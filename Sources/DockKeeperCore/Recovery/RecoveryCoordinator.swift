import Foundation
import CoreGraphics

/// A durable note that corrections are suspended (DK-FR-009), so a process that
/// is *not* the one holding the pause — `dockkeeper status`, `--diagnostics` —
/// can still see it. Pause is otherwise pure in-process state, and a menu-bar-only
/// app gives support nowhere else to look (#36, ADR-014).
///
/// Follows `ScreenShareHideRecord`'s shape for the same reasons (ADR-013): one
/// key, one JSON blob, so a single `set` is atomic and can never be read
/// half-written, and an undecodable value degrades to `nil` — "not paused",
/// which is the safe answer everywhere. A struct rather than a bare `Bool` so
/// the deadline rides along and a later field needs no key migration.
///
/// **This record is not meant to outlive the process that wrote it**: ADR-014
/// makes a restart an implicit resume. Two things enforce that, and only the
/// second is a guarantee — `AppState.prepareForTermination()` clears it on a
/// trappable quit, and `AppState.resumeStalePauseIfNeeded()` clears it at the
/// next launch regardless. A record read while DockKeeper is running therefore
/// always describes the running instance.
///
/// It *can* be read while DockKeeper is not running: an untrappable exit —
/// SIGKILL, Force Quit, a crash, the logout kill — leaves it behind until the
/// next launch. (An ordinary ⌘Q used to do this too, which is why the teardown
/// clear exists.) The reported age is what exposes such a record, exactly as it
/// does for a leftover screen-share hide.
public struct PauseRecord: Codable, Sendable, Equatable {

    /// When the pause was taken.
    public let pausedAt: Date

    /// When a timed pause auto-resumes; `nil` for a pause that runs until an
    /// explicit resume. That `nil` is the state worth reporting loudest — it has
    /// no timer at all, so nothing but a resume ever ends it.
    public let pausedUntil: Date?

