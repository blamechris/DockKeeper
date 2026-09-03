import CoreGraphics
import Foundation
import Testing

@testable import DockKeeperCore

// Convenience fixtures ------------------------------------------------------

/// Frames are **CG global, top-left origin** throughout, matching
/// `CGDisplayBounds` / `DisplayInfo.frame` and the space an event tap reports.
private func display(
    _ id: CGDirectDisplayID,
    _ frame: CGRect,
    main: Bool = false
) -> DisplayInfo {
    DisplayInfo(
        id: "cg-\(id)", displayID: id, name: "D\(id)", isMain: main, frame: frame
    )
}

private func snapshot(
    displays: [DisplayInfo],
    preferred: CGDirectDisplayID? = 1,
    edge: DockOrientation = .bottom,
    separateSpaces: Bool = true,
    appEnabled: Bool = true,
    enabled: Bool = true,
    trusted: Bool = true
) -> BottomDockGuard.Snapshot {
    BottomDockGuard.Snapshot(
        displays: displays,
        preferredDisplayID: preferred,
        dockEdge: edge,
        separateSpacesEnabled: separateSpaces,
        appEnabled: appEnabled,
        featureEnabled: enabled,
        accessibilityTrusted: trusted
    )
}

/// Laptop left, external right — both bottom edges free. The arrangement the
/// spike's positive control ran on.
private let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
private let externalRight = CGRect(x: 1728, y: 0, width: 3840, height: 2160)

/// Portrait display stacked *above* the laptop: in CG top-left, "above" means
/// smaller y, so the portrait's maxY meets the laptop's minY. It overhangs the
/// laptop to the left (x −919 … 521 against the laptop's 0 … 1728), so since #83
/// it is *partly* guarded rather than refused whole.
private let portraitAbove = CGRect(x: -919, y: -2160, width: 1440, height: 2160)

/// Stacked above the laptop and **wholly** covered by it — no overhang either
/// side, so nothing of its bottom edge is free and it is refused outright. The
/// blocker extends past both ends, which also exercises clipping the blocker to
/// the guarded display's own extent.
private let coveredAbove = CGRect(x: 200, y: -900, width: 800, height: 900)

/// The owner's own desk, and the arrangement [#83](https://github.com/blamechris/DockKeeper/issues/83)
/// was filed from: a 4K stacked *above* the MacBook and overhanging it on both
/// sides — ~748 px left, ~1364 px right, ~2112 px of bottom edge with nothing
/// beneath it, against a shared strip of 1728 px. v0.9.3 stood the guard down
/// over all of it.
private let dellAbove = CGRect(x: -748, y: -2160, width: 3840, height: 2160)

private func zones(_ decision: BottomDockGuard.Decision) -> [BottomDockGuard.ClampZone] {
    guard case .guarding(let z, _, _) = decision else { return [] }
    return z
}

/// The displays a decision actually guards, de-duplicated and in order. Since
/// #83 a display contributes one zone per free span, so `zones.map(\.displayID)`
/// is a list of spans, not of displays — a distinction several assertions below
/// depend on.
private func guardedDisplayIDs(_ decision: BottomDockGuard.Decision) -> [CGDirectDisplayID] {
    var seen: Set<CGDirectDisplayID> = []
    return zones(decision).map(\.displayID).filter { seen.insert($0).inserted }
}

private func skipped(_ decision: BottomDockGuard.Decision) -> [CGDirectDisplayID] {
    guard case .guarding(_, let s, _) = decision else { return [] }
    return s
}

private func partiallyGuarded(_ decision: BottomDockGuard.Decision) -> [CGDirectDisplayID] {
    guard case .guarding(_, _, let p) = decision else { return [] }
    return p
}

/// The horizontal extents of a decision's zones for one display, in order.
private func spans(
    _ decision: BottomDockGuard.Decision, on displayID: CGDirectDisplayID
) -> [(minX: CGFloat, maxX: CGFloat)] {
    zones(decision).filter { $0.displayID == displayID }.map { ($0.frame.minX, $0.frame.maxX) }
}

private func idleReason(_ decision: BottomDockGuard.Decision) -> BottomDockGuard.IdleReason? {
    guard case .idle(let r) = decision else { return nil }
    return r
}

// MARK: - Geometry: which bottom edges are free (CG top-left)

@Suite("BottomDockGuard geometry")
struct BottomDockGuardGeometryTests {

    @Test("Side-by-side displays both have a free bottom edge")
    func sideBySideBothFree() {
        let frames = [laptop, externalRight]
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: frames))
        #expect(BottomDockGuard.bottomEdgeIsFree(1, among: frames))
    }

    /// The load-bearing orientation test. In CG top-left a display *beneath*
    /// another has the **greater** y. Inverting this would mark exactly the
    /// crossing boundaries as free and clamp them — trapping the pointer, which
    /// is the one outcome the gate exists to prevent.
    @Test("A display flush beneath blocks the upper display's bottom edge, not its own")
    func stackedBlocksTheUpperDisplay() {
        // portraitAbove sits above laptop: portraitAbove.maxY == laptop.minY == 0
        let frames = [portraitAbove, laptop]
        #expect(portraitAbove.maxY == laptop.minY)

        // The upper display's bottom edge is the crossing boundary -> blocked.
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: frames) == false)
        // The lower display has nothing beneath it -> free.
        #expect(BottomDockGuard.bottomEdgeIsFree(1, among: frames))
    }

    @Test("Stacked but horizontally disjoint does not block — the pointer cannot cross there")
    func stackedWithoutOverlapIsFree() {
        let upper = CGRect(x: 0, y: 0, width: 100, height: 100)
        let lowerOffToTheSide = CGRect(x: 500, y: 100, width: 100, height: 100)
        let frames = [upper, lowerOffToTheSide]
        #expect(upper.maxY == lowerOffToTheSide.minY)   // flush in y
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: frames))
    }

    @Test("Edge-touching in x only is not an overlap")
    func touchingHorizontallyIsNotOverlap() {
        let upper = CGRect(x: 0, y: 0, width: 100, height: 100)
        let lower = CGRect(x: 100, y: 100, width: 100, height: 100)  // starts where upper ends
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: [upper, lower]))
    }

    /// Mirrored displays share a frame. Identity by index, not by frame, or a
    /// display reports itself as its own blocker.
    @Test("Mirrored displays sharing a frame do not block each other")
    func mirroredDisplaysAreFree() {
        let frames = [laptop, laptop]
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: frames))
        #expect(BottomDockGuard.bottomEdgeIsFree(1, among: frames))
    }

    @Test("A single display's bottom edge is free")
    func singleDisplayIsFree() {
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: [laptop]))
    }

    @Test("Out-of-range index is not free, rather than trapping")
    func outOfRangeIsRefused() {
        #expect(BottomDockGuard.bottomEdgeIsFree(5, among: [laptop]) == false)
    }

    @Test("Sub-point gaps still count as flush; a real gap does not")
    func flushToleranceBoundaries() {
        let upper = CGRect(x: 0, y: 0, width: 100, height: 100)
        let almostFlush = CGRect(x: 0, y: 100.5, width: 100, height: 100)
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: [upper, almostFlush]) == false)

        let clearlyApart = CGRect(x: 0, y: 140, width: 100, height: 100)
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: [upper, clearlyApart]))
    }
}

