import Testing
import Foundation
import CoreGraphics
@testable import DockKeeperCore

// MARK: - RecoveryMachine (pure core)

@Suite("RecoveryMachine.decide")
struct RecoveryDecideTests {

    @Test("Edge drift produces a setEdge effect")
    func edgeDrift() {
        let input = ReconcileInput(currentEdge: .bottom, desiredEdge: .left)
        #expect(RecoveryMachine.decide(input: input) == [.setEdge(.left)])
    }

    @Test("Unreadable edge counts as drift")
    func unknownEdgeIsDrift() {
        let input = ReconcileInput(currentEdge: nil, desiredEdge: .bottom)
        #expect(RecoveryMachine.decide(input: input) == [.setEdge(.bottom)])
    }

    @Test("Aligned edge and no pin work is a no-op")
    func aligned() {
        let input = ReconcileInput(currentEdge: .left, desiredEdge: .left)
        #expect(RecoveryMachine.decide(input: input).isEmpty)
    }

    @Test("Pin reconfigure decision adds a pin effect")
    func pinIncluded() {
        let input = ReconcileInput(
            currentEdge: .left, desiredEdge: .left,
            pinDecision: .reconfigure(7)
        )
        #expect(RecoveryMachine.decide(input: input) == [.pin(7)])
    }

    @Test("Edge-only passes skip pinning (space change / poll — TDD §8.1)")
    func edgeOnlySkipsPin() {
        let input = ReconcileInput(
            currentEdge: .left, desiredEdge: .left,
            includesPinning: false,
            pinDecision: .reconfigure(7)
        )
        #expect(RecoveryMachine.decide(input: input).isEmpty)
    }
}

@Suite("RecoveryMachine")
struct RecoveryMachineTests {

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func enabledMachine(_ config: RecoveryMachine.Config = RecoveryMachine.Config()) -> RecoveryMachine {
        var machine = RecoveryMachine(config: config)
        machine.noteEnabled()
        return machine
    }

    @Test("Disabled machine ignores events")
    func disabledIgnoresEvents() {
        let machine = RecoveryMachine()
        #expect(!machine.shouldProcess(.wake, now: t0))
    }

    @Test("Self-inflicted reconfiguration echo is swallowed inside the window")
    func echoSwallowed() {
        var machine = enabledMachine()
        machine.notePinApplied(now: t0)
        #expect(!machine.shouldProcess(.displayReconfigured, now: t0.addingTimeInterval(1.0)))
        #expect(!machine.shouldProcess(.screenParametersChanged, now: t0.addingTimeInterval(1.0)))
        // Non-display events are never treated as echoes.
        #expect(machine.shouldProcess(.wake, now: t0.addingTimeInterval(1.0)))
        // Outside the window the same event is processed again.
        #expect(machine.shouldProcess(.displayReconfigured, now: t0.addingTimeInterval(2.5)))
    }

    @Test("Converged pass settles into Monitoring")
    func convergedSettles() {
        var machine = enabledMachine()
        let result = machine.reconcile(
            passIndex: 0,
            input: ReconcileInput(currentEdge: .bottom, desiredEdge: .bottom),
            now: t0
        )
        #expect(result.effects.isEmpty)
        #expect(result.nextPassDelay == nil)
        #expect(result.state == .monitoring)
    }

    @Test("Primary mechanism unavailable settles into Degraded")
    func degradedSteadyState() {
        var machine = enabledMachine()
        let result = machine.reconcile(
            passIndex: 0,
            input: ReconcileInput(currentEdge: .bottom, desiredEdge: .bottom, primaryMechanismAvailable: false),
            now: t0
        )
        #expect(result.state == .degraded)
    }

    @Test("Absent preferred display settles into PreferredDisplayMissing; edge-only passes keep it")
    func preferredDisplayMissing() {
        var machine = enabledMachine()
        var result = machine.reconcile(
            passIndex: 0,
            input: ReconcileInput(
                currentEdge: .bottom, desiredEdge: .bottom,
                pinDecision: .terminal(.displayNotConnected)
            ),
            now: t0
        )
        #expect(result.state == .preferredDisplayMissing)

        // A poll/space-change (edge-only) pass learns nothing about the display
        // and must not clear the standing state.
        result = machine.reconcile(
            passIndex: 0,
            input: ReconcileInput(currentEdge: .bottom, desiredEdge: .bottom, includesPinning: false),
            now: t0.addingTimeInterval(30)
        )
        #expect(result.state == .preferredDisplayMissing)
    }

