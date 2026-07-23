import Foundation

/// Drives the macOS Dock's orientation, restoring it whenever it drifts from
/// the user's locked edge.
///
/// Mechanisms live behind `DockAdapter` (kickoff rule 8): the primary adapter
/// (`CoreDock` — live, flicker-free) with a fallback (`defaults` + restart)
/// when the primary can't act. Fallback use is what the `degraded` state
/// surfaces to the user.
public final class DockController: @unchecked Sendable {

    private let settings: Settings
    private let primary: DockAdapter
    private let fallback: DockAdapter

    public init(
        settings: Settings = .shared,
        primary: DockAdapter = CoreDockAdapter(),
        fallback: DockAdapter = DefaultsDockAdapter()
    ) {
        self.settings = settings
        self.primary = primary
        self.fallback = fallback
    }

    /// True when the primary (flicker-free) mechanism is unavailable and edge
    /// corrections will go through the visible fallback.
    public var isDegraded: Bool { !primary.isAvailable }

    /// Mechanism name for `dockkeeper status` / diagnostics.
    public var activeMechanismName: String {
        primary.isAvailable ? primary.name : fallback.name
    }

    /// The Dock's current orientation as macOS reports it. Prefers the live
    /// read; falls back to the defaults read, which can lag (TDD §5.3).
    public func currentOrientation() -> DockOrientation? {
        primary.currentOrientation() ?? fallback.currentOrientation()
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
        if primary.isAvailable, primary.setOrientation(edge) {
            Log.dock.info("Set Dock orientation to \(edge.displayName, privacy: .public) via \(self.primary.name, privacy: .public)")
            return
        }
        Log.dock.info("\(self.primary.name, privacy: .public) unavailable; using \(self.fallback.name, privacy: .public) for \(edge.displayName, privacy: .public)")
        if !fallback.setOrientation(edge) {
            Log.dock.error("All Dock mechanisms failed to set \(edge.displayName, privacy: .public)")
        }
    }
}
