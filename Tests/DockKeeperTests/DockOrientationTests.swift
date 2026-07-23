import Testing
import Foundation
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
        #expect(settings.autoRecover == true)
    }

    @Test("Persists a changed lock edge")
    func persistsLockEdge() {
        let settings = makeSettings()
        settings.lockEdge = .left
        #expect(settings.lockEdge == .left)
    }
}
