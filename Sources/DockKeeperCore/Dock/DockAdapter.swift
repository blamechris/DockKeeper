import Foundation

/// Read/write access to the Dock's orientation, hiding the mechanism so
/// decision logic can be unit-tested against fakes (kickoff rule 8).
///
/// Two production implementations, in preference order:
/// - `CoreDockAdapter` — live, flicker-free private API (ADR-003).
/// - `DefaultsDockAdapter` — `defaults write` + Dock restart; visible, robust.
public protocol DockAdapter: Sendable {
    /// Short mechanism name for logs and `dockkeeper status`.
    var name: String { get }
    /// Whether this mechanism can act in the current process.
    var isAvailable: Bool { get }
    /// The Dock's current orientation, or `nil` when unreadable.
    func currentOrientation() -> DockOrientation?
    /// Apply `edge`. Returns `false` when the mechanism could not act.
    @discardableResult
    func setOrientation(_ edge: DockOrientation) -> Bool
}

/// Primary mechanism: the private `CoreDock` API (ADR-003, ratified).
///
/// Spike-confirmed (2026-07-22): a live set writes through to the
/// `com.apple.dock` defaults domain, so Dock restarts re-read the edge we set —
/// no mirroring needed.
public struct CoreDockAdapter: DockAdapter {
    public init() {}
    public var name: String { "CoreDock" }
    public var isAvailable: Bool { CoreDock.isAvailable }

    public func currentOrientation() -> DockOrientation? {
        CoreDock.current()?.orientation
    }

    public func setOrientation(_ edge: DockOrientation) -> Bool {
        CoreDock.set(orientation: edge)
    }
}

/// Fallback mechanism: write the `com.apple.dock` preference and restart the
/// Dock so it picks the value up. Visible (the Dock relaunches) — used only
/// when `CoreDock` is unavailable, surfacing the `degraded` state.
public struct DefaultsDockAdapter: DockAdapter {
    public init() {}
    public var name: String { "defaults+restart" }
    public var isAvailable: Bool { true }

    public func currentOrientation() -> DockOrientation? {
        guard
            let dockDefaults = UserDefaults(suiteName: "com.apple.dock"),
            let raw = dockDefaults.string(forKey: "orientation")
        else { return nil }
        return DockOrientation(defaultsValue: raw)
    }

    public func setOrientation(_ edge: DockOrientation) -> Bool {
        guard let dockDefaults = UserDefaults(suiteName: "com.apple.dock") else { return false }
        dockDefaults.set(edge.defaultsValue, forKey: "orientation")
        restartDock()
        return true
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