    @Test("Drifting pass applies and schedules the ladder; persistent drift exhausts to Error")
    func ladderExhaustion() {
        var machine = enabledMachine()
        let drifting = ReconcileInput(currentEdge: .bottom, desiredEdge: .left)

        let pass0 = machine.reconcile(passIndex: 0, input: drifting, now: t0)
        #expect(pass0.effects == [.setEdge(.left)])
        #expect(pass0.nextPassDelay == 1.5)
        #expect(pass0.state == .restoring)

        let pass1 = machine.reconcile(passIndex: 1, input: drifting, now: t0.addingTimeInterval(1.5))
        #expect(pass1.effects == [.setEdge(.left)])
        #expect(pass1.nextPassDelay == 4.0)

        let pass2 = machine.reconcile(passIndex: 2, input: drifting, now: t0.addingTimeInterval(5.5))
        #expect(pass2.effects == [.setEdge(.left)])
        #expect(pass2.nextPassDelay == 4.0)

        // Final pass is check-only: still drifting → give up until next event.
        let pass3 = machine.reconcile(passIndex: 3, input: drifting, now: t0.addingTimeInterval(9.5))
        #expect(pass3.effects.isEmpty)
        #expect(pass3.nextPassDelay == nil)
        #expect(pass3.state == .error(.notConverging))
    }

    @Test("Wake before displays are ready climbs the ladder without acting")
    func displaysNotReadyRetries() {
        var machine = enabledMachine()
        let notReady = ReconcileInput(currentEdge: nil, desiredEdge: .left, displaysReady: false)

        let pass0 = machine.reconcile(passIndex: 0, input: notReady, now: t0)
        #expect(pass0.effects.isEmpty)
        #expect(pass0.nextPassDelay == 1.5)
        #expect(pass0.state == .restoring)

        // Displays come up before the ladder ends → normal convergence.
        let ready = ReconcileInput(currentEdge: .left, desiredEdge: .left)
        let pass1 = machine.reconcile(passIndex: 1, input: ready, now: t0.addingTimeInterval(1.5))
        #expect(pass1.state == .monitoring)
    }

    @Test("Cooldown budget: more than 6 corrections in 60s stops the fight (DK-FR-003 S4)")
    func oscillationGuard() {
        var machine = enabledMachine()
        let drifting = ReconcileInput(currentEdge: .bottom, desiredEdge: .left)

        // Six event-triggered corrections inside the window (fresh pass 0 each
        // time — an external agent keeps moving the Dock back).
        for i in 0..<6 {
            let result = machine.reconcile(passIndex: 0, input: drifting, now: t0.addingTimeInterval(Double(i) * 5))
            #expect(result.effects == [.setEdge(.left)], "correction \(i) should still apply")
        }

        // The seventh within the window trips the breaker.
        let tripped = machine.reconcile(passIndex: 0, input: drifting, now: t0.addingTimeInterval(30))
        #expect(tripped.effects.isEmpty)
        #expect(tripped.state == .error(.oscillation))

        // Once the window has drained, corrections resume (next event recovers).
        var recovered = machine
        recovered.noteEnabled()
        let later = recovered.reconcile(passIndex: 0, input: drifting, now: t0.addingTimeInterval(120))
        #expect(later.effects == [.setEdge(.left)])
    }

    @Test("Disable clears in-flight bookkeeping")
    func disableResets() {
        var machine = enabledMachine()
        _ = machine.reconcile(passIndex: 0, input: ReconcileInput(currentEdge: .bottom, desiredEdge: .left), now: t0)
        machine.noteDisabled()
        #expect(machine.state == .disabled)
        let result = machine.reconcile(passIndex: 1, input: ReconcileInput(currentEdge: .bottom, desiredEdge: .left), now: t0)
        #expect(result.effects.isEmpty)
        #expect(result.state == .disabled)
    }
}

// MARK: - RecoveryCoordinator (orchestration with fakes)

@MainActor
private final class Harness {
    var scheduled: [(delay: TimeInterval, block: @MainActor () -> Void)] = []
    var appliedEdges: [DockOrientation] = []
    var appliedPins: [CGDirectDisplayID] = []
    var pinOutcomes: [PinOutcome] = []
    var states: [RecoveryState] = []
    var now = Date(timeIntervalSinceReferenceDate: 2_000_000)

    /// Inputs consumed FIFO; the last one sticks when the queue drains.
    var inputs: [ReconcileInput]

    let coordinator: RecoveryCoordinator

    init(inputs: [ReconcileInput], config: RecoveryMachine.Config = RecoveryMachine.Config()) {
        self.inputs = inputs
        var harnessSelf: Harness!
        self.coordinator = RecoveryCoordinator(
            machine: RecoveryMachine(config: config),
            inputProvider: { includesPinning in
                var input = harnessSelf.inputs.count > 1 ? harnessSelf.inputs.removeFirst() : harnessSelf.inputs[0]
                input.includesPinning = includesPinning
                return input
            },
            applyEdge: { harnessSelf.appliedEdges.append($0) },
            applyPin: { id in
                harnessSelf.appliedPins.append(id)
                return .pinned
            },
            now: { harnessSelf.now },
            schedule: { delay, block in
                harnessSelf.scheduled.append((delay, block))
            }
        )
        harnessSelf = self
        coordinator.onStateChange = { [weak self] in self?.states.append($0) }
        coordinator.onPinOutcome = { [weak self] in self?.pinOutcomes.append($0) }
    }

    /// Run every scheduled block in order (blocks may schedule more).
    func runAllScheduled() {
        while !scheduled.isEmpty {
            let next = scheduled.removeFirst()
            next.block()
        }
    }

