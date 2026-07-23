import Foundation

/// The edge of the screen the Dock is pinned to.
///
/// Raw values match the integers used by the private `CoreDock` API
/// (`CoreDockSetOrientationAndPinning`) as well as the string values written
/// to the `com.apple.dock` `orientation` preference.
public enum DockOrientation: Int, CaseIterable, Sendable, Codable {
    case top = 1     // Not user-selectable on macOS, kept for CoreDock parity.
    case bottom = 2
    case left = 3
    case right = 4

    /// The string value used by the `com.apple.dock` `orientation` default.
    public var defaultsValue: String {
        switch self {
        case .top: return "top"
        case .bottom: return "bottom"
        case .left: return "left"
        case .right: return "right"
        }
    }

    /// Edges a user is allowed to lock to. macOS does not support a top Dock.
    public static let userSelectable: [DockOrientation] = [.bottom, .left, .right]

    public init?(defaultsValue: String) {
        switch defaultsValue.lowercased() {
        case "top": self = .top
        case "bottom": self = .bottom
        case "left": self = .left
        case "right": self = .right
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// Where along the edge the Dock is anchored. Mirrors the `CoreDock` pinning
/// integer. Exposed for completeness; DockKeeper defaults to `.middle`.
public enum DockPinning: Int, CaseIterable, Sendable, Codable {
    case start = 1
    case middle = 2
    case end = 3
}
