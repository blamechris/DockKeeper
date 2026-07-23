import Foundation
import CoreGraphics
import ColorSync  // CGDisplayCreateUUIDFromDisplayID / CGDisplayGetDisplayIDFromUUID
import AppKit     // NSScreen.localizedName (main-actor)

/// Identifies and enumerates connected displays. The `id` is the display's
/// UUID string when it has one, or a `"cg-<id>"` placeholder for UI identity
/// only — placeholders are **never persisted**; preferences store a
/// `DisplayFingerprint` (ADR-004).
public struct DisplayInfo: Identifiable, Sendable, Hashable {
    public let id: String          // Display UUID string, or "cg-<id>" (UI-only).
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isMain: Bool
    public let frame: CGRect
    /// Full identity evidence for fingerprint matching; `nil` only in tests
    /// that don't exercise identity.
    public let fingerprint: DisplayFingerprint?

    public init(
        id: String,
        displayID: CGDirectDisplayID,
        name: String,
        isMain: Bool,
        frame: CGRect,
        fingerprint: DisplayFingerprint? = nil
    ) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.isMain = isMain
        self.frame = frame
        self.fingerprint = fingerprint
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

    /// All currently active displays. Main-actor because human-readable names
    /// come from `NSScreen.localizedName` (TDD §7.1).
    @MainActor
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
                frame: CGDisplayBounds(id),
                fingerprint: fingerprint(for: id)
            )
        }
    }

    /// Capture every identity signal we have for a display (TDD §7.1).
    @MainActor
    public static func fingerprint(for displayID: CGDirectDisplayID) -> DisplayFingerprint {
        DisplayFingerprint(
            uuid: uuid(for: displayID),
            vendorNumber: CGDisplayVendorNumber(displayID),
            modelNumber: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),
            localizedName: localizedName(for: displayID),
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0
        )
    }

    /// The user-facing display name ("DELL U2720Q"), falling back to a generic
    /// label when NSScreen has no entry for the display.
    @MainActor
    public static func name(for displayID: CGDirectDisplayID) -> String {
        if let localized = localizedName(for: displayID) {
            return localized
        }
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "Built-in Display"
        }
        return "Display \(displayID)"
    }

    @MainActor
    private static func localizedName(for displayID: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }?.localizedName
    }

    /// Whether the user's preferred display (if any) is currently connected.
    public static func isConnected(uuid: String) -> Bool {
        displayID(for: uuid) != nil
    }
}
