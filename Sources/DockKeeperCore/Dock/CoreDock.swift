import Foundation
import CoreGraphics

/// Thin wrapper over the private `CoreDock*` C functions that the macOS Dock
/// exposes for reading and setting its orientation and pinning.
///
/// These symbols are not part of the public SDK, so we resolve them at runtime
/// with `dlsym` against the current process image (they are already loaded via
/// HIServices/ApplicationServices in any AppKit process). If resolution fails
/// — e.g. Apple changes or removes them in a future macOS — the wrapper
/// degrades gracefully and callers can fall back to the `defaults` + restart
/// path in `DockController`.
///
/// Using `CoreDockSetOrientationAndPinning` is strongly preferred over
/// `defaults write` because it repositions the Dock live, with no flicker and
/// no `killall Dock`.
public enum CoreDock {

    private typealias GetFn = @convention(c) (
        UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
    ) -> Void
    private typealias SetFn = @convention(c) (Int32, Int32) -> Void
    private typealias GetAutoHideFn = @convention(c) () -> Bool
    private typealias SetAutoHideFn = @convention(c) (Bool) -> Void
    private typealias GetRectFn = @convention(c) (UnsafeMutablePointer<CGRect>) -> Void

    /// The CoreDock symbols live in HIServices, which is only guaranteed to be
    /// loaded in AppKit processes. Explicitly load the ApplicationServices
    /// umbrella (which carries HIServices) so a non-AppKit process — or a
    /// future CLI without transitive AppKit linkage — still resolves them
    /// (spike-recommended hardening; link order is no longer load-bearing).
    private nonisolated(unsafe) static let frameworkHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        RTLD_LAZY
    )

    private static let getFn: GetFn? = symbol("CoreDockGetOrientationAndPinning")
    private static let setFn: SetFn? = symbol("CoreDockSetOrientationAndPinning")
    private static let getAutoHideFn: GetAutoHideFn? = symbol("CoreDockGetAutoHideEnabled")
    private static let setAutoHideFn: SetAutoHideFn? = symbol("CoreDockSetAutoHideEnabled")
    private static let getRectFn: GetRectFn? = symbol("CoreDockGetRect")

    private static func symbol<T>(_ name: String) -> T? {
        _ = frameworkHandle  // force the dlopen before any dlsym
        guard let handle = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(handle, to: T.self)
    }

    /// True when the private API resolved and can be used. Answers for the
    /// *orientation* pair only — see `isAutoHideAvailable` for the auto-hide one.
    public static var isAvailable: Bool { getFn != nil && setFn != nil }

    /// True when the auto-hide symbols specifically resolved. `isAvailable`
    /// answers for `CoreDockGet/SetOrientationAndPinning` and is not a proxy for
    /// these: the four symbols are `dlsym`'d independently, so a UI gate that
    /// consults the wrong pair can enable a control whose write cannot land (and
    /// disable one whose write can).
    public static var isAutoHideAvailable: Bool { getAutoHideFn != nil && setAutoHideFn != nil }

    /// The Dock's current orientation and pinning, or `nil` if the API is
    /// unavailable or returns an unrecognized value.
    public static func current() -> (orientation: DockOrientation, pinning: DockPinning)? {
        guard let getFn else { return nil }
        var rawOrientation: Int32 = 0
        var rawPinning: Int32 = 0
        getFn(&rawOrientation, &rawPinning)
        guard
            let orientation = DockOrientation(rawValue: Int(rawOrientation)),
            let pinning = DockPinning(rawValue: Int(rawPinning))
        else { return nil }
        return (orientation, pinning)
    }

    /// Set the Dock's orientation (and pinning). Returns `false` if the private
    /// API is unavailable, so the caller can fall back.
    @discardableResult
    public static func set(
        orientation: DockOrientation,
        pinning: DockPinning = .middle
    ) -> Bool {
        guard let setFn else { return false }
        setFn(Int32(orientation.rawValue), Int32(pinning.rawValue))
        return true
    }

    // MARK: - Auto-hide (screen-share Dock hide — DK-FR-011 / ADR-011)

    /// The Dock's current auto-hide state, or `nil` if the private symbol is
    /// unavailable. Used by `ScreenShareHider` to remember whether the user was
    /// already running auto-hide before we consider hiding the Dock.
    public static func getAutoHideEnabled() -> Bool? {
        guard let getAutoHideFn else { return nil }
        return getAutoHideFn()
    }

    /// Set the Dock's auto-hide state. Returns `false` if the private symbol is
    /// unavailable (the caller then treats the feature as inert). This writes
    /// through to the `com.apple.dock` domain the same way the orientation set
    /// does, so a Dock restart preserves the value.
    @discardableResult
    public static func setAutoHideEnabled(_ enabled: Bool) -> Bool {
        guard let setAutoHideFn else { return false }
        setAutoHideFn(enabled)
        return true
    }

    /// The Dock's on-screen rectangle in global display coordinates, or `nil`
    /// when the symbol is unavailable. Auto-hide leaves `NSScreen.visibleFrame`
    /// stale (spike gotcha), so this is the auto-hide-proof way to locate the
    /// Dock's host display should a future feature need it while the Dock is
    /// hidden. The shipped pinning path uses `CGDisplayBounds` / `CGMainDisplayID`
    /// and is unaffected, so nothing calls this yet — it exists as the correct
    /// sensor for that future work (ADR-011).
    public static func getRect() -> CGRect? {
        guard let getRectFn else { return nil }
        var rect = CGRect.zero
        getRectFn(&rect)
        return rect
    }
}
