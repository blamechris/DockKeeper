import Foundation

/// Persisted note that DockKeeper is holding Dock auto-hide ON for a screen
/// capture right now (DK-FR-013, ADR-013).
///
/// `weHidIt` is in-memory only, so a process that is SIGKILLed, force-quit,
/// crashes, or is killed at logout takes the only record of "this auto-hide is
/// ours" with it. The next launch then reads `weHidIt == false` with auto-hide
/// ON, and `decide` — correctly, per ADR-011 — treats that as "the user runs
/// auto-hide, never touch it", forever. This record is what survives that death.
///
/// It carries a timestamp and nothing else. In particular it does **not**
/// identify the writing process: a pid-keyed owner would need a liveness check
/// to mean anything, pids recycle (the same reason ADR-012 ranks by start time
/// before pid), and a liveness check that wrongly answered "owner still alive"
/// would block the repair forever — reinstating the unrecoverable state this
/// record exists to remove. Two live instances are handled instead by the fact
/// that both read the same global capture state and reach the same conclusion
/// (ADR-013, "Two instances").
public struct ScreenShareHideRecord: Codable, Sendable, Equatable {

    /// When the hide was taken. Used only as an **upper bound** on how long the
    /// user has been able to see — and act on — the leftover auto-hide: the real
    /// exposure window opens when we died, which is not observable from here.
    /// Over-estimating exposure errs toward *not* restoring, the safe direction.
    public let hiddenAt: Date

    public init(hiddenAt: Date = Date()) {
        self.hiddenAt = hiddenAt
    }
}

/// Hides the Dock (by turning macOS Dock auto-hide ON) while the screen is being
/// captured/recorded, and restores it (auto-hide back OFF) when capture stops —
/// DK-FR-011, ADR-011. Opt-in, off by default.
///
/// Mechanism split, mirroring the rest of the engine (kickoff rule 8): a **pure**
/// `decide` core holds every rule and is exhaustively unit-tested; the
/// side-effecting `evaluate` reads/writes `CoreDock` auto-hide and logs. Tests
/// never touch the private APIs — they drive `decide` directly.
///
/// The governing invariant (ADR-011): we only ever *change* auto-hide when the
/// user did **not** already have it on. So the only prior state we can restore
/// to is "off" — which is why a single `weHidIt` flag is sufficient and no prior
/// value needs storing. If the user runs auto-hide themselves, we never touch
/// it, and therefore never "restore" something we didn't change.
///
/// That sufficiency argument is about the restore *value*, and it still holds.
/// What it silently carried — the *fact that we hid at all* — does not survive
/// the process, so ADR-013 makes the flag durable: a `ScreenShareHideRecord` is
/// written before the hide and cleared after the restore, and `repair` reconciles
/// the two at launch. Without it, a SIGKILL/crash/logout kill leaves auto-hide ON
/// with `weHidIt == false`, which `decide` reads as "the user runs auto-hide"
/// forever (issue #29).
///
/// Main-actor because it owns a `Timer` and mutates `weHidIt`; the CoreDock
/// calls themselves are process-wide but cheap.
@MainActor
public final class ScreenShareHider {

    /// The three things a reconcile of capture-state can conclude.
    public enum Action: Sendable, Equatable {
        /// Do nothing (already in the right state, or the user owns auto-hide).
        case none
        /// Turn auto-hide ON to hide the Dock, and record that we did it
        /// (prior state is necessarily "off" — see the type doc).
        case hide
        /// Turn auto-hide back OFF (only reachable when we hid it), and clear
        /// the flag.
        case restore
    }

    /// A completed hide/restore transition, surfaced for the diagnostics note.
    /// State only — no PII (DK-PRIV-001 S2).
    public enum Transition: String, Sendable {
        case hidden
        case restored
        /// A restore that undid a hide left behind by a *previous*, killed
        /// process (DK-FR-013) rather than one this process took.
        case repaired
        /// A user-initiated "Turn Off Dock Auto-Hide" (DK-FR-013 S11). The only
        /// transition that is not gated on us having hidden anything.
        case manual
    }

    /// What a launch-time reconcile of a persisted hide record can conclude.
    public enum Repair: Sendable, Equatable {
        /// Leave everything alone — nothing was left behind, or we may not act.
        case none
        /// Drop the record without touching the Dock: the auto-hide on screen is
        /// not, or is no longer, attributable to us.
        case discard
        /// A capture is still running and the poll is about to start: take
        /// ownership of the leftover hide so the normal capture-stop restore
        /// puts it back — restoring now would show the Dock mid-share.
        case adopt
        /// Turn auto-hide back OFF and drop the record.
        case restore
    }

