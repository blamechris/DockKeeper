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

/// Every idle reason, built by walking a cyclic successor function.
///
/// Two mechanisms keep this list honest, and it is worth being exact about what
/// each one does — three review rounds in a row corrected an overstatement in
/// this comment, each time because it described the *intent* rather than the
/// mechanism:
///
/// - **The compiler** fails the build when `IdleReason` gains a case, because
///   `nextIdleReason` below has no `default`. That is the whole of its
///   contribution. It does **not** force the new case into this list: satisfying
///   the error with `case .newCase: return .appDisabled` compiles, leaves the
///   walk ten entries long, and ships the reason with no coverage. Review
///   demonstrated exactly that, twice, against two different versions of this
///   file.
/// - **`chainVisitsEveryReason`** asserts the walk is ten long, which is what
///   turns a spliced-in case into a red test and then into a required caption.
///   It cannot see a case that nothing points at.
///
/// Swift cannot close the remaining gap: `IdleReason` carries an associated
/// value, so it cannot be `CaseIterable`, and nothing can enumerate it. What is
/// actually achieved is that the build breaks *in this file* and a count
/// assertion sits next to the break. That is less than "the list cannot go
/// stale", and saying the stronger thing is what earned rounds 2 and 3.
private let allIdleReasons: [BottomDockGuard.IdleReason] = {
    var out: [BottomDockGuard.IdleReason] = [.appDisabled]
    var reason = nextIdleReason(.appDisabled)
    // Bounded so a malformed cycle fails a test rather than hanging the runner —
    // a test that hangs is worse than one that fails, and this file has already
    // been bitten once by an assertion that aborted the process.
    while reason != .appDisabled && out.count < 64 {
        out.append(reason)
        reason = nextIdleReason(reason)
    }
    return out
}()

/// Total by construction, and **cyclic**: each case names the next, and the last
/// names the first. The return type is non-optional on purpose — an optional
/// would let a new case be satisfied with `nil`, silently truncating the chain.
private func nextIdleReason(
    _ reason: BottomDockGuard.IdleReason
) -> BottomDockGuard.IdleReason {
    switch reason {
    case .appDisabled:                  return .featureDisabled
    case .featureDisabled:              return .edgeNotBottom
    case .edgeNotBottom:                return .separateSpacesOff
    case .separateSpacesOff:            return .singleDisplay
    case .singleDisplay:                return .noPreferredDisplay
    case .noPreferredDisplay:           return .preferredDisplayNotConnected
    case .preferredDisplayNotConnected: return .accessibilityNotGranted
    // One blocked display is all this reason's explanation renders.
    case .accessibilityNotGranted:      return .nothingToGuard(blockedDisplayIDs: [2])
    case .nothingToGuard:               return .mirrorsPreferredDisplay
    case .mirrorsPreferredDisplay:      return .appDisabled
    }
}

/// Two external displays, both wholly free of anything beneath them: the only
/// shape in this file where **both** optional sentences must be absent, which is
/// what makes their conditions falsifiable in the "must not appear" direction.
private let twoWhollyFree: [DisplayInfo] = [
    display(1, laptop, main: true), display(2, freeStanding), display(3, freeStanding2),
]