// MARK: - Decision: every idle reason, in precedence order

@Suite("BottomDockGuard decision")
struct BottomDockGuardDecisionTests {

    private var twoFree: [DisplayInfo] {
        [display(1, laptop, main: true), display(2, externalRight)]
    }

    @Test("Off by default — the feature flag disqualifies first")
    func featureDisabled() {
        let d = BottomDockGuard.decide(snapshot(displays: twoFree, enabled: false))
        #expect(idleReason(d) == .featureDisabled)
    }

    @Test("A disabled DockKeeper is named as such, not as the feature being off")
    func appDisabledIsDistinct() {
        // #63: both switches live in Preferences ▸ Advanced. Reporting the
        // feature toggle when it is the master switch that is off sends support
        // — and the user — at the control they did not touch.
        let d = BottomDockGuard.decide(
            snapshot(displays: twoFree, appEnabled: false, enabled: true)
        )
        #expect(idleReason(d) == .appDisabled)
    }

    @Test("The master switch disqualifies before the feature toggle")
    func appDisabledOutranksFeatureDisabled() {
        let d = BottomDockGuard.decide(
            snapshot(displays: twoFree, appEnabled: false, enabled: false)
        )
        #expect(idleReason(d) == .appDisabled)
    }

    @Test("The two disabled reasons do not share an explanation")
    func disabledReasonsReadDifferently() {
        // The defect was a single "off" for both. Distinct enum cases are not
        // enough on their own — `--diagnostics` prints the explanation, so it is
        // the strings that have to differ.
        #expect(
            BottomDockGuard.IdleReason.appDisabled.explanation
                != BottomDockGuard.IdleReason.featureDisabled.explanation
        )
    }

    @Test("Only a bottom Dock is pointer-summoned")
    func nonBottomEdges() {
        for edge in [DockOrientation.left, .right] {
            let d = BottomDockGuard.decide(snapshot(displays: twoFree, edge: edge))
            #expect(idleReason(d) == .edgeNotBottom, "edge \(edge)")
        }
    }

    @Test("With one Space across displays there is no per-display summon")
    func separateSpacesOff() {
        let d = BottomDockGuard.decide(snapshot(displays: twoFree, separateSpaces: false))
        #expect(idleReason(d) == .separateSpacesOff)
    }

    @Test("One display has nothing to guard against")
    func singleDisplay() {
        let d = BottomDockGuard.decide(snapshot(displays: [display(1, laptop, main: true)]))
        #expect(idleReason(d) == .singleDisplay)
    }

    @Test("No preferred display means no target to hold the Dock on")
    func noPreference() {
        let d = BottomDockGuard.decide(snapshot(displays: twoFree, preferred: nil))
        #expect(idleReason(d) == .noPreferredDisplay)
    }

    @Test("A preferred display that is not attached is reported as such")
    func preferredAbsent() {
        let d = BottomDockGuard.decide(snapshot(displays: twoFree, preferred: 99))
        #expect(idleReason(d) == .preferredDisplayNotConnected)
    }

    @Test("Without Accessibility the guard says so instead of pretending")
    func untrusted() {
        let d = BottomDockGuard.decide(snapshot(displays: twoFree, trusted: false))
        #expect(idleReason(d) == .accessibilityNotGranted)
    }

    @Test("Guards every non-preferred display with a free bottom edge, and only those")
    func guardsNonPreferredOnly() {
        let d = BottomDockGuard.decide(snapshot(displays: twoFree, preferred: 1))
        let z = zones(d)
        #expect(z.count == 1)
        #expect(z.first?.displayID == 2)
        #expect(z.first?.frame == externalRight)
    }

    @Test("Choosing the other display flips which one is guarded")
    func preferenceSelectsTheZone() {
        let d = BottomDockGuard.decide(snapshot(displays: twoFree, preferred: 2))
        #expect(zones(d).map(\.displayID) == [1])
    }

    /// The safety gate. A bottom edge shared along its whole length with the
    /// display beneath is never clamped — and needs no clamp, because a summon
    /// is believed not to fire on a blocked edge either.
    @Test("A wholly blocked bottom edge is refused, not guarded")
    func blockedEdgeIsSkipped() {
        // preferred = laptop(1); covered(2) sits above the laptop with the
        // laptop spanning its entire width, so display 2's whole bottom edge is
        // the crossing boundary between them.
        let displays = [display(1, laptop, main: true), display(2, coveredAbove)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(idleReason(d) == .nothingToGuard(blockedDisplayIDs: [2]))
        #expect(zones(d).isEmpty)
    }

    @Test("Mixed arrangement guards the free display and skips the wholly blocked one")
    func mixedArrangement() {
        let displays = [
            display(1, laptop, main: true),
            display(2, coveredAbove),
            display(3, externalRight),
        ]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(guardedDisplayIDs(d) == [3])
        #expect(skipped(d) == [2])
        #expect(partiallyGuarded(d).isEmpty)
    }

    @Test("Safety geometry is evaluated last, so refusals name the real cause")
    func settingsDisqualifyBeforeGeometry() {
        // A blocked arrangement AND the feature off: the user hears about the
        // switch they control, not about their monitor arrangement.
        let displays = [display(1, laptop, main: true), display(2, coveredAbove)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, enabled: false))
        #expect(idleReason(d) == .featureDisabled)
    }

    @Test("Guarding is never emitted with an empty zone list")
    func guardingIsNeverEmpty() {
        let cases: [BottomDockGuard.Snapshot] = [
            snapshot(displays: twoFree),
            snapshot(displays: twoFree, preferred: 2),
            snapshot(displays: [display(1, laptop, main: true), display(2, portraitAbove)]),
            snapshot(displays: [display(1, laptop, main: true), display(2, coveredAbove)]),
            snapshot(displays: [display(1, laptop, main: true), display(2, dellAbove)]),
        ]
        for c in cases {
            if case .guarding(let z, _, _) = BottomDockGuard.decide(c) {
                #expect(!z.isEmpty)
            }
        }
    }

    /// The three lists partition the non-preferred displays, and
    /// `partiallyGuarded` is a claim *about* guarded displays rather than a
    /// fourth category. A report built on overlapping lists would double-count.
    @Test("zones, skipped and partiallyGuarded never contradict each other")
    func decisionListsArePartitioned() {
        let arrangements: [[DisplayInfo]] = [
            [display(1, laptop, main: true), display(2, dellAbove)],
            [display(1, laptop, main: true), display(2, portraitAbove), display(3, externalRight)],
            [display(1, laptop, main: true), display(2, coveredAbove), display(3, externalRight)],
            [display(1, laptop, main: true), display(2, laptop), display(3, externalRight)],
        ]
        for displays in arrangements {
            for preferred in displays.map(\.displayID) {
                let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: preferred))
                let guarded = Set(guardedDisplayIDs(d))
                #expect(guarded.isDisjoint(with: Set(skipped(d))))
                #expect(Set(partiallyGuarded(d)).isSubset(of: guarded))
                #expect(!guarded.contains(preferred))
            }
        }
    }
}

