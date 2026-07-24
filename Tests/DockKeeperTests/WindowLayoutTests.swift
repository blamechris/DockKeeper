import Testing
import Foundation
import CoreGraphics
@testable import DockKeeperCore

// Convenience fixtures ------------------------------------------------------

private func display(_ id: CGDirectDisplayID, _ frame: CGRect, main: Bool = false) -> DisplayInfo {
    DisplayInfo(id: "d\(id)", displayID: id, name: "D\(id)", isMain: main, frame: frame)
}

/// The owner's real rig (task geometry). Built-in main pre-pin; pinning the
/// Dell re-bases every origin by the same delta (−target.originBefore).
private enum Rig {
    static let builtinID: CGDirectDisplayID = 1
    static let dellID: CGDirectDisplayID = 2

    static let builtinBefore = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    static let dellBefore = CGRect(x: 130, y: -2560, width: 1440, height: 2560)

    static let builtinAfter = CGRect(x: -130, y: 2560, width: 1728, height: 1117)
    static let dellAfter = CGRect(x: 0, y: 0, width: 1440, height: 2560)

    static let displaysBefore = [display(builtinID, builtinBefore, main: true), display(dellID, dellBefore)]
    static let displaysAfter = [display(builtinID, builtinAfter), display(dellID, dellAfter, main: true)]
}

// MARK: - Max-overlap display assignment

@Suite("WindowLayoutPreserver.assignDisplay")
struct WindowAssignmentTests {

    @Test("A window fully inside one display is assigned to it")
    func fullyInside() {
        let displays = Rig.displaysBefore
        let window = CGRect(x: 100, y: 100, width: 300, height: 200)  // inside built-in
        #expect(WindowLayoutPreserver.assignDisplay(bounds: window, displays: displays) == Rig.builtinID)
    }

    @Test("A window straddling two displays goes to the one it overlaps most")
    func straddlingPicksMaxOverlap() {
        let left = display(10, CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let right = display(20, CGRect(x: 1000, y: 0, width: 1000, height: 1000))

        // 200pt on the left, 100pt on the right → left wins.
        let leaningLeft = CGRect(x: 800, y: 100, width: 300, height: 200)
        #expect(WindowLayoutPreserver.assignDisplay(bounds: leaningLeft, displays: [left, right]) == 10)

        // 50pt on the left, 250pt on the right → right wins.
        let leaningRight = CGRect(x: 950, y: 100, width: 300, height: 200)
        #expect(WindowLayoutPreserver.assignDisplay(bounds: leaningRight, displays: [left, right]) == 20)
    }

    @Test("A window off every display assigns to nothing")
    func offScreenIsNil() {
        let window = CGRect(x: 9000, y: 9000, width: 100, height: 100)
        #expect(WindowLayoutPreserver.assignDisplay(bounds: window, displays: Rig.displaysBefore) == nil)
    }
}

// MARK: - Delta computation & restore plan

@Suite("WindowLayoutPreserver.restorePlan")
struct RestorePlanTests {

    @Test("Re-base delta moves every window by −target.originBefore on the real rig")
    func rigDelta() {
        let snapshot = WindowLayoutPreserver.Snapshot(
            windows: [
                .init(ownerPID: 501, bounds: CGRect(x: 50, y: 50, width: 400, height: 300), displayID: Rig.builtinID),
                .init(ownerPID: 502, bounds: CGRect(x: 200, y: -2000, width: 600, height: 400), displayID: Rig.dellID),
            ],
            originsBefore: [Rig.builtinID: Rig.builtinBefore.origin, Rig.dellID: Rig.dellBefore.origin]
        )
        let plan = WindowLayoutPreserver.restorePlan(snapshot, displaysAfter: Rig.displaysAfter)

        // Both displays shift by (−130, +2560); windows follow their display.
        #expect(plan.count == 2)
        let builtinMove = plan.first { $0.ownerPID == 501 }
        let dellMove = plan.first { $0.ownerPID == 502 }
        #expect(builtinMove?.newOrigin == CGPoint(x: -80, y: 2610))
        #expect(dellMove?.newOrigin == CGPoint(x: 70, y: 560))
    }

