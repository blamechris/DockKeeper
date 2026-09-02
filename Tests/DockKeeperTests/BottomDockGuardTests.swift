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
/// smaller y, so the portrait's maxY meets the laptop's minY.
private let portraitAbove = CGRect(x: -919, y: -2160, width: 1440, height: 2160)

private func zones(_ decision: BottomDockGuard.Decision) -> [BottomDockGuard.ClampZone] {
    guard case .guarding(let z, _) = decision else { return [] }
    return z
}

private func skipped(_ decision: BottomDockGuard.Decision) -> [CGDirectDisplayID] {
    guard case .guarding(_, let s) = decision else { return [] }
    return s
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
            if case .guarding(let z, _) = BottomDockGuard.decide(c) {
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

    /// The invariant behind the whole safety gate, asserted directly rather than
    /// inferred from individual arrangements.
    @Test("No zone is ever emitted for a display with a blocked bottom edge")
    func zonesNeverIncludeBlockedDisplays() {
        let arrangements: [[DisplayInfo]] = [
            [display(1, laptop, main: true), display(2, portraitAbove)],
            [display(1, laptop, main: true), display(2, portraitAbove), display(3, externalRight)],
            [display(1, CGRect(x: 0, y: 0, width: 1000, height: 1000), main: true),
             display(2, CGRect(x: 0, y: 1000, width: 1000, height: 1000)),
             display(3, CGRect(x: 0, y: 2000, width: 1000, height: 1000))],
        ]
        for displays in arrangements {
            for preferred in displays.map(\.displayID) {
                let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: preferred))
                let frames = displays.map(\.frame)
                for zone in zones(d) {
                    let index = displays.firstIndex { $0.displayID == zone.displayID }!
                    #expect(
                        BottomDockGuard.bottomEdgeIsFree(index, among: frames),
                        "zone emitted for blocked display \(zone.displayID)"
                    )
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

    /// A partially-overlapped display is refused whole, so the spans that really
    /// can host a summon are left open. That is deliberate — see the docstring —
    /// but it must be reported, not hidden behind an unqualified "guarding".
    @Test("A partially overlapped display is skipped and reported, not silently dropped")
    func partialOverlapIsReported() {
        let external = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let laptopUnder = CGRect(x: 1056, y: 2160, width: 1728, height: 1117)
        let third = CGRect(x: 3840, y: 0, width: 1920, height: 1080)
        let displays = [
            display(1, laptopUnder, main: true), display(2, external), display(3, third),
        ]
        let d = BottomDockGuard.decide(snapshot(displays: displays, preferred: 1))
        #expect(zones(d).map(\.displayID) == [3])
        #expect(skipped(d).contains(2))
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
