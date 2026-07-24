import Testing
import Foundation
import CoreGraphics
@testable import DockKeeperCore

@Suite("DockOrientation")
struct DockOrientationTests {

    @Test("Round-trips through defaults string values")
    func defaultsRoundTrip() {
        for orientation in DockOrientation.allCases {
            let string = orientation.defaultsValue
            #expect(DockOrientation(defaultsValue: string) == orientation)
        }
    }

    @Test("Parses defaults values case-insensitively")
    func caseInsensitiveParsing() {
        #expect(DockOrientation(defaultsValue: "BOTTOM") == .bottom)
        #expect(DockOrientation(defaultsValue: "Left") == .left)
    }

    @Test("Rejects unknown defaults values")
    func rejectsUnknown() {
        #expect(DockOrientation(defaultsValue: "diagonal") == nil)
    }

    @Test("Raw values match the CoreDock orientation integers")
    func coreDockRawValues() {
        #expect(DockOrientation.bottom.rawValue == 2)
        #expect(DockOrientation.left.rawValue == 3)
        #expect(DockOrientation.right.rawValue == 4)
    }

    @Test("Top is excluded from user-selectable edges")
    func userSelectableExcludesTop() {
        #expect(!DockOrientation.userSelectable.contains(.top))
        #expect(DockOrientation.userSelectable == [.bottom, .left, .right])
    }
}

@Suite("Settings")
struct SettingsTests {

    /// Isolated defaults so tests don't touch the real user domain. A unique
    /// suite name per call keeps parallel tests from racing on shared state.
    private func makeSettings() -> Settings {
        let suiteName = "com.dockkeeper.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return Settings(defaults: suite)
    }

    @Test("Registers sensible defaults")
    func registeredDefaults() {
        let settings = makeSettings()
        #expect(settings.isEnabled == true)
        #expect(settings.lockEdge == .bottom)
        // ADR-005: the poll is a 30 s safety net, not a 2 s hammer.
        #expect(settings.recoveryInterval == 30.0)
        #expect(settings.restoreDelay == 0.4)
        // Diagnostics file is strictly opt-in (DK-PRIV-001 S2).
        #expect(settings.diagnosticsFileEnabled == false)
        #expect(settings.settingsVersion == 1)
    }

    @Test("Persists a changed lock edge")
    func persistsLockEdge() {
        let settings = makeSettings()
        settings.lockEdge = .left
        #expect(settings.lockEdge == .left)
    }
}

@Suite("MainDisplayPinner.decide")
struct DisplayPinnerTests {

    private func display(_ uuid: String, id: CGDirectDisplayID, origin: CGPoint = .zero) -> DisplayInfo {
        DisplayInfo(
            id: uuid,
            displayID: id,
            name: "Display \(id)",
            isMain: false,
            frame: CGRect(origin: origin, size: CGSize(width: 1920, height: 1080))
        )
    }

    private func snapshot(_ displays: [DisplayInfo], main: CGDirectDisplayID, separateSpaces: Bool) -> DisplaySnapshot {
        DisplaySnapshot(displays: displays, mainDisplayID: main, separateSpacesEnabled: separateSpaces)
    }

    @Test("No preference is a no-op")
    func noPreference() {
        let snap = snapshot([display("A", id: 1)], main: 1, separateSpaces: false)
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .none, dockEdge: .bottom) == .terminal(.noPreference))
    }

    @Test("Single display cannot be pinned, whatever the resolution says")
    func singleDisplay() {
        let snap = snapshot([display("A", id: 1)], main: 1, separateSpaces: false)
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .resolved(1, repaired: nil), dockEdge: .bottom) == .terminal(.singleDisplay))
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .notConnected, dockEdge: .bottom) == .terminal(.singleDisplay))
    }

    @Test("Unresolved preferred display reports not-connected")
    func displayNotConnected() {
        let snap = snapshot([display("A", id: 1), display("B", id: 2)], main: 1, separateSpaces: false)
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .notConnected, dockEdge: .bottom) == .terminal(.displayNotConnected))
    }

    @Test("Ambiguous identity is surfaced, never guessed (TDD §7.2)")
    func ambiguousIdentity() {
        let snap = snapshot([display("A", id: 1), display("B", id: 2)], main: 1, separateSpaces: false)
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .ambiguous, dockEdge: .bottom) == .terminal(.ambiguousIdentity))
        #expect(PinOutcome.ambiguousIdentity.userMessage != nil)
    }

    @Test("Separate Spaces on declines a BOTTOM Dock (Decision 2A, narrowed by ADR-009)")
    func unsupportedSeparateSpacesBottom() {
        let snap = snapshot([display("A", id: 1), display("B", id: 2)], main: 1, separateSpaces: true)
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .resolved(2, repaired: nil), dockEdge: .bottom) == .terminal(.unsupportedSeparateSpaces))
    }

    @Test("Separate Spaces on PINS a left/right Dock via main relocation (ADR-009, hardware-confirmed)")
    func separateSpacesLeftRightPins() {
        let snap = snapshot([display("A", id: 1), display("B", id: 2)], main: 1, separateSpaces: true)
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .resolved(2, repaired: nil), dockEdge: .left) == .reconfigure(2))
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .resolved(2, repaired: nil), dockEdge: .right) == .reconfigure(2))
    }

    @Test("Target already main is a no-op")
    func alreadyOnTarget() {
        let snap = snapshot([display("A", id: 1), display("B", id: 2)], main: 2, separateSpaces: false)
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .resolved(2, repaired: nil), dockEdge: .bottom) == .terminal(.alreadyOnTarget))
    }

    @Test("Valid off-main target on a multi-display, non-separate-Spaces setup reconfigures")
    func reconfigures() {
        let snap = snapshot(
            [display("A", id: 1, origin: .zero),
             display("B", id: 2, origin: CGPoint(x: 1920, y: 0))],
            main: 1,
            separateSpaces: false
        )
        #expect(MainDisplayPinner.decide(snapshot: snap, resolution: .resolved(2, repaired: nil), dockEdge: .bottom) == .reconfigure(2))
    }
}
