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

    /// When the current arming began, or `nil` when nothing is armed.
    ///
    /// It exists to bound the counters above, which are reset in `start()` and
    /// **not** in `stop()` — so a released tap still holds the previous run's
    /// totals. Publishing a count without the window it was counted over is how
    /// a stale figure gets read as a live one, so `vitals` carries the two
    /// together or not at all (DK-FR-015).
    private(set) var armedAt: Date?

    var isActive: Bool { tap != nil }

    /// What the tap actually holds, for the live-state record (DK-FR-015).
    ///
    /// `nil` when nothing is armed, which is what makes the counters
    /// unreachable in that case rather than merely unwise to read.
    ///
    /// `systemEnabled` is a genuinely new observation, and the distinction it
    /// draws has been invisible until now: `isActive` is `tap != nil` and
    /// nothing more, so between a `tapDisabledByTimeout` and the next event that
    /// re-enables it, this object reports an armed tap that is filtering
    /// nothing. `CGEvent.tapIsEnabled` asks macOS instead of asking ourselves.
    /// It is read here, on a support path, and never from `handle` — the whole
    /// hazard being described is a callback that takes too long.
    var vitals: LiveGuardRecord.TapRecord? {
        guard let tap, let armedAt else { return nil }
        return LiveGuardRecord.TapRecord(
            armedAt: armedAt,
            installedZoneCount: zones.count,
            systemEnabled: CGEvent.tapIsEnabled(tap: tap),
            clampCount: clampCount,
            reenableCount: reenableCount
        )
    }

    /// Applies a decision. Idempotent: re-applying the same zones keeps the
    /// existing tap rather than tearing it down, so a reconcile storm cannot
    /// thrash the pointer.
    func apply(_ decision: BottomDockGuard.Decision) {
        switch decision {
        case .idle:
            stop()
        case .guarding(let newZones, _, _):
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
        // `handle` uses `MainActor.assumeIsolated`, which is a hard crash if the
        // callback ever runs off the main thread. Its soundness rests entirely on
        // this source living on the main run loop. The standard cure for a slow
        // event tap is to move it to a dedicated thread with its own run loop —
        // a refactor that would silently turn both `assumeIsolated` calls into
        // crashes, so the invariant is asserted here rather than left in prose.
        precondition(Thread.isMainThread, "BottomDockGuardTap must be started on the main thread")
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)

        tap = created
        source = runLoopSource
        clampCount = 0
        reenableCount = 0
        // Stamped in the same breath as the counters it bounds, so the window
        // and the totals can never describe different armings.
        armedAt = Date()
        // Built in Core so the counts it claims are reachable from a test
        // (#84). This log is read as the evidence that the tap armed —
        // `--diagnostics` re-derives and cannot see a live tap (#77/#78) — so
        // what it says must not overstate what armed.
        // Hoisted out of the interpolation on purpose: `Logger`'s interpolation
        // is an autoclosure, so building the line inside it would read
        // main-actor state from a closure the logger evaluates on its own terms.
        let armed = BottomDockGuard.armedLogLine(zones: zones)
        Log.app.notice("\(armed, privacy: .public)")
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
        // The counters are deliberately left alone — they are reset on the next
        // arm, and that asymmetry predates this change. Clearing the window
        // instead is what makes them unpublishable rather than merely stale.
        armedAt = nil
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

    // No `deinit` teardown, and the reason is worth stating precisely because the
    // obvious fix does not build everywhere.
    //
    // The hazard is real in the abstract: `start()` hands the tap
    // `Unmanaged.passUnretained(self)`, and `CFRunLoopAddSource` retains the
    // source, which retains the port, which carries that raw pointer — so
    // releasing an armed tap would leave the next mouse event dereferencing freed
    // memory. `isolated deinit { stop() }` expresses the fix exactly, and compiles
    // on newer toolchains, but it is **still an experimental feature** and fails on
    // this project's CI Swift with "requires frontend flag
    // -enable-experimental-feature IsolatedDeinit". Turning an experimental flag on
    // for a shipping product to protect against a path that cannot currently occur
    // is the wrong trade.
    //
    // Why it cannot currently occur: the only owner is `AppState`'s
    // `private let bottomDockGuardTap`, which lives for the whole process and calls
    // `stop()` from `prepareForTermination()`. There is no path that releases this
    // object while a tap is armed. **If it ever gains a shorter-lived owner, that
    // assumption dies with it** — revisit then, either with `isolated deinit` once
    // it stabilises or by moving the CF handles into a small non-isolated box.
    //
    // Independent of all that, an event tap is process-owned and stops filtering
    // the moment the process exits by any route, SIGKILL included. That is why this
    // feature needs no launch-time repair, unlike ADR-013's borrowed Dock auto-hide,
    // which survives its owner and therefore does.
}