// MARK: - Clamping

@Suite("BottomDockGuard clamping")
struct BottomDockGuardClampTests {

    private let zone = BottomDockGuard.ClampZone(displayID: 2, frame: externalRight)

    /// Reproduces the spike's measured control: aiming at y = 2159 on a display
    /// whose maxY is 2160 holds the cursor at 2157.
    @Test("Reproduces the measured clamp: aimed at 2159, held at 2157")
    func matchesMeasuredControl() {
        #expect(zone.clampY == 2157)
        let clamped = BottomDockGuard.clamp(CGPoint(x: 3648, y: 2159), zones: [zone])
        #expect(clamped == CGPoint(x: 3648, y: 2157))
    }

    @Test("A point above the band is left alone")
    func aboveBandUntouched() {
        #expect(BottomDockGuard.clamp(CGPoint(x: 3648, y: 2000), zones: [zone]) == nil)
    }

    @Test("The band's upper limit itself is allowed — clamping is idempotent")
    func limitIsAllowed() {
        #expect(BottomDockGuard.clamp(CGPoint(x: 3648, y: 2157), zones: [zone]) == nil)
    }

    @Test("Horizontal travel is never altered — the pointer is slowed, not cornered")
    func xIsPreserved() {
        for x in [CGFloat(1728), CGFloat(2500), CGFloat(5567)] {
            let clamped = BottomDockGuard.clamp(CGPoint(x: x, y: 2159), zones: [zone])
            #expect(clamped?.x == x)
        }
    }

    @Test("Points outside the guarded display's horizontal span are untouched")
    func outsideHorizontallyUntouched() {
        #expect(BottomDockGuard.clamp(CGPoint(x: 100, y: 2159), zones: [zone]) == nil)
    }

    /// Half-open on the right so two side-by-side displays never both claim the
    /// seam column, which would make the result depend on zone ordering.
    @Test("The right edge belongs to the next display, not this one")
    func seamIsHalfOpen() {
        #expect(zone.contains(CGPoint(x: externalRight.maxX, y: 2159)) == false)
        #expect(zone.contains(CGPoint(x: externalRight.minX, y: 2159)))
    }

    @Test("With no zones nothing is ever clamped")
    func noZonesNoClamp() {
        #expect(BottomDockGuard.clamp(CGPoint(x: 3648, y: 2159), zones: []) == nil)
    }

    @Test("Multiple zones each guard their own display")
    func multipleZones() {
        let other = BottomDockGuard.ClampZone(displayID: 1, frame: laptop)
        let all = [zone, other]
        #expect(BottomDockGuard.clamp(CGPoint(x: 3648, y: 2159), zones: all)?.y == 2157)
        #expect(BottomDockGuard.clamp(CGPoint(x: 100, y: 1116), zones: all)?.y == laptop.maxY - 3)
    }

    @Test("Every idle reason renders a non-empty explanation")
    func explanationsExist() {
        let reasons: [BottomDockGuard.IdleReason] = [
            .appDisabled, .featureDisabled, .edgeNotBottom, .separateSpacesOff,
            .singleDisplay, .noPreferredDisplay, .preferredDisplayNotConnected,
            .accessibilityNotGranted, .nothingToGuard(blockedDisplayIDs: [2]),
            .mirrorsPreferredDisplay,
        ]
        for reason in reasons {
            #expect(!reason.explanation.isEmpty, "\(reason)")
        }
    }
}

