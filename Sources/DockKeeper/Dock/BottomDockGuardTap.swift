import ApplicationServices
import CoreGraphics
import DockKeeperCore
import Foundation

/// The side-effecting half of DK-FR-014: a `CGEventTap` that holds the pointer
/// off the bottom trigger row of every display the Dock should not be summoned
/// to (ADR-015).
///
/// All policy lives in `BottomDockGuard`; this type owns only the tap's
/// lifecycle and the per-event coordinate edit. Split per TDD rule 8 — the
/// decision is pure and exhaustively unit-tested, while this adapter is
/// deliberately thin because the test target cannot reach it.
///
/// **Failure is always silent and safe.** No grant, a refused tap, a revoked
/// grant mid-session, or a system-disabled tap all end with the pointer moving
/// normally. The tap holds no persistent state and dies with the process, so
/// unlike the borrowed auto-hide of ADR-013 there is nothing to repair at the
/// next launch.
@MainActor
final class BottomDockGuardTap {

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// The bands currently held. Read by the C callback through `Unmanaged`, so
    /// it must only ever be mutated on the main actor.
    private var zones: [BottomDockGuard.ClampZone] = []

    /// Number of clamps applied since the tap was armed — the counter the spike
    /// used to tell a working tap from a broken one, and the same thing support
    /// needs to answer "is it doing anything?".
    private(set) var clampCount: Int = 0

    /// How many times macOS disabled the tap and we re-enabled it. A climbing
    /// value means the callback is too slow and is worth surfacing.
    private(set) var reenableCount: Int = 0

    var isActive: Bool { tap != nil }

    /// Applies a decision. Idempotent: re-applying the same zones keeps the
    /// existing tap rather than tearing it down, so a reconcile storm cannot
    /// thrash the pointer.
    func apply(_ decision: BottomDockGuard.Decision) {
        switch decision {
        case .idle:
            stop()
        case .guarding(let newZones):
            zones = newZones
            if tap == nil { start() }
        }
    }

    // MARK: - Lifecycle

    private func start() {
        // Checked again here rather than trusted from the decision: the grant
        // can be revoked between the snapshot and this call, and
        // CGEventTapCreate would then hand back a port that never fires.
        guard AXIsProcessTrusted() else {
            Log.app.notice("Bottom-Dock guard: not starting, Accessibility not granted")
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // must be able to modify, not just observe
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let guardTap = Unmanaged<BottomDockGuardTap>.fromOpaque(userInfo)
                    .takeUnretainedValue()
                return guardTap.handle(type: type, event: event)
            },
            userInfo: context
        ) else {
            Log.app.error("Bottom-Dock guard: CGEventTapCreate returned nil; guard inactive")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)

        tap = created
        source = runLoopSource
        clampCount = 0
        reenableCount = 0
        Log.app.notice("Bottom-Dock guard: armed over \(self.zones.count, privacy: .public) display(s)")
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
        zones = []
        Log.app.notice("Bottom-Dock guard: released")
    }

    // MARK: - Per-event

    /// Called on the run loop that owns the tap — the main run loop, so the
    /// `@MainActor` isolation this type declares actually holds. Kept short on
    /// purpose: a slow callback is what makes macOS disable the tap.
    private nonisolated func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that takes too long, and one that stays disabled
        // silently stops guarding. Re-arm rather than fail open in silence.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let label = String(describing: type)
            MainActor.assumeIsolated { self.reenable(after: label) }
            return Unmanaged.passUnretained(event)
        }

        // `CGEvent` is not `Sendable`, so only the location crosses into the
        // actor; the event itself is mutated back out here. Keeping the isolated
        // region to a pure point-in/point-out also keeps it short, which is what
        // stops macOS disabling the tap for being slow.
        let location = event.location
        let clamped: CGPoint? = MainActor.assumeIsolated {
            guard let clamped = BottomDockGuard.clamp(location, zones: self.zones) else {
                return nil
            }
            self.clampCount += 1
            return clamped
        }
        if let clamped { event.location = clamped }
        return Unmanaged.passUnretained(event)
    }

    private func reenable(after reason: String) {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        reenableCount += 1
        Log.app.notice("Bottom-Dock guard: tap re-enabled after \(reason, privacy: .public)")
    }

    // No `deinit` cleanup, deliberately. The port is main-actor isolated and a
    // `deinit` is not, so it cannot legally touch it — and it does not need to.
    // An event tap is owned by the process: it stops filtering the moment the
    // process exits, by any route, including SIGKILL. That is the whole reason
    // this feature needs no launch-time repair, unlike the borrowed Dock
    // auto-hide of ADR-013, which survives its owner and therefore does.
    // `AppState.prepareForTermination()` calls `stop()` for the ordinary path.
}
