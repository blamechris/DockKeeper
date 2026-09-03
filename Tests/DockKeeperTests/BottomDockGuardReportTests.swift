import CoreGraphics
import Foundation
import Testing

@testable import DockKeeperCore

// What the guard tells the user ---------------------------------------------
//
// Coverage for `BottomDockGuard.caption(for:)`, `diagnosticsLine(for:paused:)`
// and `armedLogLine(zones:)` — the three strings that make claims about the
// user's desk (#84). They were unreachable from any test while they lived in
// the app target, which is how #83 was able to change all three at once in the
// direction where a mistake is a *false claim to the user*.
//
// Two rules shape the assertions:
//
// 1. **The oracle is the arrangement, never the code.** Where a count is
//    checked, the expected value is known from how the fixture was *built* —
//    "I placed three other displays with free bottom edges" — not recomputed as
//    `Set(zones.map(\.displayID)).count`, which is the expression under test.
//    An invariant that re-derives its own formula agrees with the code because
//    it *is* the code; that is the mistake #83's first safety invariant made.
// 2. **Whole strings, not substrings, for the rich cases.** A `contains` check
//    passes just as happily when a second sentence has been appended, dropped
//    or attached to the wrong branch. The exact-equality tests below are what
//    make the partial/skipped swap detectable.

private func display(
    _ id: CGDirectDisplayID, _ frame: CGRect, main: Bool = false
) -> DisplayInfo {
    DisplayInfo(id: "cg-\(id)", displayID: id, name: "D\(id)", isMain: main, frame: frame)
}

private func snapshot(
    _ displays: [DisplayInfo], preferred: CGDirectDisplayID? = 1
) -> BottomDockGuard.Snapshot {
    BottomDockGuard.Snapshot(
        displays: displays,
        preferredDisplayID: preferred,
        dockEdge: .bottom,
        separateSpacesEnabled: true,
        appEnabled: true,
        featureEnabled: true,
        accessibilityTrusted: true
    )
}

/// Every idle reason, in one list, so the sweeps below cannot silently miss a
/// case added later. `nothingToGuard` carries an associated value; one blocked
/// display is enough to render it.
private let allIdleReasons: [BottomDockGuard.IdleReason] = [
    .appDisabled, .featureDisabled, .edgeNotBottom, .separateSpacesOff,
    .singleDisplay, .noPreferredDisplay, .preferredDisplayNotConnected,
    .accessibilityNotGranted, .nothingToGuard(blockedDisplayIDs: [2]),
    .mirrorsPreferredDisplay,
]

// MARK: - Fixtures whose answers are known by construction

private let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)

/// The owner's desk: a 4K stacked above the laptop and overhanging it on both
/// sides. **One display, two free spans** — the arrangement that makes
/// "distinct displays" and "zones" different numbers, and therefore the only
/// kind of fixture on which the count mutation is observable at all.
private let dellAbove = CGRect(x: -748, y: -2160, width: 3840, height: 2160)

/// A free-standing display well clear of the 4K's extent, with nothing beneath
/// its bottom edge: exactly one span, wholly guarded.
private let freeStanding = CGRect(x: 4000, y: 0, width: 1000, height: 1000)
private let freeStanding2 = CGRect(x: 6000, y: 0, width: 1000, height: 1000)

/// Stacked above `freeStanding` / `freeStanding2` and wholly covered by it, so
/// no part of its bottom edge is free: skipped outright, never guarded.
private let coveredAbove = CGRect(x: 4200, y: -800, width: 600, height: 800)
private let coveredAbove2 = CGRect(x: 6200, y: -800, width: 600, height: 800)

/// **The flagship arrangement.** Built so that every number in every string is
/// a different number, which is what makes each of them independently able to
/// fail:
///
/// - 3 other displays are guarded (2, 3, 5) — known because each was placed
///   with at least part of its bottom edge over empty space
/// - over 4 spans — display 2 contributes two (the overhangs), 3 and 5 one each
/// - 1 is partly covered (2) — the 4K's shared strip with the laptop
/// - 2 are not covered at all (4, 6) — each wholly covered by the display below
///
/// 3 ≠ 4 catches counting zones as displays; 1 ≠ 2 catches swapping the partial
/// and skipped branches. A fixture where those coincided would let both edits
/// through.
private let everyBranch: [DisplayInfo] = [
    display(1, laptop, main: true),
    display(2, dellAbove),
    display(3, freeStanding),
    display(4, coveredAbove),
    display(5, freeStanding2),
    display(6, coveredAbove2),
]

