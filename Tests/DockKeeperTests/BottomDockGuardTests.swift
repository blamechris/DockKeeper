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
    enabled: Bool = true,
    trusted: Bool = true
) -> BottomDockGuard.Snapshot {
    BottomDockGuard.Snapshot(
        displays: displays,
        preferredDisplayID: preferred,
        dockEdge: edge,
        separateSpacesEnabled: separateSpaces,
        featureEnabled: enabled,
        accessibilityTrusted: trusted
    )
}

/// Laptop left, external right — both bottom edges free. The arrangement the
/// spike's positive control ran on.
private let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
private let externalRight = CGRect(x: 1728, y: 0, width: 3840, height: 2160)

/// Portrait display stacked *above* the laptop: in CG top-left, "above" means
/// smaller y, so the portrait's maxY meets the laptop's minY.
private let portraitAbove = CGRect(x: -919, y: -2160, width: 1440, height: 2160)

private func zones(_ decision: BottomDockGuard.Decision) -> [BottomDockGuard.ClampZone] {
    guard case .guarding(let z) = decision else { return [] }
    return z
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

    /// The safety gate. A non-preferred display with a display flush beneath it
    /// is never clamped — and needs no clamp, because a summon cannot fire on a
    /// blocked bottom edge either.
    @Test("A blocked bottom edge is refused, not guarded")
    func blockedEdgeIsSkipped() {
        // preferred = laptop(1); portrait(2) sits above the laptop, so display 2's
        // bottom edge is the crossing boundary between them.
        let displays = [display(1, laptop, main: true), display(2, portraitAbove)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(idleReason(d) == .nothingToGuard(blockedDisplayIDs: [2]))
        #expect(zones(d).isEmpty)
    }

    @Test("Mixed arrangement guards the free display and skips the blocked one")
    func mixedArrangement() {
        let displays = [
            display(1, laptop, main: true),
            display(2, portraitAbove),
            display(3, externalRight),
        ]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(zones(d).map(\.displayID) == [3])
    }

    @Test("Safety geometry is evaluated last, so refusals name the real cause")
    func settingsDisqualifyBeforeGeometry() {
        // A blocked arrangement AND the feature off: the user hears about the
        // switch they control, not about their monitor arrangement.
        let displays = [display(1, laptop, main: true), display(2, portraitAbove)]
        let d = BottomDockGuard.decide(snapshot(displays: displays, enabled: false))
        #expect(idleReason(d) == .featureDisabled)
    }

    @Test("Guarding is never emitted with an empty zone list")
    func guardingIsNeverEmpty() {
        let cases: [BottomDockGuard.Snapshot] = [
            snapshot(displays: twoFree),
            snapshot(displays: twoFree, preferred: 2),
            snapshot(displays: [display(1, laptop, main: true), display(2, portraitAbove)]),
        ]
        for c in cases {
            if case .guarding(let z) = BottomDockGuard.decide(c) {
                #expect(!z.isEmpty)
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
            .featureDisabled, .edgeNotBottom, .separateSpacesOff, .singleDisplay,
            .noPreferredDisplay, .preferredDisplayNotConnected, .accessibilityNotGranted,
            .nothingToGuard(blockedDisplayIDs: [2]),
        ]
        for reason in reasons {
            #expect(!reason.explanation.isEmpty, "\(reason)")
        }
    }
}