    func runNextScheduled() {
        guard !scheduled.isEmpty else { return }
        scheduled.removeFirst().block()
    }
}

private let drifting = ReconcileInput(currentEdge: .bottom, desiredEdge: .left)
private let aligned = ReconcileInput(currentEdge: .left, desiredEdge: .left)

@Suite("RecoveryCoordinator")
@MainActor
struct RecoveryCoordinatorTests {

    @Test("Duplicate display events produce a single recovery attempt (DK-FR-003 S2)")
    func duplicateEventsProduceSingleAttempt() {
        let harness = Harness(inputs: [drifting, aligned])
        harness.coordinator.enable()  // schedules the initial reconcile

        // A burst: two more events land inside the debounce window.
        harness.coordinator.handle(.displayReconfigured)
        harness.coordinator.handle(.screenParametersChanged)
        #expect(harness.scheduled.count == 3)

        // All three fire; the two stale generations no-op.
        harness.runAllScheduled()
        #expect(harness.appliedEdges == [.left], "burst must coalesce to one correction")
        #expect(harness.coordinator.state == .monitoring)
    }

    @Test("Wake with slow displays converges through the ladder (DK-FR-003 S1)")
    func wakeLadderConverges() {
        let notReady = ReconcileInput(currentEdge: nil, desiredEdge: .left, displaysReady: false)
        let harness = Harness(inputs: [notReady, notReady, drifting, aligned])
        harness.coordinator.enable()

        harness.runAllScheduled()

        // pass0 (not ready) → +1.5 s; pass1 (not ready) → +4 s; pass2 applies →
        // +4 s verify; pass3 converged. Delay 0 is the debounced intake.
        #expect(harness.appliedEdges == [.left])
        #expect(harness.coordinator.state == .monitoring)
    }

    @Test("Echo of our own pin is swallowed (DK-FR-003 S3)")
    func echoSuppressed() {
        var pinning = aligned
        pinning.pinDecision = .reconfigure(9)
        let harness = Harness(inputs: [pinning, aligned])
        harness.coordinator.enable()
        harness.runAllScheduled()
        #expect(harness.appliedPins == [9])
        #expect(harness.pinOutcomes.first == .pinned)

        // The pin emits a display-reconfiguration event right back at us.
        let before = harness.scheduled.count
        harness.coordinator.handle(.displayReconfigured)
        #expect(harness.scheduled.count == before, "echo must not schedule another pass")

        // A wake event is not an echo and passes through.
        harness.coordinator.handle(.wake)
        #expect(harness.scheduled.count == before + 1)
    }

    @Test("An external agent fighting us trips the cooldown into Error (DK-FR-003 S4)")
    func oscillationStops() {
        let harness = Harness(inputs: [drifting])  // drift forever
        harness.coordinator.enable()
        harness.scheduled.removeAll()  // strand the initial pass; events drive this test

        // Each event applies one correction (its verify passes are stranded by
        // the next event's generation bump — like real bursts would).
        for i in 0..<6 {
            harness.now = harness.now.addingTimeInterval(5)
            harness.coordinator.handle(.displayReconfigured)
            harness.runNextScheduled()
            harness.scheduled.removeAll()
            #expect(harness.appliedEdges.count == i + 1)
        }

        harness.now = harness.now.addingTimeInterval(5)
        harness.coordinator.handle(.displayReconfigured)
        harness.runNextScheduled()
        #expect(harness.appliedEdges.count == 6, "the breaker must stop the seventh correction")
        #expect(harness.coordinator.state == .error(.oscillation))
    }

    @Test("Poll-caught drift is counted for ADR-005 evidence (DK-FR-003 S5)")
    func pollCountsDrift() {
        let harness = Harness(inputs: [drifting, aligned])
        harness.coordinator.enable()
        harness.runAllScheduled()
        harness.inputs = [drifting, aligned]

        harness.coordinator.handle(.pollTick)
        #expect(harness.scheduled.first?.delay == 0, "poll passes skip the debounce")
        harness.runAllScheduled()
        #expect(harness.coordinator.pollCaughtDriftCount == 1)
    }

    @Test("Terminal pin decisions still surface their explanation to the UI")
    func terminalPinOutcomeSurfaces() {
        var declined = aligned
        declined.pinDecision = .terminal(.unsupportedSeparateSpaces)
        let harness = Harness(inputs: [declined])
        harness.coordinator.enable()
        harness.runAllScheduled()
        #expect(harness.pinOutcomes.contains(.unsupportedSeparateSpaces))
        #expect(harness.appliedPins.isEmpty)
    }

    @Test("Disable strands in-flight passes; no residual corrections (DK-FR-004 S1)")
    func disableStrandsPasses() {
        let harness = Harness(inputs: [drifting])
        harness.coordinator.enable()
        harness.coordinator.handle(.wake)
        harness.coordinator.disable()
        harness.runAllScheduled()
        #expect(harness.appliedEdges.isEmpty)
        #expect(harness.coordinator.state == .disabled)

        // Events while disabled are ignored entirely.
        harness.coordinator.handle(.wake)
        #expect(harness.scheduled.isEmpty)
    }
}