    /// Poll cadence for the capture check. A constant, not a user setting:
    /// there is no capture-state event source (Principle 19 is satisfied by the
    /// absence of one — the private flag is poll-only), and 3 s is a comfortable
    /// trade between "Dock hides promptly when a share starts" and "two cheap C
    /// calls, only while the feature is on and a capture may be running." If
    /// field evidence ever wants it tunable, promote it to `Settings`.
    public nonisolated static let defaultCheckInterval: TimeInterval = 3

    /// How long after a hide the record still counts as ours.
    ///
    /// A constant, not a user setting (same reasoning as `defaultCheckInterval`),
    /// and **not** a precision instrument: it bounds a quantity that cannot be
    /// measured. Inside it, a leftover auto-hide is overwhelmingly ours; outside
    /// it the user has lived with the auto-hiding Dock long enough that the
    /// setting is theirs by acquiescence, whoever wrote it.
    ///
    /// 7 days because the repair must survive the realistic relaunch paths — the
    /// dev loop (seconds), a manual relaunch (minutes), and the dominant one, the
    /// login item at the next login (hours to days; a long weekend is the tail) —
    /// while still expiring, so a record that outlived an uninstall, a Time
    /// Machine restore, or a machine migration never fires an automatic Dock
    /// write. Beyond the window the recovery is the manual command, which is what
    /// makes a *finite* window affordable at all.
    ///
    /// Known bound, stated rather than engineered around: the stamp is taken at
    /// the hide and never refreshed, so a *single* capture that runs longer than
    /// the window (a permanently-connected Screen Sharing session on a headless
    /// Mac, say) and is then killed leaves a record that repairs to `.discard`.
    /// The outcome there is exactly the pre-fix status quo plus the manual
    /// recovery (DK-FR-013 S11); re-stamping would cost a `Settings` read on
    /// every 3 s tick against DK-NFR-001, which ADR-013 declined.
    public nonisolated static let repairWindow: TimeInterval = 7 * 24 * 3600

    /// Whether *we* currently have the Dock hidden (auto-hide ON at our hand).
    /// Authoritative for restore: we restore iff this is true, never guessing
    /// from the live auto-hide value (which the user could have changed).
    public private(set) var weHidIt = false

    /// Fired after a real hide/restore transition, so the app layer can write a
    /// `FileDiagnostics` note (kept app-side to match the pin/state pattern).
    public var onTransition: (@MainActor (Transition) -> Void)?

    private var timer: Timer?
    private let probe: @MainActor () -> Bool
    private let readAutoHide: @MainActor () -> Bool?
    private let writeAutoHide: @MainActor (Bool) -> Bool
    private let settings: Settings

    /// - Parameters:
    ///   - probe: capture-state source; defaults to the live private detector.
    ///   - readAutoHide: current Dock auto-hide value, `nil` when the private
    ///     symbol is unavailable. Defaults to the live `CoreDock` read.
    ///   - writeAutoHide: set Dock auto-hide; returns `false` when the private
    ///     symbol is unavailable. Defaults to the live `CoreDock` write.
    ///   - settings: where the durable hide record lives (DK-FR-013). Injected
    ///     for the same reason as the ports: a test must never write a record
    ///     into the real `com.dockkeeper.app` domain.
    ///
    /// All four are injected rather than called statically (kickoff rule 8) so
    /// the *side-effecting* half of this type — in particular the teardown /
    /// restore contract that DK-FR-013 depends on — is unit-testable without
    /// ever moving the real Dock. Production always passes the defaults; only
    /// tests substitute.
    public init(
        probe: @escaping @MainActor () -> Bool = { ScreenCapture.isCapturing() },
        readAutoHide: @escaping @MainActor () -> Bool? = { CoreDock.getAutoHideEnabled() },
        writeAutoHide: @escaping @MainActor (Bool) -> Bool = { CoreDock.setAutoHideEnabled($0) },
        settings: Settings = .shared
    ) {
        self.probe = probe
        self.readAutoHide = readAutoHide
        self.writeAutoHide = writeAutoHide
        self.settings = settings
    }

    // MARK: - Pure decision core (exhaustively unit-tested — ADR-011)

    /// The complete rule table over `capturing × weHidIt × currentAutoHide`.
    ///
    /// - Hide only when a capture is running, we haven't already hidden, **and**
    ///   the user isn't already running auto-hide (never fight a user who set it
    ///   themselves — and by not recording a hide there, we never restore it).
    /// - On capture-stop, restore only if *we* hid it; then the flag is cleared.
    /// - Every same-state repeat is `.none` (idempotent).
    public nonisolated static func decide(capturing: Bool, weHidIt: Bool, currentAutoHide: Bool) -> Action {
        if capturing {
            if weHidIt { return .none }             // already hidden by us — idempotent
            if currentAutoHide { return .none }     // user runs auto-hide — never touch it
            return .hide
        } else {
            return weHidIt ? .restore : .none       // restore only what we changed
        }
    }

