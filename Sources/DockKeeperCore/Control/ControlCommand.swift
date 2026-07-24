import Foundation

/// A single, UI-free automation command over DockKeeper's existing controls.
///
/// Lives in `DockKeeperCore` (not the app target) so the parse table is unit
/// testable from `DockKeeperTests`, which links only the core library. The
/// side-effecting funnel (`AppState.perform(_:)`) stays in the app layer; this
/// type is pure and `Sendable`, shared by the `dockkeeper://` URL handler and
/// the App Intents.
public enum ControlCommand: Equatable, Sendable {
    /// Enable enforcement and lock to a user-selectable edge (bottom/left/right).
    case lock(DockOrientation)
    /// Disable enforcement.
    case unlock
    /// Suspend corrections. `nil` pauses until an explicit resume; otherwise the
    /// value is a duration in seconds.
    case pause(TimeInterval?)
    /// Resume corrections and re-enforce.
    case resume

    /// Upper bound on a timed pause requested via automation.
    public static let maxPauseSeconds: TimeInterval = 24 * 60 * 60

    /// Parse a `dockkeeper://` URL into a command, or `nil` when the URL is not
    /// a recognized command. Recognized forms:
    ///
    ///   - `dockkeeper://lock?edge=bottom|left|right`  (edge case-insensitive)
    ///   - `dockkeeper://unlock`
    ///   - `dockkeeper://pause`            (until resumed)
    ///   - `dockkeeper://pause?minutes=15` (positive, capped at 24h)
    ///   - `dockkeeper://resume`
    ///
    /// Unknown scheme, host, or malformed parameters yield `nil`. Unrelated
    /// query parameters are ignored. `top` is rejected — only user-selectable
    /// edges lock.
    public static func parse(url: URL) -> ControlCommand? {
        guard url.scheme?.lowercased() == "dockkeeper" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let host = (components.host ?? "").lowercased()
        let queryItems = components.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first { $0.name.lowercased() == name }?.value
        }

        switch host {
        case "lock":
            guard
                let edgeValue = value("edge"),
                let edge = DockOrientation(defaultsValue: edgeValue),
                DockOrientation.userSelectable.contains(edge)
            else { return nil }
            return .lock(edge)

        case "unlock":
            return .unlock

        case "pause":
            guard let minutesValue = value("minutes") else { return .pause(nil) }
            guard let seconds = pauseSeconds(fromMinutes: minutesValue) else { return nil }
            return .pause(seconds)

        case "resume":
            return .resume

        default:
            return nil
        }
    }

    /// Convert a `minutes` query value into a capped, positive second count.
    /// Non-numeric, non-finite, zero, and negative values yield `nil`; values
    /// above the cap clamp to `maxPauseSeconds`.
    private static func pauseSeconds(fromMinutes string: String) -> TimeInterval? {
        guard let minutes = Double(string), minutes.isFinite, minutes > 0 else { return nil }
        return min(minutes * 60, maxPauseSeconds)
    }
}
