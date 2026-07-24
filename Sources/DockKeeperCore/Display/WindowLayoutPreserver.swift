import Foundation
import CoreGraphics
import ApplicationServices  // AXUIElement / AXIsProcessTrusted / AXValue

/// Opt-in "keep windows in place when pinning" (ADR-010).
///
/// A pin makes the preferred display the macOS *main* display by re-basing every
/// display's origin. Windows keep their global coordinates while the grid moves
/// underneath them, so some land on the other screen — identical to changing the
/// primary display in System Settings. This snapshots window geometry before the
/// pin and moves each window back to its original display afterward.
///
/// Restoring *other* apps' windows requires the Accessibility permission, so the
/// whole feature is opt-in and no-ops silently until trusted — DockKeeper's
/// default stays zero-permission. The decision math is pure and unit-tested; the
/// `CGWindowList`/AX reads and writes are thin wrappers over it. Privacy rule
/// (TDD §12): window titles/names are never read or stored — geometry only.
@MainActor
public enum WindowLayoutPreserver {

    // MARK: - Value types

    /// One captured window: which app owns it, where it sat (global, CG
    /// top-left coordinates), and the display it belonged to (max-overlap).
    public struct WindowRecord: Sendable, Equatable {
        public let ownerPID: pid_t
        public let bounds: CGRect
        public let displayID: CGDirectDisplayID

        public init(ownerPID: pid_t, bounds: CGRect, displayID: CGDirectDisplayID) {
            self.ownerPID = ownerPID
            self.bounds = bounds
            self.displayID = displayID
        }
    }

    /// Window geometry captured just before a pin, plus the pre-pin display
    /// origins needed to compute the post-pin delta.
    public struct Snapshot: Sendable, Equatable {
        public let windows: [WindowRecord]
        public let originsBefore: [CGDirectDisplayID: CGPoint]

        public init(windows: [WindowRecord], originsBefore: [CGDirectDisplayID: CGPoint]) {
            self.windows = windows
            self.originsBefore = originsBefore
        }
    }

    /// One window to move back: where it was (used to re-find it via AX) and
    /// where it now needs to go.
    public struct RestoreMove: Sendable, Equatable {
        public let ownerPID: pid_t
        public let oldBounds: CGRect
        public let newOrigin: CGPoint

        public init(ownerPID: pid_t, oldBounds: CGRect, newOrigin: CGPoint) {
            self.ownerPID = ownerPID
            self.oldBounds = oldBounds
            self.newOrigin = newOrigin
        }
    }

    /// Raw layer/geometry read from `CGWindowList`, before display assignment.
    /// Deliberately carries no title/name (privacy).
    public struct RawWindow: Sendable, Equatable {
        public let ownerPID: pid_t
        public let layer: Int
        public let bounds: CGRect

        public init(ownerPID: pid_t, layer: Int, bounds: CGRect) {
            self.ownerPID = ownerPID
            self.layer = layer
            self.bounds = bounds
        }
    }

    // MARK: - Pure decision core (unit-tested)

    /// Overlap area between two global-coordinate rectangles (0 if disjoint).
    public nonisolated static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    /// Assign a window to the display whose frame overlaps its bounds most.
    /// `nil` when the window overlaps no display (off-screen / vanished).
    public nonisolated static func assignDisplay(
        bounds: CGRect,
        displays: [DisplayInfo]
    ) -> CGDirectDisplayID? {
        var best: (id: CGDirectDisplayID, area: CGFloat)?
        for display in displays {
            let area = overlapArea(bounds, display.frame)
            guard area > 0 else { continue }
            if best == nil || area > best!.area {
                best = (display.displayID, area)
            }
        }
        return best?.id
    }

    /// Build a snapshot from raw window info: keep layer-0 windows that overlap
    /// a display, tagging each with its max-overlap display and recording the
    /// pre-pin display origins.
    public nonisolated static func buildSnapshot(
        rawWindows: [RawWindow],
        displays: [DisplayInfo]
    ) -> Snapshot {
        let originsBefore = Dictionary(
            displays.map { ($0.displayID, $0.frame.origin) },
            uniquingKeysWith: { first, _ in first }
        )
        let records = rawWindows.compactMap { raw -> WindowRecord? in
            guard raw.layer == 0 else { return nil }
            guard let displayID = assignDisplay(bounds: raw.bounds, displays: displays) else { return nil }
            return WindowRecord(ownerPID: raw.ownerPID, bounds: raw.bounds, displayID: displayID)
        }
        return Snapshot(windows: records, originsBefore: originsBefore)
    }

