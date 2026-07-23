import Foundation

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

    private static let getFn: GetFn? = symbol("CoreDockGetOrientationAndPinning")
    private static let setFn: SetFn? = symbol("CoreDockSetOrientationAndPinning")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(handle, to: T.self)
    }

    /// True when the private API resolved and can be used.
    public static var isAvailable: Bool { getFn != nil && setFn != nil }

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
}