    // MARK: - Pure repair core (crash recovery — DK-FR-013, ADR-013)

    /// The complete rule table for "what does a persisted hide record mean at
    /// launch?", over `record × currentAutoHide × capturing × featureActive`.
    ///
    /// Deliberately **not** a new input to `decide`. `decide` answers a
    /// steady-state question every 3 s from three live booleans, and its
    /// exhaustive 8-row table is the documented contract of ADR-011; this answers
    /// a once-per-launch question about *provenance across a process boundary*,
    /// from inputs `decide` has no business seeing. Keeping them apart leaves
    /// `decide` untouched — and once `repair` has run, `weHidIt` and the record
    /// agree, which is exactly `decide`'s precondition.
    ///
    /// The safety property, asserted directly by test: this never returns
    /// `.restore` or `.adopt` unless `currentAutoHide == true`. It therefore can
    /// never turn off an auto-hide it did not observe as on, and never writes the
    /// Dock on the strength of the record alone.
    ///
    /// - Parameters:
    ///   - record: the persisted breadcrumb; `nil` when none survived.
    ///   - currentAutoHide: the live auto-hide value, `nil` when the private
    ///     symbol is unavailable — in which case we can neither read nor write.
    ///   - capturing: whether a capture is running *now*.
    ///   - featureActive: whether the poll will run after this call (DockKeeper
    ///     enabled, feature on, detector available). Load-bearing: adopting a
    ///     hide that nothing will later restore leaves the Dock hidden with the
    ///     record renewed, which is the bug re-armed.
    ///   - now: the clock, injected for tests.
    ///   - window: the attribution window; see `repairWindow`.
    public nonisolated static func repair(
        record: ScreenShareHideRecord?,
        currentAutoHide: Bool?,
        capturing: Bool,
        featureActive: Bool,
        now: Date = Date(),
        window: TimeInterval = ScreenShareHider.repairWindow
    ) -> Repair {
        guard let record else { return .none }                  // 1 nothing was left behind
        guard let currentAutoHide else { return .none }          // 2 can't read the Dock → can't act
        guard currentAutoHide else { return .discard }           // 3 already back off; nothing of ours remains
        let age = now.timeIntervalSince(record.hiddenAt)
        guard age >= 0 else { return .discard }                  // 4 clock moved back / restored backup
        guard age <= window else { return .discard }             // 5 too old to attribute to us
        return capturing && featureActive ? .adopt : .restore    // 6 / 7
    }

    // MARK: - Side-effecting lifecycle

