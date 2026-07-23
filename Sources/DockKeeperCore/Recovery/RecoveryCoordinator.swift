import Foundation
import CoreGraphics

/// The single owner of Dock reconciliation (TDD §4.3, §8.3, kickoff §6.9).
///
/// Consumes `DockEvent`s, debounces bursts with a generation counter (a newer
/// event abandons any in-flight pass), runs the retry ladder via the pure
/// `RecoveryMachine`, and executes the resulting effects through injected
/// closures — so tests can drive the whole lifecycle with a fake scheduler,
/// clock, and snapshot provider, and no real Dock is ever touched.
@MainActor
public final class RecoveryCoordinator {

    /// Schedules `block` after `delay` seconds. Production uses a main-actor
    /// `Task.sleep`; tests capture blocks and fire them manually.
    public typealias Scheduler = @MainActor (_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void) -> Void

    public private(set) var machine: RecoveryMachine
    public var state: RecoveryState { machine.state }

    /// Poll-caught (as opposed to event-caught) drift count — the local
    /// evidence ADR-005 wants before tuning the poll interval.
    public private(set) var pollCaughtDriftCount = 0

    /// UI hooks (the menu-bar app sets these; the CLI doesn't need them).
    public var onStateChange: (@MainActor (RecoveryState) -> Void)?
    public var onPinOutcome: (@MainActor (PinOutcome) -> Void)?

    private let inputProvider: @MainActor (_ includesPinning: Bool) -> ReconcileInput
    private let applyEdge: @MainActor (DockOrientation) -> Void
    private let applyPin: @MainActor (CGDirectDisplayID) -> PinOutcome
    private let now: @MainActor () -> Date
    private let schedule: Scheduler

    /// Bumped on every admitted event; stale passes see a mismatch and no-op.
    private var pendingGeneration = 0

    public init(
        machine: RecoveryMachine = RecoveryMachine(),
        inputProvider: @escaping @MainActor (_ includesPinning: Bool) -> ReconcileInput,
        applyEdge: @escaping @MainActor (DockOrientation) -> Void,
        applyPin: @escaping @MainActor (CGDirectDisplayID) -> PinOutcome,
        now: @escaping @MainActor () -> Date = { Date() },
        schedule: Scheduler? = nil
    ) {
        self.machine = machine
        self.inputProvider = inputProvider
        self.applyEdge = applyEdge
        self.applyPin = applyPin
        self.now = now
        self.schedule = schedule ?? { delay, block in
            Task { @MainActor in
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                block()
            }
        }
    }

    /// Production wiring over the real engine pieces.
    public convenience init(
        controller: DockController,
        settings: Settings,
        machine: RecoveryMachine
    ) {
        self.init(
            machine: machine,
            inputProvider: { includesPinning in
                var pinDecision = ReconcileInput.PinDecision.terminal(.noPreference)
                var displaysReady = true
                if includesPinning {
                    let snapshot = MainDisplayPinner.liveSnapshot()
                    displaysReady = !snapshot.displays.isEmpty
                    let resolution = DisplayIdentityResolver.resolve(
                        stored: settings.preferredDisplayFingerprint,
                        candidates: snapshot.identityCandidates
                    )
                    if case .resolved(_, let repaired?) = resolution {
                        settings.repairPreferredDisplay(repaired)  // TDD §7.3
                    }
                    switch MainDisplayPinner.decide(snapshot: snapshot, resolution: resolution) {
                    case .terminal(let outcome): pinDecision = .terminal(outcome)
                    case .reconfigure(let id): pinDecision = .reconfigure(id)
                    }
                }
                return ReconcileInput(
                    currentEdge: controller.currentOrientation(),
                    desiredEdge: settings.lockEdge,
                    primaryMechanismAvailable: !controller.isDegraded,
                    displaysReady: displaysReady,
                    includesPinning: includesPinning,
                    pinDecision: pinDecision
                )
            },
            applyEdge: { controller.forceOrientation($0) },
            applyPin: { id in
                // Placement guards re-checked on a fresh snapshot inside the
                // pinner; returns the typed outcome for the UI.
                MainDisplayPinner().pin(toDisplayID: id)
            }
        )
    }

    // MARK: - Lifecycle

    /// User enabled DockKeeper (or the app launched enabled).
    public func enable() {
        machine.noteEnabled()
        notifyState()
        handle(.enabled)
    }

    /// User disabled DockKeeper: cancel in-flight work, go dormant.
    public func disable() {
        pendingGeneration += 1  // strands any scheduled pass
        machine.noteDisabled()
        notifyState()
    }

    /// Full reconcile on demand (settings edited in-app, display picked, etc.).
    public func requestReconcile() {
        handle(.enabled)
    }

    // MARK: - Event intake

    public func handle(_ event: DockEvent) {
        guard machine.shouldProcess(event, now: now()) else { return }
        pendingGeneration += 1
        let generation = pendingGeneration
        let includesPinning = event.reconcilesPinning
        let isPoll = (event == .pollTick)
        // Poll ticks skip the debounce: they are already rate-limited and
        // should stay silent and cheap.
        let delay = isPoll ? 0 : machine.config.debounce
        schedule(delay) { [weak self] in
            self?.pass(generation: generation, index: 0, includesPinning: includesPinning, isPoll: isPoll)
        }
    }

    // MARK: - Reconcile passes

    private func pass(generation: Int, index: Int, includesPinning: Bool, isPoll: Bool) {
        guard generation == pendingGeneration else { return }  // coalesced away
        guard machine.state != .disabled else { return }

        let input = inputProvider(includesPinning)
        let result = machine.reconcile(passIndex: index, input: input, now: now())

        if isPoll && index == 0 && !result.effects.isEmpty {
            pollCaughtDriftCount += 1
            Log.dock.info("Poll caught drift the events missed (count: \(self.pollCaughtDriftCount, privacy: .public))")
        }

        for effect in result.effects {
            switch effect {
            case .setEdge(let edge):
                applyEdge(edge)
            case .pin(let displayID):
                let outcome = applyPin(displayID)
                machine.notePinApplied(now: now())
                onPinOutcome?(outcome)
            }
        }

        // Terminal pin decisions (separate Spaces, ambiguous identity, …)
        // never produce an effect, but their explanation must still reach the
        // UI; a clean `.noPreference`/`.alreadyOnTarget` clears stale notes.
        if includesPinning, case .terminal(let outcome) = input.pinDecision {
            onPinOutcome?(outcome)
        }

        notifyState()

        if let delay = result.nextPassDelay {
            schedule(delay) { [weak self] in
                self?.pass(generation: generation, index: index + 1, includesPinning: includesPinning, isPoll: isPoll)
            }
        }
    }

    private func notifyState() {
        onStateChange?(machine.state)
    }
}