// MARK: - Regressions from the 2026-08-29 review panel

@Suite("BottomDockGuard safety regressions")
struct BottomDockGuardSafetyTests {

    /// A zone must never act beyond the display it names. Without the
    /// `point.y < frame.maxY` bound the band is an unbounded half-plane, and one
    /// wrong frame — stale, mirrored, or transient — drags an entire other
    /// display's pointer positions onto this one.
    @Test("A zone never clamps a point below its own display")
    func zoneIsBoundedBelow() {
        let zone = BottomDockGuard.ClampZone(displayID: 1, frame: laptop)  // maxY 1117
        #expect(BottomDockGuard.clamp(CGPoint(x: 100, y: 1116), zones: [zone]) != nil)
        for y in [CGFloat(1117), 1200, 2159, 5000] {
            #expect(
                BottomDockGuard.clamp(CGPoint(x: 100, y: y), zones: [zone]) == nil,
                "y=\(y) is on another display and must be untouched"
            )
        }
    }

    /// Mirror-set members have distinct display IDs and identical bounds, so the
    /// preferred-ID check does not catch them. A band on "the other display"
    /// would land on the only screen the user can see.
    @Test("A display mirroring the preferred one is never guarded")
    func mirrorOfPreferredIsRefused() {
        let displays = [display(1, laptop, main: true), display(2, laptop)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(zones(d).isEmpty)
        #expect(idleReason(d) == .mirrorsPreferredDisplay)
    }

    @Test("A mirror is reported as mirroring, not as a blocked bottom edge")
    func mirrorReasonIsDistinct() {
        let displays = [display(1, laptop, main: true), display(2, laptop)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        // Saying "a display sits directly below another" would be a false
        // statement about the user's desk.
        #expect(idleReason(d) != .nothingToGuard(blockedDisplayIDs: [2]))
    }

    @Test("A mirror alongside a genuine second display guards only the second")
    func mirrorPlusRealDisplay() {
        let displays = [
            display(1, laptop, main: true),
            display(2, laptop),            // mirrors the preferred
            display(3, externalRight),     // genuinely separate
        ]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(zones(d).map(\.displayID) == [3])
        #expect(skipped(d) == [2])
    }

    /// Three displays in a vertical chain: only the bottom-most has a free
    /// bottom edge, so guarding must be exactly one display, not two.
    @Test("Vertical chain of three guards only the bottom-most")
    func verticalChain() {
        let top = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let mid = CGRect(x: 0, y: 1000, width: 1000, height: 1000)
        let bot = CGRect(x: 0, y: 2000, width: 1000, height: 1000)
        let displays = [display(1, top, main: true), display(2, mid), display(3, bot)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(zones(d).map(\.displayID) == [3])
        #expect(skipped(d) == [2])
    }

    /// **The invariant behind the whole safety gate**, restated for per-span
    /// clamping (#83) and asserted directly rather than inferred from
    /// individual arrangements.
    ///
    /// Before #83 this read "no zone for a display with a blocked bottom edge",
    /// which a whole-display refusal satisfied structurally. Per-span clamping
    /// buys coverage with interval arithmetic, and interval arithmetic can be
    /// wrong — so the property it has to hold is asserted on the geometry
    /// itself: **no emitted band ever overlaps a display flush beneath it.**
    /// That is what keeps the crossing route open, and it is the one failure
    /// this file exists to prevent.
    @Test("No emitted band ever overlaps a display flush beneath it")
    func zonesNeverCoverACrossingSpan() {
        let arrangements: [[DisplayInfo]] = [
            [display(1, laptop, main: true), display(2, dellAbove)],
            [display(1, laptop, main: true), display(2, portraitAbove)],
            [display(1, laptop, main: true), display(2, coveredAbove)],
            [display(1, laptop, main: true), display(2, portraitAbove), display(3, externalRight)],
            // A display straddled by two beneath it, leaving three free spans.
            [display(1, CGRect(x: -500, y: -1000, width: 3000, height: 1000), main: true),
             display(2, CGRect(x: 0, y: 0, width: 500, height: 500)),
             display(3, CGRect(x: 1500, y: 0, width: 500, height: 500))],
            [display(1, CGRect(x: 0, y: 0, width: 1000, height: 1000), main: true),
             display(2, CGRect(x: 0, y: 1000, width: 1000, height: 1000)),
             display(3, CGRect(x: 0, y: 2000, width: 1000, height: 1000))],
            // Blockers arriving out of left-to-right order, one of them nested
            // inside another. Bounds can overlap transiently during a
            // reconfiguration — the same reason the mirror gate tests by
            // intersection — and a sweep that took them in arrival order, or
            // let its cursor walk backwards onto a nested one, would emit a
            // band straight across the strip the wider blocker sits under.
            [display(1, CGRect(x: 10000, y: 0, width: 500, height: 500), main: true),
             display(2, CGRect(x: 0, y: 0, width: 3000, height: 500)),
             display(3, CGRect(x: 2200, y: 500, width: 400, height: 500)),
             display(4, CGRect(x: 500, y: 500, width: 1500, height: 500)),
             display(5, CGRect(x: 800, y: 500, width: 400, height: 500))],
            // Flush beneath in y but nowhere near in x. A blocker not clipped
            // to the guarded display's own extent would drag the sweep past
            // that display's right edge and emit a band wider than the screen
            // it names.
            [display(1, CGRect(x: 10000, y: 0, width: 500, height: 500), main: true),
             display(2, CGRect(x: 0, y: 0, width: 1000, height: 500)),
             display(3, CGRect(x: 3000, y: 500, width: 500, height: 500))],
            // The lower display OVERLAPS the upper one's bottom edge by 2 pt
            // rather than meeting it. macOS's arrangement UI cannot produce
            // this, but a bounds report during reconfiguration can — the very
            // premise the mirror gate in `decide` already defends against. The
            // symmetric `abs(...) < flushTolerance` test this file shipped in
            // v0.9.3 dropped such a neighbour from the blocker scan entirely
            // and emitted a full-width band across it (#83 review).
            [display(1, CGRect(x: 10000, y: 0, width: 500, height: 500), main: true),
             display(2, CGRect(x: 0, y: 0, width: 1920, height: 1080)),
             display(3, CGRect(x: 0, y: 1078, width: 1920, height: 1080))],
            // ...and the same overlap with an overhang, so there is still a
            // genuine free span to guard rather than a whole-display refusal.
            [display(1, CGRect(x: 10000, y: 0, width: 500, height: 500), main: true),
             display(2, CGRect(x: -400, y: 0, width: 2320, height: 1080)),
             display(3, CGRect(x: 0, y: 1078, width: 1920, height: 1080))],
        ]
        // The oracle must NOT re-derive the implementation's own "flush beneath"
        // formula. An earlier version of this test did, and was therefore
        // structurally blind to a bug in that formula — it agreed with the code
        // because it *was* the code. So both properties below are stated purely
        // in terms of which display CONTAINS a given point, which is ground
        // truth from the arrangement and involves no tolerance arithmetic.
        var bandViolations = 0  // property A: bands found on a crossing display's ground
        var crossingChecks = 0  // property B evaluated at a real crossing point

        for displays in arrangements {
            for preferred in displays.map(\.displayID) {
                let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: preferred))
                let zs = zones(d)
                for zone in zs {
                    guard let owner = displays
                        .first(where: { $0.displayID == zone.displayID })?.frame
                    else {
                        Issue.record("zone names display \(zone.displayID), which is not attached")
                        continue
                    }
                    // A zone is a sub-rectangle of the display it names: never
                    // wider than it, never on another display's y.
                    #expect(zone.frame.minX >= owner.minX && zone.frame.maxX <= owner.maxX)
                    #expect(zone.frame.minY == owner.minY && zone.frame.maxY == owner.maxY)

                    // PROPERTY A — the band never sits on the territory of a
                    // display that continues below the owner, i.e. one the
                    // pointer would cross into. Independent of any notion of
                    // "flush": if such a neighbour's rectangle covers ground we
                    // are about to clamp, clamping it is wrong however that
                    // overlap arose.
                    //
                    // Tested as a RECTANGLE INTERSECTION rather than by probing
                    // points. An earlier version sampled one point at
                    // `maxY - 0.5`, which made it blind to any overlap
                    // shallower than that — the property would have depended on
                    // a magic probe depth rather than on the geometry (#83
                    // delta review). `intersects` is false for edge-adjacent
                    // rects, so a *flush* neighbour starting exactly at
                    // `owner.maxY` is correctly not a violation, while an
                    // overlap of any depth at all is.
                    //
                    // The `maxY >` clause is what keeps the deliberately-
                    // overlapping *blocker* fixtures above (two displays
                    // sharing a band, used to prove the sweep collapses them)
                    // from reading as violations — they are siblings, not
                    // crossings.
                    let band = CGRect(
                        x: zone.frame.minX, y: zone.clampY,
                        width: zone.frame.width, height: owner.maxY - zone.clampY
                    )
                    for other in displays where other.displayID != zone.displayID {
                        guard other.frame.maxY > owner.maxY else { continue }
                        if other.frame.intersects(band) {
                            bandViolations += 1
                            Issue.record(
                                "band \(band) on display \(zone.displayID) overlaps display \(other.displayID) at \(other.frame)"
                            )
                        }
                    }
                }

                // PROPERTY B — the trapped-cursor property, and the reason the
                // whole feature has a geometry gate. Swept over each display's
                // ENTIRE bottom edge rather than over the zones, because it is
                // a claim about what must NOT be clamped: wherever a step
                // downward lands on another display, that x is the route
                // between the two screens and has to stay open. Stated without
                // any arithmetic — "which display contains this point" is
                // ground truth from the arrangement.
                //
                // This half does sample, at one point per point of width. That
                // is sufficient *because CoreGraphics reports integral display
                // bounds and every fixture here is integral* — not because a
                // unit step is safe in general. A sub-point violation window
                // off the integer grid could hide between samples, so keep the
                // fixtures integral or narrow the step.
                for owner in displays.map(\.frame) {
                    var x = owner.minX
                    while x < owner.maxX {
                        let inBand = CGPoint(x: x, y: owner.maxY - 0.5)
                        let justBelow = CGPoint(x: x, y: owner.maxY + 0.5)
                        if displays.contains(where: { $0.frame.contains(justBelow) }) {
                            crossingChecks += 1
                            #expect(
                                BottomDockGuard.clamp(inBand, zones: zs) == nil,
                                "x=\(x) is a crossing route off \(owner) and must not be clamped"
                            )
                        }
                        x += 1
                    }
                }
            }
        }

        // Without these the whole test can go vacuous under a refactor — zero
        // zones, or arrangements that no longer place anything beneath
        // anything, would leave every assertion above unexecuted and the suite
        // still green. Pin that both properties actually ran.
        #expect(bandViolations == 0, "property A recorded \(bandViolations) violation(s)")
        // 37,681 at the time of writing. The floor is deliberately an order of
        // magnitude below that: it exists to catch an invariant that has gone
        // *vacuous* — arrangements refactored until nothing sits beneath
        // anything — not to pin an exact count that every fixture edit would
        // have to chase.
        #expect(
            crossingChecks > 1000,
            "property B reached only \(crossingChecks) crossing points — the invariant has gone vacuous"
        )
    }

    /// `bottomEdgeIsFree` and `freeBottomSpans` are deliberately independent
    /// computations — one has no intervals in it at all — so they can be run
    /// against each other. A disagreement is an error in the arithmetic, and
    /// this is the test that would catch one.
    @Test("The whole-display predicate and the span sweep always agree")
    func predicateAndSpansAgree() {
        let pool = [
            laptop, externalRight, portraitAbove, coveredAbove, dellAbove,
            CGRect(x: 0, y: 1117, width: 1728, height: 1117),
            CGRect(x: -500, y: -1000, width: 3000, height: 1000),
            CGRect(x: 900, y: 0, width: 400, height: 400),
            CGRect(x: 1700, y: 0, width: 400, height: 400),
            // Sitting exactly ON the y tolerance, either side of it, and
            // OVERLAPPING it. Without these the pool contained only clean
            // flush-or-far pairs, so a boundary or sign disagreement between
            // the two functions — precisely what this test exists to catch —
            // had nothing to disagree about (#83 review).
            CGRect(x: 0, y: 1117.9, width: 1728, height: 900),
            CGRect(x: 0, y: 1118.0, width: 1728, height: 900),
            CGRect(x: 0, y: 1115.0, width: 1728, height: 900),
        ]
        for i in pool.indices {
            for j in pool.indices where j != i {
                for k in pool.indices where k != i && k != j {
                    let frames = [pool[i], pool[j], pool[k]]
                    for index in frames.indices {
                        let free = BottomDockGuard.bottomEdgeIsFree(index, among: frames)
                        let spans = BottomDockGuard.freeBottomSpans(index, among: frames)
                        let whollyFree = spans.count == 1
                            && spans[0].minX == frames[index].minX
                            && spans[0].maxX == frames[index].maxX
                        #expect(
                            free == whollyFree,
                            "predicate \(free) vs spans \(spans.map { ($0.minX, $0.maxX) }) for \(frames[index]) among \(frames)"
                        )
                    }
                }
            }
        }
    }

    /// Pins the tolerance itself. Changing `flushTolerance` from 1 to 2 left
    /// every other test green.
    @Test("Flush tolerance boundary is pinned at 1 point")
    func flushToleranceIsPinned() {
        let upper = CGRect(x: 0, y: 0, width: 100, height: 100)
        let gap09 = CGRect(x: 0, y: 100.9, width: 100, height: 100)
        let gap10 = CGRect(x: 0, y: 101.0, width: 100, height: 100)
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: [upper, gap09]) == false)
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: [upper, gap10]))
    }

    /// A partially-overlapped display is guarded over its free spans and left
    /// open over the shared one (#83), and the split is reported rather than
    /// hidden behind an unqualified "guarding".
    @Test("A partially overlapped display is guarded over its free spans and reported as partial")
    func partialOverlapIsGuardedAndReported() {
        let external = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let laptopUnder = CGRect(x: 1056, y: 2160, width: 1728, height: 1117)
        let third = CGRect(x: 3840, y: 0, width: 1920, height: 1080)
        let displays = [
            display(1, laptopUnder, main: true), display(2, external), display(3, third),
        ]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(guardedDisplayIDs(d) == [2, 3])
        // Both overhangs, and nothing over the 1056 … 2784 strip the laptop sits
        // under.
        #expect(spans(d, on: 2).map(\.minX) == [0, 2784])
        #expect(spans(d, on: 2).map(\.maxX) == [1056, 3840])
        #expect(partiallyGuarded(d) == [2])
        #expect(skipped(d).isEmpty)
        // The wholly free display is guarded, and is not reported as partial.
        #expect(spans(d, on: 3).count == 1)
    }
}