    /// The restore plan: for each recorded window whose display moved, shift its
    /// origin by that display's delta (afterOrigin − beforeOrigin). Windows on
    /// unmoved displays (zero delta) or on displays absent after the pin are
    /// dropped.
    public nonisolated static func restorePlan(
        _ snapshot: Snapshot,
        displaysAfter: [DisplayInfo]
    ) -> [RestoreMove] {
        let originsAfter = Dictionary(
            displaysAfter.map { ($0.displayID, $0.frame.origin) },
            uniquingKeysWith: { first, _ in first }
        )
        return snapshot.windows.compactMap { window -> RestoreMove? in
            guard
                let before = snapshot.originsBefore[window.displayID],
                let after = originsAfter[window.displayID]
            else { return nil }
            let dx = after.x - before.x
            let dy = after.y - before.y
            guard dx != 0 || dy != 0 else { return nil }  // display didn't move
            let newOrigin = CGPoint(x: window.bounds.origin.x + dx, y: window.bounds.origin.y + dy)
            return RestoreMove(ownerPID: window.ownerPID, oldBounds: window.bounds, newOrigin: newOrigin)
        }
    }

    /// Whether two frames match within a small tolerance — used to re-find an AX
    /// window by the global coordinates it kept through the re-base.
    public nonisolated static func framesMatch(
        _ a: CGRect,
        _ b: CGRect,
        tolerance: CGFloat = 2
    ) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance &&
        abs(a.origin.y - b.origin.y) <= tolerance &&
        abs(a.size.width - b.size.width) <= tolerance &&
        abs(a.size.height - b.size.height) <= tolerance
    }

    // MARK: - Availability

    /// Non-prompting trust check. The preserver NEVER prompts — the UI owns the
    /// contextual explanation and the one prompt (TDD §10).
    public static func isTrusted() -> Bool { AXIsProcessTrusted() }

    // MARK: - Side effects (thin wrappers over the pure core)

    /// Snapshot on-screen layer-0 windows against `displays` (the pre-pin list).
    public static func snapshot(displays: [DisplayInfo]) -> Snapshot {
        buildSnapshot(rawWindows: liveWindowList(), displays: displays)
    }

    /// Move each planned window back onto its original display. Per-window AX
    /// failures are tolerated silently; only a count is logged (no titles).
    public static func restore(_ snapshot: Snapshot, displaysAfter: [DisplayInfo]) {
        guard isTrusted() else { return }  // opt-in setting on, permission missing
        let plan = restorePlan(snapshot, displaysAfter: displaysAfter)
        guard !plan.isEmpty else { return }
        var failures = 0
        for move in plan where !liveMove(pid: move.ownerPID, oldBounds: move.oldBounds, newOrigin: move.newOrigin) {
            failures += 1
        }
        if failures > 0 {
            Log.accessibility.info(
                "Window restore: \(failures, privacy: .public)/\(plan.count, privacy: .public) windows not moved"
            )
        }
    }

    // MARK: - Live CGWindowList / AX implementations

    /// Read on-screen, non-desktop windows. Keeps PID, layer, and bounds only;
    /// `kCGWindowBounds` is in global CG top-left coordinates.
    static func liveWindowList() -> [RawWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { entry in
            guard
                let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return RawWindow(ownerPID: pid, layer: layer, bounds: bounds)
        }
    }

    /// Find the app's AX window whose current frame ≈ `oldBounds` (it kept its
    /// global coordinates through the re-base) and set its position. AX uses the
    /// same global CG top-left coordinate space as `CGWindowList` — INFERRED,
    /// pending empirical confirmation on hardware. Returns whether a move
    /// happened.
    static func liveMove(pid: pid_t, oldBounds: CGRect, newOrigin: CGPoint) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return false }

        for window in windows {
            guard let frame = axFrame(of: window), framesMatch(frame, oldBounds) else { continue }
            var point = newOrigin
            guard let position = AXValueCreate(.cgPoint, &point) else { return false }
            return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success
        }
        return false
    }

    /// Current global frame of an AX window, or `nil` if either attribute reads
    /// fail (window closed, app unresponsive).
    private static func axFrame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionAX = positionValue, let sizeAX = sizeValue
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionAX as! AXValue, .cgPoint, &origin),
            AXValueGetValue(sizeAX as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
