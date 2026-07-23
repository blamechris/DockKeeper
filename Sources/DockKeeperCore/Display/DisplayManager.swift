import Foundation
import CoreGraphics
import ColorSync  // CGDisplayCreateUUIDFromDisplayID / CGDisplayGetDisplayIDFromUUID

/// Identifies and enumerates connected displays, keyed by stable UUID so a
/// user's "preferred display" survives reboots and reconnection.
public struct DisplayInfo: Identifiable, Sendable, Hashable {
    public let id: String          // Display UUID string.
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isMain: Bool
    public let frame: CGRect

    public init(id: String, displayID: CGDirectDisplayID, name: String, isMain: Bool, frame: CGRect) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.frame = frame
    }
}

public enum DisplayManager {

    /// The stable UUID string for a Core Graphics display, or `nil` if it has
    /// no UUID (rare; some virtual displays).
    public static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String?
    }

    /// The Core Graphics display ID for a UUID string, if that display is
    /// currently connected.
    public static func displayID(for uuid: String) -> CGDirectDisplayID? {
        guard let cfUUID = CFUUIDCreateFromString(nil, uuid as CFString) else { return nil }
        let displayID = CGDisplayGetDisplayIDFromUUID(cfUUID)
        return displayID != 0 ? displayID : nil
    }

    /// All currently active displays.
    public static func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        let mainID = CGMainDisplayID()
        return ids.map { id in
            DisplayInfo(
                id: uuid(for: id) ?? "cg-\(id)",
                displayID: id,
                name: name(for: id),
                isMain: id == mainID,
                frame: CGDisplayBounds(id)
            )
        }
    }

    /// A human-readable name for a display, falling back to a generic label.
    public static func name(for displayID: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Built-in Display"
        }
        if CGDisplayIsMain(displayID) != 0 {
            return "Main Display"
        }
        return "Display \(displayID)"
    }

    /// Whether the user's preferred display (if any) is currently connected.
    public static func isConnected(uuid: String) -> Bool {
        displayID(for: uuid) != nil
    }
}