// MARK: - Per-free-span clamping (#83)

@Suite("BottomDockGuard free spans")
struct BottomDockGuardSpanTests {

    /// The regression #83 was filed for, asserted on the owner's real numbers.
    /// v0.9.3 returned `.idle(.nothingToGuard)` here and left ~2112 px of a
    /// 3840 px edge unguarded.
    @Test("The owner's stacked-with-overhang layout is guarded over both overhangs")
    func ownersArrangementIsGuarded() {
        let displays = [display(1, laptop, main: true), display(2, dellAbove)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))

        #expect(guardedDisplayIDs(d) == [2])
        // Whole-list comparisons, never `[0]` / `[1]`. A trapping subscript aborts the
        // test *process*, so under a mutation that changes the span count the suite
        // crashes instead of failing — and every mutation figure published for this file
        // becomes unmeasurable. Two of ADR-015's re-measured rows were wrong for exactly
        // that reason before this was fixed.
        #expect(spans(d, on: 2).map(\.minX) == [-748, 1728])
        #expect(spans(d, on: 2).map(\.maxX) == [0, 3092])
        // 748 + 1364 — the figure the issue quotes as "about 2100 px".
        let covered = spans(d, on: 2).reduce(CGFloat(0)) { $0 + ($1.maxX - $1.minX) }
        #expect(covered == 2112)
        // Guarded, but only partly — the report must not claim the whole edge.
        #expect(partiallyGuarded(d) == [2])
        #expect(skipped(d).isEmpty)
    }

    /// **The safety property, with its control.** The seed's instrument rule
    /// applies to unit tests too: "the pointer is held" means nothing without
    /// "and here it is not held", asserted in the same breath on the same
    /// arrangement.
    @Test("The shared span is never clamped, so the pointer can still cross")
    func sharedSpanStaysOpen() {
        let displays = [display(1, laptop, main: true), display(2, dellAbove)]
        let z = zones(BottomDockGuard.decide(snapshot(displays: displays, preferred: 1)))

        // Held on both overhangs...
        #expect(BottomDockGuard.clamp(CGPoint(x: -400, y: -1), zones: z)?.y == -3)
        #expect(BottomDockGuard.clamp(CGPoint(x: 2500, y: -1), zones: z)?.y == -3)
        // ...and free across the whole strip the laptop sits under, which is
        // the route between the two screens.
        for x in stride(from: CGFloat(0), through: 1727, by: 1) {
            if BottomDockGuard.clamp(CGPoint(x: x, y: -1), zones: z) != nil {
                Issue.record("x=\(x) is on the crossing span and must not be clamped")
                break
            }
        }
    }

    /// The seams between a free span and the shared span, pinned exactly. Both
    /// spans are half-open on the right, so the shared strip owns x = 0 and the
    /// right overhang owns x = 1728.
    @Test("Span seams are half-open, so the crossing strip owns its own edges")
    func spanSeamsAreHalfOpen() {
        let displays = [display(1, laptop, main: true), display(2, dellAbove)]
        let z = zones(BottomDockGuard.decide(snapshot(displays: displays, preferred: 1)))
        #expect(BottomDockGuard.clamp(CGPoint(x: -1, y: -1), zones: z) != nil)
        #expect(BottomDockGuard.clamp(CGPoint(x: 0, y: -1), zones: z) == nil)
        #expect(BottomDockGuard.clamp(CGPoint(x: 1727, y: -1), zones: z) == nil)
        #expect(BottomDockGuard.clamp(CGPoint(x: 1728, y: -1), zones: z) != nil)
    }

    /// A span narrows in `x` only. If it inherited a narrowed `y` too, `clampY`
    /// and the `frame.maxY` bound would stop describing the display the zone
    /// names, which is the blast-radius argument `ClampZone.contains` rests on.
    @Test("A span keeps its display's vertical extent, so clampY is unchanged")
    func spanKeepsVerticalExtent() {
        let displays = [display(1, laptop, main: true), display(2, dellAbove)]
        for zone in zones(BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))) {
            #expect(zone.frame.minY == dellAbove.minY)
            #expect(zone.frame.maxY == dellAbove.maxY)
            #expect(zone.clampY == dellAbove.maxY - BottomDockGuard.guardBand)
        }
    }

    @Test("A wholly free bottom edge yields exactly one span: the frame itself")
    func whollyFreeEdgeYieldsTheFrame() {
        let spans = BottomDockGuard.freeBottomSpans(1, among: [laptop, externalRight])
        #expect(spans == [externalRight])
    }

    @Test("A wholly covered bottom edge yields no span at all")
    func whollyCoveredEdgeYieldsNothing() {
        #expect(BottomDockGuard.freeBottomSpans(0, among: [coveredAbove, laptop]).isEmpty)
        // And the exactly-equal case, not just the strictly-inside one.
        let sameWidth = CGRect(x: 0, y: -900, width: 1728, height: 900)
        #expect(BottomDockGuard.freeBottomSpans(0, among: [sameWidth, laptop]).isEmpty)
    }

    @Test("A display overlapped in its middle yields a span either side")
    func middleOverlapSplitsInTwo() {
        let upper = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let lowerMiddle = CGRect(x: 400, y: 500, width: 200, height: 500)
        let spans = BottomDockGuard.freeBottomSpans(0, among: [upper, lowerMiddle])
        #expect(spans.map(\.minX) == [0, 600])
        #expect(spans.map(\.maxX) == [400, 1000])
    }

    /// Two displays beneath, leaving three gaps — and given to the sweep out of
    /// left-to-right order, because the sweep sorts and a sweep that did not
    /// would emit spans over a blocker it had already passed.
    @Test("Several blockers yield several spans, whatever order they arrive in")
    func severalBlockersInAnyOrder() {
        let upper = CGRect(x: 0, y: 0, width: 3000, height: 500)
        let left = CGRect(x: 500, y: 500, width: 500, height: 500)
        let right = CGRect(x: 2000, y: 500, width: 500, height: 500)
        let forward = BottomDockGuard.freeBottomSpans(0, among: [upper, left, right])
        let reversed = BottomDockGuard.freeBottomSpans(0, among: [upper, right, left])
        #expect(forward.map(\.minX) == [0, 1000, 2500])
        #expect(forward.map(\.maxX) == [500, 2000, 3000])
        #expect(forward == reversed)
    }

    /// Overlapping and fully nested blockers must collapse. A sweep that reset
    /// its cursor backwards on the second blocker would re-open a span over
    /// ground the first one already covers — the one way this arithmetic could
    /// clamp a crossing route.
    @Test("Overlapping and nested blockers collapse instead of re-opening a span")
    func overlappingBlockersCollapse() {
        let upper = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let wide = CGRect(x: 100, y: 500, width: 700, height: 500)     // 100 … 800
        let inside = CGRect(x: 300, y: 500, width: 200, height: 500)   // 300 … 500, nested
        let overlapping = CGRect(x: 600, y: 500, width: 300, height: 500)  // 600 … 900
        let spans = BottomDockGuard.freeBottomSpans(
            0, among: [upper, wide, inside, overlapping]
        )
        #expect(spans.map(\.minX) == [0, 900])
        #expect(spans.map(\.maxX) == [100, 1000])
    }

    /// A blocker wider than the display it blocks is clipped to that display,
    /// so a span is never measured against ground the display does not own.
    @Test("A blocker overhanging both ends is clipped to the guarded display")
    func blockerIsClippedToTheDisplay() {
        let upper = CGRect(x: 0, y: 0, width: 500, height: 500)
        let huge = CGRect(x: -5000, y: 500, width: 20000, height: 500)
        #expect(BottomDockGuard.freeBottomSpans(0, among: [upper, huge]).isEmpty)
    }

    /// Sub-point spans are float noise, discarded by the same tolerance that
    /// decides "flush beneath" in `y`. Discarding one only ever *reduces*
    /// clamping, so the tolerance fails open in both axes.
    @Test("A sub-point free span is discarded as noise; a one-point one is real")
    func subPointSpansAreDiscarded() {
        let upper = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let almostAll = CGRect(x: 0.9, y: 500, width: 999.1, height: 500)
        #expect(BottomDockGuard.freeBottomSpans(0, among: [upper, almostAll]).isEmpty)

        let leavingOnePoint = CGRect(x: 1.0, y: 500, width: 999, height: 500)
        let spans = BottomDockGuard.freeBottomSpans(0, among: [upper, leavingOnePoint])
        #expect(spans.map(\.minX) == [0])
        #expect(spans.map(\.maxX) == [1])
    }

    @Test("Edge-touching in x only does not split a span")
    func edgeTouchingDoesNotSplit() {
        let upper = CGRect(x: 0, y: 0, width: 100, height: 100)
        let cornerAdjacent = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(BottomDockGuard.freeBottomSpans(0, among: [upper, cornerAdjacent]) == [upper])
    }

    @Test("A display beneath but not flush does not split a span")
    func nonFlushDoesNotSplit() {
        let upper = CGRect(x: 0, y: 0, width: 100, height: 100)
        let farBelow = CGRect(x: 0, y: 140, width: 100, height: 100)
        #expect(BottomDockGuard.freeBottomSpans(0, among: [upper, farBelow]) == [upper])
    }

    @Test("Mirrored displays sharing a frame do not split each other's spans")
    func mirroredFramesDoNotSplit() {
        #expect(BottomDockGuard.freeBottomSpans(0, among: [laptop, laptop]) == [laptop])
    }

    /// `partial` is derived from `bottomEdgeIsFree`, not from `spans.count > 1`,
    /// and the difference is reachable: a display overlapped on exactly ONE
    /// side yields a single free span while being only partly covered. Counting
    /// spans would report it as fully guarded — the overstated-coverage bug the
    /// three-list design exists to prevent. Nothing caught this substitution
    /// before the #83 review.
    @Test("A display overhanging on one side only yields one span and is still reported partial")
    func oneSidedOverhangIsStillPartial() {
        // portraitAbove spans x −919 … 521 over a laptop at 0 … 1728: it hangs
        // off the left and is covered from 0 rightwards. One free span.
        let displays = [display(1, laptop, main: true), display(2, portraitAbove)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(spans(d, on: 2).map(\.minX) == [-919])
        #expect(spans(d, on: 2).map(\.maxX) == [0])
        #expect(spans(d, on: 2).count == 1)          // a span count of one...
        #expect(partiallyGuarded(d) == [2])          // ...and still only partly covered
    }

    /// The converse, so the pair pins the derivation from both sides: a wholly
    /// free edge is one span AND not partial.
    @Test("A wholly free display is one span and is not reported partial")
    func whollyFreeIsNotPartial() {
        let displays = [display(1, laptop, main: true), display(2, externalRight)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(spans(d, on: 2).count == 1)
        #expect(partiallyGuarded(d).isEmpty)
    }

    /// The overlap case the shipped symmetric flush test was blind to, pinned
    /// directly rather than only via the invariant (#83 review, critical).
    @Test("A display overlapping the bottom edge blocks it, rather than being ignored")
    func overlapBlocksLikeAFlushNeighbour() {
        let upper = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let overlappingBy2 = CGRect(x: 0, y: 1078, width: 1920, height: 1080)
        #expect(BottomDockGuard.bottomEdgeIsFree(0, among: [upper, overlappingBy2]) == false)
        #expect(BottomDockGuard.freeBottomSpans(0, among: [upper, overlappingBy2]).isEmpty)

        // ...and an overlap that leaves an overhang still yields just the overhang.
        let wider = CGRect(x: -400, y: 0, width: 2320, height: 1080)
        let spans = BottomDockGuard.freeBottomSpans(0, among: [wider, overlappingBy2])
        #expect(spans.map(\.minX) == [-400])
        #expect(spans.map(\.maxX) == [0])
    }

    /// A display *above* satisfies the first half of `isBeneath` and must be
    /// excluded by the second; a mirror sharing the exact frame likewise. Pins
    /// the clause that stops the one-sided test from over-blocking.
    @Test("A display above, or a mirror, is never treated as beneath")
    func aboveAndMirrorAreNotBeneath() {
        // portraitAbove sits above the laptop; the laptop's own edge stays free.
        #expect(BottomDockGuard.bottomEdgeIsFree(1, among: [portraitAbove, laptop]))
        #expect(BottomDockGuard.freeBottomSpans(1, among: [portraitAbove, laptop]) == [laptop])
        // Identical frames: neither blocks the other.
        #expect(BottomDockGuard.freeBottomSpans(0, among: [laptop, laptop]) == [laptop])
    }

    @Test("Out-of-range index yields no spans, rather than trapping")
    func outOfRangeYieldsNothing() {
        #expect(BottomDockGuard.freeBottomSpans(5, among: [laptop]).isEmpty)
    }
}

// MARK: - The registered default (DK-FR-014 S1)

@Suite("BottomDockGuard setting")
struct BottomDockGuardSettingTests {

    /// S1 claims the feature is off on a fresh install. Asserted against the
    /// **registration domain** rather than by passing `featureEnabled: false`
    /// into a Snapshot — the latter exercises the branch, not the default, and
    /// would stay green if someone flipped the registered value to `true`.
    @Test("Off on a fresh install")
    func defaultsToOff() {
        let settings = Settings(defaults: makeTestDefaults("bottomdockguard"))
        #expect(settings.lockBottomDockToDisplay == false)
    }

    @Test("Round-trips once set")
    func roundTrips() {
        let settings = Settings(defaults: makeTestDefaults("bottomdockguard"))
        settings.lockBottomDockToDisplay = true
        #expect(settings.lockBottomDockToDisplay)
        settings.lockBottomDockToDisplay = false
        #expect(settings.lockBottomDockToDisplay == false)
    }

    /// The guard's tap is driven by the app, not by an external writer, so the
    /// key is deliberately absent from `externallyObservedKeys` — but it IS
    /// re-read in `syncFromSettings`, which is how a CLI edit reaches a running
    /// app without a KVO storm.
    @Test("Not externally observed")
    func notExternallyObserved() {
        #expect(!Settings.externallyObservedKeys.contains("lockBottomDockToDisplay"))
    }
}