    @Test("Windows on a display that didn't move are left alone (zero delta)")
    func skipsUnaffectedDisplays() {
        // Display 1 moves; display 2 stays put.
        let snapshot = WindowLayoutPreserver.Snapshot(
            windows: [
                .init(ownerPID: 1, bounds: CGRect(x: 10, y: 10, width: 100, height: 100), displayID: 1),
                .init(ownerPID: 2, bounds: CGRect(x: 1010, y: 10, width: 100, height: 100), displayID: 2),
            ],
            originsBefore: [1: .zero, 2: CGPoint(x: 1000, y: 0)]
        )
        let after = [
            display(1, CGRect(x: -50, y: 0, width: 800, height: 600)),   // moved by (−50, 0)
            display(2, CGRect(x: 1000, y: 0, width: 800, height: 600)),  // unchanged
        ]
        let plan = WindowLayoutPreserver.restorePlan(snapshot, displaysAfter: after)

        #expect(plan.count == 1)
        #expect(plan.first?.ownerPID == 1)
        #expect(plan.first?.newOrigin == CGPoint(x: -40, y: 10))
    }

    @Test("A window whose display is gone after the pin is dropped")
    func dropsMissingDisplay() {
        let snapshot = WindowLayoutPreserver.Snapshot(
            windows: [.init(ownerPID: 7, bounds: CGRect(x: 10, y: 10, width: 100, height: 100), displayID: 2)],
            originsBefore: [2: CGPoint(x: 1000, y: 0)]
        )
        let after = [display(1, CGRect(x: 0, y: 0, width: 800, height: 600))]  // display 2 unplugged
        #expect(WindowLayoutPreserver.restorePlan(snapshot, displaysAfter: after).isEmpty)
    }
}

// MARK: - Snapshot building & tolerance matching

@Suite("WindowLayoutPreserver.buildSnapshot / framesMatch")
struct SnapshotBuildTests {

    @Test("Only layer-0 windows overlapping a display are recorded")
    func filtersNonZeroLayersAndOffscreen() {
        let raw = [
            WindowLayoutPreserver.RawWindow(ownerPID: 1, layer: 0, bounds: CGRect(x: 10, y: 10, width: 100, height: 100)),
            WindowLayoutPreserver.RawWindow(ownerPID: 2, layer: 25, bounds: CGRect(x: 10, y: 10, width: 100, height: 100)),  // menu/overlay
            WindowLayoutPreserver.RawWindow(ownerPID: 3, layer: 0, bounds: CGRect(x: 9000, y: 9000, width: 100, height: 100)),  // off-screen
        ]
        let snapshot = WindowLayoutPreserver.buildSnapshot(rawWindows: raw, displays: Rig.displaysBefore)

        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows.first?.ownerPID == 1)
        #expect(snapshot.windows.first?.displayID == Rig.builtinID)
        #expect(snapshot.originsBefore[Rig.builtinID] == .zero)
    }

    @Test("Frame matching tolerates sub-pixel drift but rejects real moves")
    func frameTolerance() {
        let base = CGRect(x: 100, y: 200, width: 800, height: 600)
        #expect(WindowLayoutPreserver.framesMatch(base, CGRect(x: 101, y: 201, width: 800, height: 600)))
        #expect(!WindowLayoutPreserver.framesMatch(base, CGRect(x: 140, y: 200, width: 800, height: 600)))
        #expect(!WindowLayoutPreserver.framesMatch(base, CGRect(x: 100, y: 200, width: 810, height: 600)))
    }
}

// MARK: - Settings default

@Suite("Settings.preserveWindowLayout")
struct PreserveWindowLayoutSettingTests {

    private func makeSettings() -> Settings {
        let name = "com.dockkeeper.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return Settings(defaults: suite)
    }

    @Test("Defaults to false (zero-permission default)")
    func defaultsFalse() {
        #expect(makeSettings().preserveWindowLayout == false)
    }

    @Test("Round-trips when set")
    func roundTrips() {
        let settings = makeSettings()
        settings.preserveWindowLayout = true
        #expect(settings.preserveWindowLayout == true)
    }
}