@Suite("BottomDockGuard report — the arrangement the counts describe")
struct BottomDockGuardReportShapeTests {

    /// Guards the fixture itself. Every assertion in this file rests on this
    /// arrangement producing 4 zones over 3 displays with 1 partial and 2
    /// skipped; if `decide` ever stops doing that, the string tests below would
    /// go quietly vacuous rather than fail, so the shape is asserted first and
    /// separately.
    @Test("The flagship arrangement really does have four spans over three displays")
    func fixtureShape() {
        guard case .guarding(let zones, let skipped, let partial) =
            BottomDockGuard.decide(snapshot(everyBranch))
        else {
            Issue.record("expected a guarding decision")
            return
        }
        #expect(zones.count == 4)
        #expect(Set(zones.map(\.displayID)) == [2, 3, 5])
        #expect(zones.filter { $0.displayID == 2 }.count == 2)   // the two overhangs
        #expect(partial == [2])
        #expect(Set(skipped) == [4, 6])
    }
}

@Suite("BottomDockGuard caption")
struct BottomDockGuardCaptionTests {

    /// The whole caption for the arrangement that exercises every branch. Exact
    /// equality on purpose: this single assertion fails if the display count is
    /// taken from zones, if the partial and skipped sentences are swapped, if
    /// either is dropped, or if any of the wording changes without the change
    /// being looked at.
    @Test("Every branch at once, as the user reads it")
    func everyBranchCaption() {
        let caption = BottomDockGuard.caption(for: BottomDockGuard.decide(snapshot(everyBranch)))
        #expect(caption == """
            Active — holding the bottom edge on 3 other display(s). \
            1 of them only partly: the stretches that sit directly above your other screens \
            are left open, because that is the route your pointer takes between them, and \
            the Dock can still be summoned there. \
            2 display(s) are not covered at all, because other screens sit beneath their \
            whole bottom edge, or they mirror your preferred display — the Dock can still \
            be summoned there.
            """)
    }

    /// The owner's own desk, and the narrowest statement of the #83 count bug:
    /// one display, two spans. The caption must say **one**. Counting zones
    /// says two, and "holding the bottom edge on 2 other displays" when the
    /// user has one other display is a false statement about their desk.
    @Test("One overhanging display is one display, not two")
    func overhangCountsAsOneDisplay() {
        let decision = BottomDockGuard.decide(
            snapshot([display(1, laptop, main: true), display(2, dellAbove)])
        )
        #expect(zoneCount(decision) == 2)          // two spans...
        let caption = BottomDockGuard.caption(for: decision)
        #expect(caption.hasPrefix("Active — holding the bottom edge on 1 other display(s)."))
        #expect(!caption.contains("on 2 other display(s)"))
    }

    /// Guarded-and-whole is the case with no qualifier at all: a caption that
    /// appended the partial or skipped sentence here would be claiming a gap
    /// the arrangement does not have.
    @Test("A wholly free edge gets no qualifying sentence")
    func wholeCoverageIsUnqualified() {
        let decision = BottomDockGuard.decide(
            snapshot([display(1, laptop, main: true), display(2, freeStanding)])
        )
        #expect(BottomDockGuard.caption(for: decision)
            == "Active — holding the bottom edge on 1 other display(s).")
    }

    /// Partial without skipped, and skipped without partial, asserted whole.
    /// The flagship test has both branches live at once, which cannot
    /// distinguish "the skipped sentence is emitted unconditionally" from
    /// "the skipped sentence is emitted when skipped is non-empty".
    @Test("Partial alone, and skipped alone, each render only their own sentence")
    func branchesAreIndependent() {
        let partialOnly = BottomDockGuard.caption(for: BottomDockGuard.decide(
            snapshot([display(1, laptop, main: true), display(2, dellAbove)])
        ))
        #expect(partialOnly.contains("only partly"))
        #expect(!partialOnly.contains("not covered at all"))

        let skippedOnly = BottomDockGuard.caption(for: BottomDockGuard.decide(
            snapshot([
                display(1, laptop, main: true),
                display(2, freeStanding), display(3, coveredAbove),
            ])
        ))
        #expect(skippedOnly.contains("not covered at all"))
        #expect(!skippedOnly.contains("only partly"))
    }

    /// A mirror of the preferred display is reported through the *skipped*
    /// sentence, which names mirroring as one of its two causes — so the
    /// mirror-plus-partial case must not lose either half.
    @Test("A mirror and an overhang are reported together")
    func mirrorPlusPartial() {
        let decision = BottomDockGuard.decide(snapshot([
            display(1, laptop, main: true),
            display(2, dellAbove),
            display(3, laptop),          // identical bounds to the preferred: a mirror
        ]))
        #expect(skippedIDs(decision) == [3])
        let caption = BottomDockGuard.caption(for: decision)
        #expect(caption.contains("on 1 other display(s)"))
        #expect(caption.contains("1 of them only partly"))
        #expect(caption.contains("1 display(s) are not covered at all"))
    }

    /// `featureDisabled` is deliberately blank — there is nothing to say under a
    /// toggle the user just switched off — and it is the **only** blank one.
    /// Every other reason must say something, and must say something different,
    /// or the caption cannot answer "I turned it on and nothing happened".
    @Test("Exactly one idle reason is blank; the rest are non-empty and all distinct")
    func idleCaptionsAreDistinct() {
        var captions: [String] = []
        for reason in allIdleReasons {
            captions.append(BottomDockGuard.caption(for: .idle(reason)))
        }
        #expect(captions.filter(\.isEmpty).count == 1)
        #expect(BottomDockGuard.caption(for: .idle(.featureDisabled)).isEmpty)
        let speaking = captions.filter { !$0.isEmpty }
        #expect(speaking.count == allIdleReasons.count - 1)
        #expect(Set(speaking).count == speaking.count, "two idle reasons share a caption")
    }

    /// The two reasons that describe an *arrangement* rather than a setting are
    /// the ones a user is most likely to read as a bug, so each states its own
    /// cause. Conflating them tells someone with mirrored screens that their
    /// pointer would be trapped, which is not why the guard stood down.
    @Test("Mirrored and nothing-to-guard do not share wording")
    func arrangementReasonsAreSpecific() {
        let nothing = BottomDockGuard.caption(for: .idle(.nothingToGuard(blockedDisplayIDs: [2])))
        let mirrored = BottomDockGuard.caption(for: .idle(.mirrorsPreferredDisplay))
        #expect(nothing.contains("trap your cursor"))
        #expect(mirrored.contains("mirrored"))
        #expect(!mirrored.contains("trap your cursor"))
    }
}

@Suite("BottomDockGuard diagnostics line")
struct BottomDockGuardDiagnosticsLineTests {

    /// The support answer, whole, for the arrangement that exercises every
    /// branch — and with the pause qualifier off, so the pause test below is
    /// measuring only the difference the pause makes.
    @Test("Every branch at once, as support reads it")
    func everyBranchLine() {
        let line = BottomDockGuard.diagnosticsLine(
            for: BottomDockGuard.decide(snapshot(everyBranch)), paused: false
        )
        #expect(line == "guarding 3 display(s) over 4 span(s)"
            + "; 1 partly covered "
            + "(the strips above other displays stay open — they are the route between them)"
            + "; 2 not covered (blocked edge or mirrored)")
    }

    /// Displays and spans are different units, and the line prints both. The
    /// owner's desk is the case where they differ, and printing "2 display(s)
    /// over 2 span(s)" there is the overstatement #83 was filed about.
    @Test("Displays and spans are reported as the different numbers they are")
    func displaysAndSpansAreDistinctUnits() {
        let line = BottomDockGuard.diagnosticsLine(
            for: BottomDockGuard.decide(
                snapshot([display(1, laptop, main: true), display(2, dellAbove)])
            ),
            paused: false
        )
        #expect(line.hasPrefix("guarding 1 display(s) over 2 span(s)"))
    }

    /// A pause suspends corrections; the guard is prevention and has nothing to
    /// resume (#62). The line must therefore *qualify* rather than go quiet,
    /// and must add nothing at all when there is no pause.
    @Test("The pause qualifier is added only when paused, and changes nothing else")
    func pauseQualifierIsAdditive() {
        let decision = BottomDockGuard.decide(snapshot(everyBranch))
        let unpaused = BottomDockGuard.diagnosticsLine(for: decision, paused: false)
        let paused = BottomDockGuard.diagnosticsLine(for: decision, paused: true)
        #expect(paused == unpaused
            + "; unaffected by the pause below (this feature is not released by pausing)")
    }

    /// Pause is a property of corrections, not of the decision, so it must not
    /// leak into the idle lines — which are the reason the guard stood down.
    @Test("An idle line is its reason's explanation, paused or not")
    func idleLineIsTheExplanation() {
        for reason in allIdleReasons {
            #expect(BottomDockGuard.diagnosticsLine(for: .idle(reason), paused: false)
                == reason.explanation)
            #expect(BottomDockGuard.diagnosticsLine(for: .idle(reason), paused: true)
                == reason.explanation)
        }
    }

    /// Extends the existing non-emptiness check with the property that actually
    /// matters for a support transcript: two different causes must not print
    /// the same line, or the report cannot tell them apart.
    @Test("Every idle reason prints a non-empty line, and no two print the same one")
    func idleLinesAreDistinct() {
        let lines = allIdleReasons.map {
            BottomDockGuard.diagnosticsLine(for: .idle($0), paused: false)
        }
        for (reason, line) in zip(allIdleReasons, lines) {
            #expect(!line.isEmpty, "\(reason)")
        }
        #expect(Set(lines).count == lines.count, "two idle reasons share a diagnostics line")
    }
}

@Suite("BottomDockGuard armed log line")
struct BottomDockGuardArmedLogTests {

    /// Per #77/#78 this line is the only honest evidence that the tap armed, so
    /// it is the one that must not overstate. Two spans on one display is the
    /// case where span and display counts diverge.
    @Test("Spans and displays are counted separately")
    func spansAndDisplaysCountedSeparately() {
        let zones = zonesOf(BottomDockGuard.decide(
            snapshot([display(1, laptop, main: true), display(2, dellAbove)])
        ))
        #expect(BottomDockGuard.armedLogLine(zones: zones)
            == "Bottom-Dock guard: armed over 2 span(s) on 1 display(s)")
    }

    /// The flagship arrangement again, where the two counts are 4 and 3 — so
    /// neither can be standing in for the other.
    @Test("Four spans over three displays")
    func manySpansManyDisplays() {
        let zones = zonesOf(BottomDockGuard.decide(snapshot(everyBranch)))
        #expect(BottomDockGuard.armedLogLine(zones: zones)
            == "Bottom-Dock guard: armed over 4 span(s) on 3 display(s)")
    }

    /// The armed line and the diagnostics line report the same desk from two
    /// different processes, and support reads them side by side. They are built
    /// from the same decision, so their counts agreeing is a property worth
    /// holding rather than a coincidence to notice later.
    @Test("The armed line and the diagnostics line agree on both counts")
    func logAndDiagnosticsAgree() {
        let decision = BottomDockGuard.decide(snapshot(everyBranch))
        let armed = BottomDockGuard.armedLogLine(zones: zonesOf(decision))
        let diag = BottomDockGuard.diagnosticsLine(for: decision, paused: false)
        #expect(armed.contains("4 span(s)") && diag.contains("4 span(s)"))
        #expect(armed.contains("3 display(s)") && diag.contains("3 display(s)"))
    }
}

// Small readers, kept out of the assertions so the expected values above stay
// literal rather than computed.

private func zonesOf(_ decision: BottomDockGuard.Decision) -> [BottomDockGuard.ClampZone] {
    guard case .guarding(let z, _, _) = decision else { return [] }
    return z
}

private func zoneCount(_ decision: BottomDockGuard.Decision) -> Int { zonesOf(decision).count }

private func skippedIDs(_ decision: BottomDockGuard.Decision) -> [CGDirectDisplayID] {
    guard case .guarding(_, let s, _) = decision else { return [] }
    return s
}
