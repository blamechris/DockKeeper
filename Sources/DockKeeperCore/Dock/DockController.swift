import Foundation

/// Drives the macOS Dock's orientation, restoring it whenever it drifts from
/// the user's locked edge.
///
/// Two mechanisms, in preference order:
/// 1. The private `CoreDock` API — live, flicker-free, no Dock restart.
/// 2. `defaults write com.apple.dock orientation` + `killall Dock` — a robust
///    fallback if the private API is ever unavailable.
public final class DockController: @unchecked Sendable {

    private let settings: Settings

    public init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// The Dock's current orientation as macOS reports it.
    public func currentOrientation() -> DockOrientation? {
        if let current = CoreDock.current() {
            return current.orientation
        }
        return readOrientationFromDefaults()
    }

    /// True when the Dock already sits on `edge`; used to avoid redundant work.
    public func isOnEdge(_ edge: DockOrientation) -> Bool {
        currentOrientation() == edge
    }

    /// Move the Dock to `edge`. Returns `true` if a change was applied.
    /// A no-op (already on `edge`) returns `false`.
    @discardableResult
    public func setOrientation(_ edge: DockOrientation) -> Bool {
        guard !isOnEdge(edge) else {
            Log.dock.debug("Dock already on \(edge.displayName, privacy: .public); no-op")
            return false
        }
        apply(edge)
        return true
    }

    /// Force the Dock to `edge` regardless of current state (used after wake /
    /// display changes where our cached view may be stale).
    public func forceOrientation(_ edge: DockOrientation) {
        apply(edge)
    }

    /// Restore the Dock to the user's configured lock edge, if enabled.
    /// Returns `true` if a correction was applied.
    @discardableResult
    public func restoreToLockedEdge() -> Bool {
        guard settings.isEnabled else { return false }
        return setOrientation(settings.lockEdge)
    }

    // MARK: - Application

    private func apply(_ edge: DockOrientation) {
        if CoreDock.set(orientation: edge) {
            Log.dock.info("Set Dock orientation to \(edge.displayName, privacy: .public) via CoreDock")
        } else {
            Log.dock.info("CoreDock unavailable; falling back to defaults+restart for \(edge.displayName, privacy: .public)")
            writeOrientationToDefaults(edge)
            restartDock()
        }
    }

    // MARK: - `defaults` fallback

    private func readOrientationFromDefaults() -> DockOrientation? {
        guard
            let dockDefaults = UserDefaults(suiteName: "com.apple.dock"),
            let raw = dockDefaults.string(forKey: "orientation")
        else { return nil }
        return DockOrientation(defaultsValue: raw)
    }

    private func writeOrientationToDefaults(_ edge: DockOrientation) {
        let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
        dockDefaults?.set(edge.defaultsValue, forKey: "orientation")
    }

    private func restartDock() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        do {
            try task.run()
        } catch {
            Log.dock.error("Failed to restart Dock: \(error.localizedDescription, privacy: .public)")
        }
    }
}
