import Testing
import Foundation
@testable import DockKeeperCore

@Suite("ControlCommand.parse (DK-FR-010)")
struct ControlCommandParseTests {

    /// Parse a `dockkeeper://…` string. Force-unwraps URL construction — the
    /// inputs here are all valid URL strings; parsing rejection is the enum's
    /// job, not `URL`'s.
    private func parse(_ string: String) -> ControlCommand? {
        ControlCommand.parse(url: URL(string: string)!)
    }

    // MARK: lock

    @Test("Locks to each user-selectable edge")
    func lockEdges() {
        #expect(parse("dockkeeper://lock?edge=bottom") == .lock(.bottom))
        #expect(parse("dockkeeper://lock?edge=left") == .lock(.left))
        #expect(parse("dockkeeper://lock?edge=right") == .lock(.right))
    }

    @Test("Edge parsing is case-insensitive")
    func lockEdgeCaseInsensitive() {
        #expect(parse("dockkeeper://lock?edge=LEFT") == .lock(.left))
        #expect(parse("dockkeeper://lock?edge=Right") == .lock(.right))
        #expect(parse("dockkeeper://lock?edge=bOtToM") == .lock(.bottom))
    }

    @Test("Host is matched case-insensitively")
    func hostCaseInsensitive() {
        #expect(parse("dockkeeper://LOCK?edge=left") == .lock(.left))
        #expect(parse("dockkeeper://Unlock") == .unlock)
    }

    @Test("Rejects the top edge — not user-selectable")
    func lockRejectsTop() {
        #expect(parse("dockkeeper://lock?edge=top") == nil)
    }

    @Test("Rejects a missing or unknown edge")
    func lockRejectsBadEdge() {
        #expect(parse("dockkeeper://lock") == nil)
        #expect(parse("dockkeeper://lock?edge=") == nil)
        #expect(parse("dockkeeper://lock?edge=diagonal") == nil)
        #expect(parse("dockkeeper://lock?minutes=5") == nil)
    }

    @Test("Ignores unrelated query parameters on lock")
    func lockIgnoresExtras() {
        #expect(parse("dockkeeper://lock?edge=left&foo=bar&edge2=right") == .lock(.left))
    }

    // MARK: unlock

    @Test("Parses unlock, ignoring extras")
    func unlock() {
        #expect(parse("dockkeeper://unlock") == .unlock)
        #expect(parse("dockkeeper://unlock?whatever=1") == .unlock)
    }

    // MARK: pause

    @Test("Pause without minutes means until resumed")
    func pauseUntilResumed() {
        #expect(parse("dockkeeper://pause") == .pause(nil))
    }

    @Test("Pause with positive minutes yields seconds")
    func pauseMinutes() {
        #expect(parse("dockkeeper://pause?minutes=15") == .pause(15 * 60))
        #expect(parse("dockkeeper://pause?minutes=1") == .pause(60))
        #expect(parse("dockkeeper://pause?minutes=90") == .pause(90 * 60))
    }

    @Test("Pause accepts fractional minutes")
    func pauseFractionalMinutes() {
        #expect(parse("dockkeeper://pause?minutes=1.5") == .pause(90))
    }

    @Test("Pause rejects zero, negative, and non-numeric minutes")
    func pauseRejectsBadMinutes() {
        #expect(parse("dockkeeper://pause?minutes=0") == nil)
        #expect(parse("dockkeeper://pause?minutes=-5") == nil)
        #expect(parse("dockkeeper://pause?minutes=abc") == nil)
        #expect(parse("dockkeeper://pause?minutes=") == nil)
        #expect(parse("dockkeeper://pause?minutes=inf") == nil)
        #expect(parse("dockkeeper://pause?minutes=nan") == nil)
    }

    @Test("Pause caps minutes at 24 hours")
    func pauseCapsAtDay() {
        let cap = ControlCommand.maxPauseSeconds
        #expect(parse("dockkeeper://pause?minutes=1440") == .pause(cap))       // exactly 24h
        #expect(parse("dockkeeper://pause?minutes=2000") == .pause(cap))       // over → clamped
        #expect(parse("dockkeeper://pause?minutes=100000") == .pause(cap))
    }

    @Test("Pause ignores unrelated query parameters")
    func pauseIgnoresExtras() {
        #expect(parse("dockkeeper://pause?minutes=15&foo=bar") == .pause(15 * 60))
        #expect(parse("dockkeeper://pause?foo=bar") == .pause(nil))
    }

    // MARK: resume

    @Test("Parses resume")
    func resume() {
        #expect(parse("dockkeeper://resume") == .resume)
    }

    // MARK: rejection

    @Test("Rejects unknown hosts")
    func rejectsUnknownHost() {
        #expect(parse("dockkeeper://frobnicate") == nil)
        #expect(parse("dockkeeper://") == nil)
        #expect(parse("dockkeeper://status") == nil)  // status is read-only, not a command
    }

    @Test("Rejects foreign URL schemes")
    func rejectsForeignScheme() {
        #expect(parse("http://lock?edge=left") == nil)
        #expect(parse("dock://lock?edge=left") == nil)
        #expect(parse("dockkeeperx://lock?edge=left") == nil)
    }
}

@Suite("StatusSummary (DK-FR-010 / DK-FR-007)")
struct StatusSummaryTests {

    @Test("CLI lines match the documented status output")
    func cliLines() {
        let summary = StatusSummary(
            isEnabled: true,
            lockEdge: .left,
            currentEdge: .bottom,
            mechanism: "CoreDock",
            coreDockAvailable: true
        )
        #expect(summary.cliLines == [
            "Enabled:    yes",
            "Lock edge:  Left",
            "Dock is on: Bottom",
            "CoreDock:   available",
        ])
    }

    @Test("Unknown current edge and unavailable CoreDock are reported honestly")
    func cliLinesDegraded() {
        let summary = StatusSummary(
            isEnabled: false,
            lockEdge: .bottom,
            currentEdge: nil,
            mechanism: "defaults + restart",
            coreDockAvailable: false
        )
        #expect(summary.cliLines[0] == "Enabled:    no")
        #expect(summary.cliLines[2] == "Dock is on: unknown")
        #expect(summary.cliLines[3] == "CoreDock:   unavailable (using defaults fallback)")
    }

    @Test("Voice line reflects enabled state and mechanism")
    func voiceLine() {
        let enabled = StatusSummary(
            isEnabled: true, lockEdge: .left, currentEdge: .left,
            mechanism: "CoreDock", coreDockAvailable: true
        )
        #expect(enabled.voiceLine.contains("DockKeeper is enabled"))
        #expect(enabled.voiceLine.contains("left"))
        #expect(enabled.voiceLine.contains("Mechanism: CoreDock"))

        let disabled = StatusSummary(
            isEnabled: false, lockEdge: .bottom, currentEdge: nil,
            mechanism: "CoreDock", coreDockAvailable: true
        )
        #expect(disabled.voiceLine.contains("DockKeeper is disabled"))
    }
}