    public init(pausedAt: Date = Date(), pausedUntil: Date? = nil) {
        self.pausedAt = pausedAt
        self.pausedUntil = pausedUntil
    }
}

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

    /// Writes (or clears) the durable pause record — ADR-014. Injected like
    /// `applyEdge`/`applyPin` rather than reaching for `Settings`, so the
    /// coordinator stays drivable from tests with no defaults domain at all.
    /// Defaults to a no-op: a coordinator nobody wired persistence into simply
    /// keeps pause in memory, which is the pre-ADR-014 behaviour.
    private let persistPause: @MainActor (PauseRecord?) -> Void

    /// Bumped on every admitted event; stale passes see a mismatch and no-op.
    private var pendingGeneration = 0

    /// Bumped on every pause/resume; a stale auto-resume timer sees a mismatch
    /// and no-ops (same generation-counter pattern as reconcile passes).
    private var pauseGeneration = 0

    /// When the current timed pause auto-resumes; `nil` when not paused or
    /// paused until an explicit resume. Readable for the menu.
    public private(set) var pausedUntil: Date?

    /// When the current pause was taken; `nil` when not paused. Held so the
    /// persisted record keeps one stable timestamp instead of re-stamping
    /// itself on every `notifyState()`.
    private var pausedAt: Date?

    /// What `persistPause` was last handed, so `syncPauseRecord()` writes only
    /// on a real change. `notifyState()` also runs on every reconcile, and
    /// re-writing an unchanged key would spend the DK-NFR-001 quietness budget
    /// to say nothing new.
    private var persistedPause: PauseRecord?

    /// Whether corrections are currently suspended (DK-FR-009).
    public var isPaused: Bool { machine.state == .paused }

    public init(
        machine: RecoveryMachine = RecoveryMachine(),
        inputProvider: @escaping @MainActor (_ includesPinning: Bool) -> ReconcileInput,
        applyEdge: @escaping @MainActor (DockOrientation) -> Void,
        applyPin: @escaping @MainActor (CGDirectDisplayID) -> PinOutcome,
        now: @escaping @MainActor () -> Date = { Date() },
        schedule: Scheduler? = nil,
        persistPause: @escaping @MainActor (PauseRecord?) -> Void = { _ in }
    ) {
        self.machine = machine
        self.persistPause = persistPause
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
                    switch MainDisplayPinner.decide(snapshot: snapshot, resolution: resolution, dockEdge: settings.lockEdge) {
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
                //
                // Opt-in window restore (ADR-010): capture window geometry
                // against the pre-pin display list, then move each window back
                // after a successful re-base. No-op unless the setting is on
                // and Accessibility is granted; never prompts from here.
                let restoreLayout = settings.preserveWindowLayout && WindowLayoutPreserver.isTrusted()
                let preSnapshot = restoreLayout
                    ? WindowLayoutPreserver.snapshot(displays: DisplayManager.activeDisplays())
                    : nil
                let outcome = MainDisplayPinner().pin(toDisplayID: id, dockEdge: settings.lockEdge)
                if let preSnapshot, outcome == .pinned {
                    WindowLayoutPreserver.restore(preSnapshot, displaysAfter: DisplayManager.activeDisplays())
                }
                return outcome
            },
            persistPause: { settings.pauseRecord = $0 }
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
        pauseGeneration += 1    // strands any pending auto-resume timer
        pausedUntil = nil
        pausedAt = nil
        machine.noteDisabled()
        notifyState()
    }

    /// Full reconcile on demand (settings edited in-app, display picked, etc.).
    public func requestReconcile() {
        handle(.enabled)
    }

    // MARK: - Pause (DK-FR-009)

    /// Suspend corrections. `duration == nil` pauses until an explicit
    /// `resume()`; otherwise the injected scheduler auto-resumes after
    /// `duration` seconds. Any in-flight reconcile is stranded, and a second
    /// pause supersedes the first (its timer strands on the generation bump).
    /// A no-op while disabled — there is nothing to suspend.
    public func pause(for duration: TimeInterval?) {
        guard machine.state != .disabled else { return }
        pendingGeneration += 1  // strand any in-flight reconcile pass
        pauseGeneration += 1
        let generation = pauseGeneration
        machine.notePaused()
        // One clock read for both stamps, so `pausedUntil - pausedAt` is exactly
        // the requested duration rather than that minus a scheduling hiccup.
        let startedAt = now()
        pausedAt = startedAt
        if let duration {
            pausedUntil = startedAt.addingTimeInterval(duration)
            schedule(duration) { [weak self] in
                guard let self, generation == self.pauseGeneration else { return }
                self.resume()
            }
        } else {
            pausedUntil = nil
        }
        notifyState()
    }

    /// Resume from a pause and immediately re-enforce the edge/pin via a full
    /// reconcile. A manual resume strands any pending auto-resume timer through
    /// the generation bump. A no-op unless currently paused.
    public func resume() {
        guard machine.state == .paused else { return }
        pauseGeneration += 1    // strand a pending auto-resume timer
        pausedUntil = nil
        pausedAt = nil
        machine.noteResumed()
        notifyState()
        requestReconcile()
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
        //
        // `displaysReady` gates this for the same reason the machine refuses to
        // act on a mid-transition topology: a decision computed against an empty
        // display list is an artifact, not a decision — it collapses to
        // `.noPreference`, which would clear a live explanation and then restore
        // it a pass later. On wake and replug, the bursty paths, that made the
        // menu note blink and defeated the transition de-duplication downstream.
        if includesPinning, input.displaysReady, case .terminal(let outcome) = input.pinDecision {
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
        syncPauseRecord()
        onStateChange?(machine.state)
    }

    /// Keep the durable record in step with `machine.state`.
    ///
    /// Deliberately hung off `notifyState()` — the one funnel every state
    /// change already passes through (`enable`, `disable`, `pause`, `resume`,
    /// and the reconcile pass) — rather than off the three pause-adjacent call
    /// sites. The record then cannot disagree with the state it describes, and
    /// a fourth path out of `.paused` added later inherits the write for free
    /// instead of silently leaking a stale "paused" into every support report.
    private func syncPauseRecord() {
        let desired: PauseRecord? = machine.state == .paused
            ? PauseRecord(pausedAt: pausedAt ?? now(), pausedUntil: pausedUntil)
            : nil
        guard desired != persistedPause else { return }
        persistedPause = desired
        persistPause(desired)
    }
}
