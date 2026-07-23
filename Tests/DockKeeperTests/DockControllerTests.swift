import Testing
import Foundation
@testable import DockKeeperCore

/// Recording fake for the `DockAdapter` seam (TDD §4.3 test seam).
private final class RecordingAdapter: DockAdapter, @unchecked Sendable {
    let name: String
    var available: Bool
    var orientation: DockOrientation?
    var setCalls: [DockOrientation] = []

    init(name: String, available: Bool = true, orientation: DockOrientation? = .bottom) {
        self.name = name
        self.available = available
        self.orientation = orientation
    }

    var isAvailable: Bool { available }
    func currentOrientation() -> DockOrientation? { orientation }
    func setOrientation(_ edge: DockOrientation) -> Bool {
        guard available else { return false }
        setCalls.append(edge)
        orientation = edge
        return true
    }
}

@Suite("DockController")
struct DockControllerTests {

    private func makeSettings() -> Settings {
        let suiteName = "com.dockkeeper.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return Settings(defaults: suite)
    }

    @Test("Drift is corrected through the primary adapter")
    func primaryPreferred() {
        let primary = RecordingAdapter(name: "primary", orientation: .bottom)
        let fallback = RecordingAdapter(name: "fallback")
        let controller = DockController(settings: makeSettings(), primary: primary, fallback: fallback)

        #expect(controller.setOrientation(.left))
        #expect(primary.setCalls == [.left])
        #expect(fallback.setCalls.isEmpty)
        #expect(!controller.isDegraded)
        #expect(controller.activeMechanismName == "primary")
    }

    @Test("Already on the locked edge is a no-op (DK-FR-001 S2)")
    func alignedNoOp() {
        let primary = RecordingAdapter(name: "primary", orientation: .left)
        let controller = DockController(settings: makeSettings(), primary: primary, fallback: RecordingAdapter(name: "fallback"))

        #expect(!controller.setOrientation(.left))
        #expect(primary.setCalls.isEmpty)
    }

    @Test("Primary unavailable falls back and reports degraded (DK-FR-001 S3)")
    func fallbackWhenPrimaryUnavailable() {
        let primary = RecordingAdapter(name: "primary", available: false, orientation: nil)
        let fallback = RecordingAdapter(name: "fallback", orientation: .bottom)
        let controller = DockController(settings: makeSettings(), primary: primary, fallback: fallback)

        #expect(controller.isDegraded)
        #expect(controller.activeMechanismName == "fallback")
        #expect(controller.setOrientation(.right))
        #expect(primary.setCalls.isEmpty)
        #expect(fallback.setCalls == [.right])
    }

    @Test("Current orientation prefers the live read, then the fallback read")
    func readPreference() {
        let primary = RecordingAdapter(name: "primary", orientation: .right)
        let fallback = RecordingAdapter(name: "fallback", orientation: .left)
        let controller = DockController(settings: makeSettings(), primary: primary, fallback: fallback)
        #expect(controller.currentOrientation() == .right)

        primary.orientation = nil  // live read fails → stale defaults read wins
        #expect(controller.currentOrientation() == .left)
    }

    @Test("Unknown orientation everywhere is treated as drift and applied (TDD §5.3)")
    func unknownStateAppliesDesired() {
        let primary = RecordingAdapter(name: "primary", orientation: nil)
        let fallback = RecordingAdapter(name: "fallback", orientation: nil)
        let controller = DockController(settings: makeSettings(), primary: primary, fallback: fallback)

        #expect(controller.setOrientation(.bottom))
        #expect(primary.setCalls == [.bottom])
    }

    @Test("Disabled settings block restoreToLockedEdge (DK-FR-004 S1)")
    func disabledBlocksRestore() {
        let settings = makeSettings()
        settings.isEnabled = false
        settings.lockEdge = .left
        let primary = RecordingAdapter(name: "primary", orientation: .bottom)
        let controller = DockController(settings: settings, primary: primary, fallback: RecordingAdapter(name: "fallback"))

        #expect(!controller.restoreToLockedEdge())
        #expect(primary.setCalls.isEmpty)
    }
}