/// One guarded display and one refused outright: `skipped` non-empty while
/// `partiallyGuarded` is empty.
private let skippedButNothingPartial: [DisplayInfo] = [
    display(1, laptop, main: true), display(2, freeStanding), display(3, coveredAbove),
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

    /// **Every idle caption, as a literal.** The sweeps above check that the
    /// captions are non-empty and pairwise distinct, which a *wrong* caption
    /// satisfies just as well as a right one: rewording `.appDisabled` to name
    /// the feature toggle instead of the master switch — the exact conflation
    /// shipped as #63, which pointed support at the switch the user had not
    /// touched — leaves it non-empty and distinct from all nine others.
    ///
    /// So the wording is pinned. Five of these are produced by the generic
    /// fallback, which string-surgeries the `"idle — "` prefix off
    /// `IdleReason.explanation`; that coupling is undeclared and now lives in a
    /// different file from the strings it cuts, so retitling the prefix would
    /// otherwise silently render "Inactive — idle: needs a second display."
    /// The walk must visit every reason and come back round.
    ///
    /// **The count is the load-bearing assertion, and it is deliberately a
    /// literal.** The previous version of this test asserted three properties,
    /// and review showed two of them could not fail while the first passed: the
    /// walk is deterministic and exits only on reaching `.appDisabled`, so a
    /// repeated element implies a cycle that never terminates and therefore hits
    /// the bound, and "the last element's successor is the first" is the loop's
    /// own exit condition restated. Worse, the malformation the test was named
    /// for slipped through — pointing `.edgeNotBottom` straight back at
    /// `.appDisabled` closes the cycle while dropping seven reasons, and all
    /// three expectations passed.
    ///
    /// A literal count catches that, and is what makes a spliced-in case fail
    /// here first and then in `idleCaptionsAreExact` until it has a caption.
    @Test("The idle-reason chain visits every reason and closes")
    func chainVisitsEveryReason() {
        #expect(
            allIdleReasons.count == 10,
            "the chain skipped a reason, gained one, or did not come back round"
        )
        // Distinct by construction if the count holds, but stated because a
        // future non-deterministic successor would break the implication.
        #expect(Set(allIdleReasons.map(String.init(describing:))).count == allIdleReasons.count)
    }

    @Test("Every idle caption, word for word")
    func idleCaptionsAreExact() {
        let expected: [(BottomDockGuard.IdleReason, String)] = [
            (.featureDisabled, ""),
            (.appDisabled, "Inactive while DockKeeper is turned off."),
            (.accessibilityNotGranted,
             "Waiting for Accessibility permission — grant it in System Settings \u{203A} "
                + "Privacy & Security \u{203A} Accessibility."),
            (.nothingToGuard(blockedDisplayIDs: [2]),
             "Not available on this arrangement: every bottom edge DockKeeper could hold "
                + "is covered along its whole length by the screens below it, so that edge is "
                + "the route your pointer takes between them. Holding it would trap your cursor."),
            (.mirrorsPreferredDisplay,
             "Not available while your displays are mirrored — they show the same pixels, "
                + "so there is no second bottom edge to hold."),
            // The generic fallback. Each must read as one sentence, not two
            // state words in a row.
            (.edgeNotBottom, "Inactive — only a bottom Dock is pointer-summoned."),
            (.separateSpacesOff,
             "Inactive — needs \u{201C}Displays have separate Spaces\u{201D} on."),
            (.singleDisplay, "Inactive — needs a second display."),
            (.noPreferredDisplay, "Inactive — no preferred display chosen."),
            (.preferredDisplayNotConnected, "Inactive — preferred display isn't connected."),
        ]
        #expect(expected.count == allIdleReasons.count)
        for (reason, want) in expected {
            #expect(BottomDockGuard.caption(for: .idle(reason)) == want, "\(reason)")
        }
    }

    /// The fallback's contract, stated as the property rather than as five more
    /// literals: it strips the shared prefix, so no caption may contain the word
    /// the prefix carries. This is what fails if `explanation`'s prefix is
    /// retitled without the caption following.
    @Test("The generic fallback strips the reason's own state word")
    func fallbackStripsIdlePrefix() {
        for reason in allIdleReasons {
            let caption = BottomDockGuard.caption(for: .idle(reason))
            #expect(!caption.lowercased().contains("idle"), "\(reason): \(caption)")
        }
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

    /// **Both optional clauses, asserted absent.** Every other guarding
    /// assertion in this suite uses an arrangement where `partiallyGuarded` is
    /// non-empty, so nothing here could tell `if !partial.isEmpty` from
    /// `if true`: on two wholly-free displays the latter prints "0 partly
    /// covered (the strips above other displays stay open …)", naming strips
    /// that do not exist. Exact equality on a desk with neither list populated
    /// is the only thing that catches it.
    @Test("Neither qualifying clause appears when its list is empty")
    func emptyListsProduceNoClause() {
        let line = BottomDockGuard.diagnosticsLine(
            for: BottomDockGuard.decide(snapshot(twoWhollyFree)), paused: false
        )
        #expect(line == "guarding 2 display(s) over 2 span(s)")
    }

    /// Skipped populated, partial empty — the half the flagship arrangement and
    /// the overhang arrangement between them never produce.
    @Test("A refused display is reported without a partly-covered clause")
    func skippedWithoutPartial() {
        let decision = BottomDockGuard.decide(snapshot(skippedButNothingPartial))
        #expect(partialIDs(decision).isEmpty)          // the shape this test needs
        #expect(BottomDockGuard.diagnosticsLine(for: decision, paused: false)
            == "guarding 1 display(s) over 1 span(s); 1 not covered (blocked edge or mirrored)")
    }

    /// Partial populated, skipped empty — the owner's own desk, whole.
    @Test("An overhanging display is reported without a not-covered clause")
    func partialWithoutSkipped() {
        let decision = BottomDockGuard.decide(
            snapshot([display(1, laptop, main: true), display(2, dellAbove)])
        )
        #expect(BottomDockGuard.diagnosticsLine(for: decision, paused: false)
            == "guarding 1 display(s) over 2 span(s); 1 partly covered "
                + "(the strips above other displays stay open — they are the route between them)")
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

private func partialIDs(_ decision: BottomDockGuard.Decision) -> [CGDirectDisplayID] {
    guard case .guarding(_, _, let p) = decision else { return [] }
    return p
}