    /// Begin polling the capture state on the shared run loop. Safe to call when
    /// the detector is unavailable (the timer just no-ops via `isCapturing()`),
    /// but callers should gate on `ScreenCapture.isAvailable` to avoid the spin.
    /// Idempotent: a running poll is torn down first.
    public func start(interval: TimeInterval = ScreenShareHider.defaultCheckInterval) {
        stop(restore: false)  // don't restore across a restart; keep our state
        let timer = Timer(timeInterval: max(1, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.dock.info("Screen-share Dock hide: polling started")
        tick()  // evaluate immediately so a share already in progress hides now
    }

    /// Stop polling. When `restore` is true (feature turned off / app disabled),
    /// put auto-hide back if we hid it — we must never leave the Dock hidden
    /// after the user disabled the feature.
    public func stop(restore: Bool = true) {
        timer?.invalidate()
        timer = nil
        if restore { restoreIfNeeded() }
    }

    /// One poll: read capture state, decide, and apply any transition.
    @discardableResult
    func tick() -> Action {
        evaluate(capturing: probe())
    }

    /// Evaluate a known capture state against the live auto-hide value and apply
    /// the resulting transition. The private-API reads/writes live here; the
    /// pure `decide` above is what tests exercise.
    @discardableResult
    func evaluate(capturing: Bool) -> Action {
        // Symmetric with `repair` guard 2, and required by the ADR-011
        // invariant itself: if auto-hide is unreadable we cannot tell the
        // user's own setting from ours, so we must not act — and above all must
        // not mint a record claiming a hide we could never attribute. Coalescing
        // an unreadable read to `false` would do exactly that, and would then
        // overwrite the record `repairIfNeeded` deliberately preserved for a
        // later macOS where the symbol resolves.
        guard let currentAutoHide = readAutoHide() else {
            Log.dock.debug("Screen-share evaluate skipped: Dock auto-hide is unreadable")
            return .none
        }
        let action = Self.decide(capturing: capturing, weHidIt: weHidIt, currentAutoHide: currentAutoHide)
        switch action {
        case .none:
            break
        case .hide:
            // Write-ahead (ADR-013): the record lands *before* the Dock write.
            // Killed between the two, we leave a record with auto-hide still
            // OFF, which the next launch discards for free. The opposite order
            // leaves auto-hide ON with no record — the unrecoverable state.
            settings.screenShareHideRecord = ScreenShareHideRecord()
            if writeAutoHide(true) {
                weHidIt = true
                Log.dock.info("Hid Dock for screen capture (auto-hide on)")
                onTransition?(.hidden)
            } else {
                settings.screenShareHideRecord = nil  // never claim a hide we failed to make
            }
        case .restore:
            performRestore()
        }
        return action
    }

    /// Restore auto-hide to off if we hid it. Idempotent; used on capture-stop,
    /// on feature/app teardown, and safe to call redundantly.
    public func restoreIfNeeded() {
        guard weHidIt else { return }
        performRestore()
    }

    // MARK: - Launch repair and manual recovery (DK-FR-013)

    /// One-shot launch reconcile of the persisted record.
    ///
    /// Called once per process by `AppState.init`, **before** the enable/feature
    /// gating and before `start()`: a Dock left auto-hidden by a killed process
    /// must be repaired even when the user has since turned the feature — or
    /// DockKeeper itself — off, and `applyScreenShareHiderState()` only starts
    /// the poll, it is not a repair path.
    @discardableResult
    public func repairIfNeeded(featureActive: Bool, now: Date = Date()) -> Repair {
        // Cheap, private-API-free short-circuit, and it is load-bearing rather
        // than an optimization: Swift evaluates call arguments eagerly, so
        // without it every launch would call `CGSIsScreenWatcherPresent` and
        // `CoreDockGetAutoHideEnabled` — including for the majority of users
        // who never opted in — falsifying DK-FR-011's "the private detector is
        // not touched unless the user opts in". `repair`'s guard 1 states the
        // same rule as the pure contract and stays exactly as it is.
        guard let record = settings.screenShareHideRecord else { return .none }
        let action = Self.repair(
            record: record,
            currentAutoHide: readAutoHide(),
            capturing: probe(),
            featureActive: featureActive,
            now: now
        )
        switch action {
        case .none:
            break
        case .discard:
            settings.screenShareHideRecord = nil
            Log.dock.info("Dropped a screen-share hide record that is no longer attributable")
        case .adopt:
            // The original `hiddenAt` is kept: adopting does not restart the
            // clock, so a second death is still measured from the hide the user
            // has actually been living with.
            weHidIt = true
            Log.dock.notice("Adopted a leftover screen-share Dock hide; a capture is still running")
        case .restore:
            performRestore(reason: .repaired)
        }
        return action
    }

    /// The user asking, in as many words, for Dock auto-hide to be turned off —
    /// the always-available floor under the record-based repair (DK-FR-013 S11).
    ///
    /// Unconditional by design: it is the only recovery that works for a user
    /// poisoned by a build that predates the record, or whose record was lost to
    /// a panic, a power loss, or a wiped preferences domain. It is user-initiated
    /// and plainly labelled, so it cannot surprise anyone — which is exactly why
    /// it may bypass the attribution rules that guard the *automatic* path.
    ///
    /// Returns whether the write landed (`false` only when the private symbol is
    /// unavailable, in which case nothing is claimed and the record is kept).
    @discardableResult
    public func restoreAutoHideByUserRequest() -> Bool {
        let applied = writeAutoHide(false)
        guard applied else {
            Log.dock.error("Manual Dock auto-hide restore failed: CoreDock write unavailable")
            return false
        }
        settings.screenShareHideRecord = nil
        weHidIt = false
        Log.dock.notice("Dock auto-hide turned off at the user's request")
        onTransition?(.manual)
        return true
    }

    /// The live auto-hide value, read through the same injected port the rest of
    /// this type uses, so the menu's "is this worth offering?" check can never
    /// disagree with the decision logic. `nil` when the symbol is unavailable.
    public func currentAutoHide() -> Bool? { readAutoHide() }

    private func performRestore(reason: Transition = .restored) {
        let applied = writeAutoHide(false)
        // Write-behind (ADR-013): clear only once the Dock is actually back off.
        // Killed in between, the record outlives a Dock that is already correct
        // and the next launch discards it. A failed write keeps the record, so
        // the claim outlives the failure instead of being dropped on the floor.
        if applied { settings.screenShareHideRecord = nil }
        weHidIt = false
        Log.dock.info("Restored Dock auto-hide to off (\(reason.rawValue, privacy: .public))")
        onTransition?(reason)
    }
}
