import Foundation

/// Thin wrapper over the private SkyLight `CGSIsScreenWatcherPresent` symbol —
/// the reliable "is anything capturing/recording the screen right now?" signal
/// (spike `screen-share-hide`, ADR-011). Screen capture has **no** public API;
/// the public camera-in-use signal detects a *different* thing (video calls),
/// so the screen-share feature is a private-API decision, mirroring ADR-003.
///
/// Resolution follows `CoreDock` exactly: `dlopen` the framework that carries
/// the symbol (SkyLight here, rather than ApplicationServices), then `dlsym`
/// against the current process image. If the symbol is gone — Apple renames or
/// removes it in a future macOS — the wrapper degrades to "unavailable" and
/// `isCapturing()` returns `false`, so the whole feature simply switches off
/// (no crash, no fallback needed — hiding the Dock is a comfort feature, not a
/// safety one).
///
/// Pure wrapper: no stored state, no polling. The caller (`ScreenShareHider`,
/// driven by a timer in `AppState`) owns the lifecycle.
public enum ScreenCapture {

    private typealias IsWatcherPresentFn = @convention(c) () -> Bool

    /// `CGSIsScreenWatcherPresent` lives in the private SkyLight framework.
    /// Explicitly load it (mirroring `CoreDock`'s ApplicationServices dlopen) so
    /// resolution doesn't depend on transitive linkage / load order.
    private nonisolated(unsafe) static let frameworkHandle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
    )

    private static let isWatcherPresentFn: IsWatcherPresentFn? = symbol("CGSIsScreenWatcherPresent")

    private static func symbol<T>(_ name: String) -> T? {
        _ = frameworkHandle  // force the dlopen before any dlsym
        guard let handle = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(handle, to: T.self)
    }

    /// True when the private symbol resolved and the detector can be used.
    /// When false, the screen-share feature is unavailable and the UI says so.
    public static var isAvailable: Bool { isWatcherPresentFn != nil }

    /// Whether a screen watcher (capture/recording/screen-sharing session) is
    /// currently present. `false` when the symbol is unavailable — an absent
    /// detector never claims a capture is happening, so the Dock is never hidden
    /// on a hunch.
    ///
    /// Evidence: the symbol resolving and returning `false` at rest is CONFIRMED
    /// on-rig (spike, macOS 26.5). The **true** case — that the flag actually
    /// flips when a real capture starts, its latency, and which apps trip it
    /// (QuickTime, Zoom, Teams, Screen Sharing.app) — is UNKNOWN pending
    /// on-device verification (folded into M6/M12; do not treat as CONFIRMED).
    public static func isCapturing() -> Bool {
        guard let isWatcherPresentFn else { return false }
        return isWatcherPresentFn()
    }
}
