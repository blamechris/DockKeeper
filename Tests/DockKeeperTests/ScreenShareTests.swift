import Testing
import Foundation
@testable import DockKeeperCore

/// DK-FR-011 / ADR-011 — hide the Dock during screen capture.
///
/// Only the pure `decide` core is exercised here (kickoff §7): the private
/// CoreDock auto-hide reads/writes and the `CGSIsScreenWatcherPresent` detector
/// are never called from tests — that would move the real Dock and needs the
/// on-device hardware cell (M6/M12). `decide` holds every rule, so the table
/// below is the whole behavioral contract.
@Suite("ScreenShareHider.decide")
struct ScreenShareDecideTests {

    private typealias Action = ScreenShareHider.Action

    /// One row of the truth table: the three inputs and the expected action.
    private struct Case {
        let capturing: Bool
        let weHidIt: Bool
        let currentAutoHide: Bool
        let expected: Action
        let note: String
    }

    /// Exhaustive: every combination of `capturing × weHidIt × currentAutoHide`
    /// (2³ = 8 rows). This is the complete decision contract of ADR-011.
    @Test("Full truth table over capturing × weHidIt × currentAutoHide (all 8)")
    func exhaustiveTable() {
        let cases: [Case] = [
            // Capture running.
            Case(capturing: true,  weHidIt: false, currentAutoHide: false, expected: .hide,
                 note: "Share starts, user auto-hide OFF → we hide"),
            Case(capturing: true,  weHidIt: false, currentAutoHide: true,  expected: .none,
                 note: "Share starts, user already auto-hides → never touch (and never record a hide)"),
            Case(capturing: true,  weHidIt: true,  currentAutoHide: true,  expected: .none,
                 note: "Already hidden by us → idempotent"),
            Case(capturing: true,  weHidIt: true,  currentAutoHide: false, expected: .none,
                 note: "Already hidden by us, even if auto-hide reads off → idempotent, no re-hide"),
            // Capture stopped.
            Case(capturing: false, weHidIt: true,  currentAutoHide: true,  expected: .restore,
                 note: "Share ends, we hid it → restore (auto-hide back off)"),
            Case(capturing: false, weHidIt: true,  currentAutoHide: false, expected: .restore,
                 note: "Share ends, we hid it → restore even if already off (clears the flag)"),
            Case(capturing: false, weHidIt: false, currentAutoHide: true,  expected: .none,
                 note: "No capture, user runs auto-hide, we didn't hide → leave it alone"),
            Case(capturing: false, weHidIt: false, currentAutoHide: false, expected: .none,
                 note: "No capture, nothing hidden → nothing to do"),
        ]

        #expect(cases.count == 8)  // guards against an accidentally dropped row
        for row in cases {
            let action = ScreenShareHider.decide(
                capturing: row.capturing,
                weHidIt: row.weHidIt,
                currentAutoHide: row.currentAutoHide
            )
            #expect(action == row.expected, "\(row.note)")
        }
    }

    @Test("Never hides when the user already runs auto-hide, so it never restores it (ADR-011)")
    func neverTouchesUserAutoHide() {
        // The user set auto-hide themselves: no hide while capturing…
        #expect(ScreenShareHider.decide(capturing: true, weHidIt: false, currentAutoHide: true) == .none)
        // …and because we never recorded a hide (weHidIt stays false), stopping
        // capture is a no-op — we never "restore" (turn off) what we didn't set.
        #expect(ScreenShareHider.decide(capturing: false, weHidIt: false, currentAutoHide: true) == .none)
    }

    @Test("Hides once, then stays put across repeated capture ticks (idempotent)")
    func hideThenIdempotent() {
        // First tick of a capture with auto-hide off → hide.
        #expect(ScreenShareHider.decide(capturing: true, weHidIt: false, currentAutoHide: false) == .hide)
        // Subsequent ticks (now weHidIt == true, auto-hide == true) → no-op.
        #expect(ScreenShareHider.decide(capturing: true, weHidIt: true, currentAutoHide: true) == .none)
    }

    @Test("Restores exactly once on capture-stop, then stays quiet (idempotent)")
    func restoreThenIdempotent() {
        // Capture stops while we hold the hide → restore.
        #expect(ScreenShareHider.decide(capturing: false, weHidIt: true, currentAutoHide: true) == .restore)
        // After restore the flag is cleared; a further no-capture tick → no-op.
        #expect(ScreenShareHider.decide(capturing: false, weHidIt: false, currentAutoHide: false) == .none)
    }
}

@Suite("ScreenShareHider lifecycle & settings")
struct ScreenShareLifecycleTests {

    /// Isolated defaults so the test never touches the real user domain.
    private func makeSettings(_ test: String = #function) -> Settings {
        makeTestSettings("ScreenShare", test)
    }

    @Test("Feature is opt-in: off by default (setting-off short-circuit)")
    func offByDefault() {
        // Off by default → AppState never starts the poll, so `decide` (and any
        // CoreDock write) is never reached. This is the setting-level guard that
        // keeps the private API untouched unless the user opts in.
        #expect(makeSettings().hideDockDuringScreenShare == false)
    }

    @Test("Persists the opt-in")
    func persists() {
        let settings = makeSettings()
        settings.hideDockDuringScreenShare = true
        #expect(settings.hideDockDuringScreenShare == true)
    }

    @MainActor
    @Test("A fresh hider holds no hide, so teardown-restore is a safe no-op")
    func freshHiderHasNoHide() {
        // Constructing the hider and reading the flag touches no private API.
        let hider = ScreenShareHider()
        #expect(hider.weHidIt == false)
        hider.restoreIfNeeded()  // guarded by weHidIt → returns before any CoreDock call
        #expect(hider.weHidIt == false)
    }

    @Test("Documented default poll cadence")
    func pollCadence() {
        #expect(ScreenShareHider.defaultCheckInterval == 3)
    }
}
