import Foundation

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
    }

    /// Poll cadence for the capture check. A constant, not a user setting:
    /// there is no capture-state event source (Principle 19 is satisfied by the
    /// absence of one — the private flag is poll-only), and 3 s is a comfortable
    /// trade between "Dock hides promptly when a share starts" and "two cheap C
    /// calls, only while the feature is on and a capture may be running." If
    /// field evidence ever wants it tunable, promote it to `Settings`.
    public nonisolated static let defaultCheckInterval: TimeInterval = 3

    /// Whether *we* currently have the Dock hidden (auto-hide ON at our hand).
    /// Authoritative for restore: we restore iff this is true, never guessing
    /// from the live auto-hide value (which the user could have changed).
    public private(set) var weHidIt = false

    /// Fired after a real hide/restore transition, so the app layer can write a
    /// `FileDiagnostics` note (kept app-side to match the pin/state pattern).
    public var onTransition: (@MainActor (Transition) -> Void)?

    private var timer: Timer?
    private let probe: @MainActor () -> Bool

    /// - Parameter probe: capture-state source; defaults to the live private
    ///   detector. Injectable so a future integration test can drive it without
    ///   the private API (the pure `decide` is the unit surface today).
    public init(probe: @escaping @MainActor () -> Bool = { ScreenCapture.isCapturing() }) {
        self.probe = probe
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
        let currentAutoHide = CoreDock.getAutoHideEnabled() ?? false
        let action = Self.decide(capturing: capturing, weHidIt: weHidIt, currentAutoHide: currentAutoHide)
        switch action {
        case .none:
            break
        case .hide:
            if CoreDock.setAutoHideEnabled(true) {
                weHidIt = true
                Log.dock.info("Hid Dock for screen capture (auto-hide on)")
                onTransition?(.hidden)
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

    private func performRestore() {
        _ = CoreDock.setAutoHideEnabled(false)
        weHidIt = false
        Log.dock.info("Restored Dock after screen capture (auto-hide off)")
        onTransition?(.restored)
    }
}
