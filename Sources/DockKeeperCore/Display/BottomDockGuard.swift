import CoreGraphics
import Foundation

/// Keeps a **bottom** Dock on the preferred display while "Displays have
/// separate Spaces" is on, by *preventing* the pointer summon that moves it
/// (DK-FR-014, ADR-015).
///
/// **Prevention, never relocation.** Every relocation candidate is falsified on
/// hardware — pointer warp, `CGEventPost` under a real Accessibility grant, AX
/// geometry (read-only), and `SLSSetDockRect{WithOrientation,WithReason}`, which
/// accept a rect on another display without the Dock following. Placement is the
/// Dock process's own decision and nothing in userspace reproduces it. What *is*
/// reachable is the trigger: a bottom Dock is summoned by holding the pointer at
/// the very bottom row of a display, so denying access to that row on every
/// display we do not want the Dock on removes the trigger. See
/// `docs/spikes/separate-spaces-pinning.md`.
///
/// This type is the pure half: it decides **whether** to guard and **which
/// bands** to hold, and never touches an event tap. The tap lives in the app
/// target (`BottomDockGuardTap`), so every rule below is unit-testable without
/// hardware, a second display, or an Accessibility grant.
public enum BottomDockGuard {

    // MARK: - Geometry

    /// Points of a guarded display's bottom edge kept out of reach.
    ///
    /// Three, matching the value measured in the spike: aiming at `y = 2159` on
    /// a display of height 2160 held the cursor at `y = 2157`. Large enough that
    /// the pointer cannot land on the trigger row between event deliveries,
    /// small enough to be imperceptible.
    public static let guardBand: CGFloat = 3

    /// Tolerance for "flush against" when comparing display edges, in points.
    /// Arrangements are integral in practice; this absorbs float noise only.
    private static let flushTolerance: CGFloat = 1

    /// Whether display `index` has a **free** bottom edge — nothing sits flush
    /// beneath it sharing any horizontal span.
    ///
    /// Two independent things hang off this and they pull in opposite
    /// directions, which is why it is one function with one meaning:
    ///
    /// - **Safety.** A bottom edge with another display flush beneath it is a
    ///   *crossing boundary* — the route the pointer takes between the two
    ///   screens. Clamping it would trap the cursor. This is what DockLock's own
    ///   `warn_incompatible_display` exists for, and it is a hard refusal here,
    ///   never an optimization.
    /// - **Necessity — INFERRED, and weaker than it first reads.** A blocked
    ///   bottom edge is *believed* not to host a summon either: the pointer
    ///   crosses into the display beneath instead of dwelling. That rests on a
    ///   single owner observation on one stacked portrait rig, immediately
    ///   followed in the spike by "whether any harder push can summon on a
    ///   shared edge is UNKNOWN" — and that rig was itself majority-free, with
    ///   roughly two thirds of the edge unobstructed. Do not quote it as
    ///   CONFIRMED.
    ///
    /// Safety is the reason a shared span is skipped; necessity is only the
    /// reason skipping it is *believed* to cost nothing.
    ///
    /// **This predicate is whole-display, and since #83 it no longer decides
    /// what is clamped** — `freeBottomSpans` does, span by span. The two are
    /// kept as separate computations rather than one defined in terms of the
    /// other, because that makes them a differential pair: a test asserts they
    /// agree on every arrangement, so an error in the interval arithmetic shows
    /// up as a disagreement with a predicate that has no intervals in it. What
    /// this one still decides is what the *report* says — a display this
    /// returns `false` for while `freeBottomSpans` returns something is
    /// **partly** guarded, and `decide` says so rather than claiming the whole
    /// display.
    ///
    /// **Coordinates are Core Graphics global, top-left origin** — the space
    /// `CGDisplayBounds` and therefore `DisplayInfo.frame` use, and the space an
    /// event tap reports locations in. `y` grows *downward*, so a display
    /// beneath this one has `minY ≈ this.maxY`. The spike's probe used
    /// `NSScreen.frame`, which is Cocoa bottom-left, and its test reads inverted
    /// against this one on purpose. Getting this backwards would clamp exactly
    /// the crossing boundaries it must refuse, so `BottomDockGuardTests` pins
    /// both orientations.
    ///
    /// Indexed rather than matched by frame: mirrored displays share a frame,
    /// and an identity test that cannot tell them apart is the wrong primitive
    /// for a safety gate.
    public static func bottomEdgeIsFree(_ index: Int, among frames: [CGRect]) -> Bool {
        guard frames.indices.contains(index) else { return false }
        let me = frames[index]
        return !frames.indices.contains { other in
            guard other != index else { return false }
            let beneath = abs(frames[other].minY - me.maxY) < flushTolerance
            let overlapsHorizontally =
                min(frames[other].maxX, me.maxX) - max(frames[other].minX, me.minX) > 0
            return beneath && overlapsHorizontally
        }
    }

    /// The stretches of display `index`'s bottom edge with **nothing beneath
    /// them** — the parts that can host a summon and cannot be a crossing
    /// route, returned as sub-rectangles of the display's own frame so a
    /// `ClampZone` can be built from one directly.
    ///
    /// **Why this exists (#83).** `bottomEdgeIsFree` refuses whole displays, so
    /// a display overlapped anywhere along its bottom edge was left entirely
    /// unguarded. On the owner's own desk that abandoned ~2100 px of a 3840 px
    /// edge: a 4K stacked above a MacBook overhangs it by ~748 px left and
    /// ~1364 px right, and the guard stood down over all of it because the
    /// middle ~1728 px is shared. ADR-015 declined this on the strength of an
    /// UNKNOWN — whether a summon can fire on a *shared* edge — but that
    /// UNKNOWN is about the shared span, and these spans are free by
    /// construction. Nothing is beneath them, so clamping them rests on nothing
    /// unknown.
    ///
    /// **The safety property is preserved exactly, not approximately.** Every
    /// span this returns is disjoint from every blocker, so the shared span —
    /// the route the pointer takes between the two screens — is never clamped.
    /// `BottomDockGuardTests` asserts that directly as an invariant over whole
    /// arrangements rather than leaving it to be inferred from examples, because
    /// the hazard this file exists to prevent is a trapped cursor.
    ///
    /// **The cost, stated rather than glossed.** Within a free span the pointer
    /// is held 3 pt clear of the edge, so a *slow* downward push there resists,
    /// as it already does on any fully guarded display. That costs nothing
    /// reachable: a free span has no display beneath it, so it was never a
    /// route — the route is the shared span, which stays open, and horizontal
    /// travel into it is never impeded (`clamping` alters `y` only).
    ///
    /// Sub-point spans are discarded as float noise, using the same
    /// `flushTolerance` that decides "flush beneath" in `y`. Discarding one can
    /// only *reduce* clamping, so the tolerance fails open in both axes.
    ///
    /// Coordinates are CG global, top-left, exactly as in `bottomEdgeIsFree` —
    /// a display beneath this one has `minY ≈ this.maxY`.
    public static func freeBottomSpans(_ index: Int, among frames: [CGRect]) -> [CGRect] {
        guard frames.indices.contains(index) else { return [] }
        let me = frames[index]
        guard me.width >= flushTolerance else { return [] }

        // Blockers, clipped to my own horizontal extent. `> 0` matches
        // `bottomEdgeIsFree`'s overlap test exactly: edge-touching in x is not
        // an overlap, so a display abutting this one's corner blocks nothing.
        var blockers: [(lo: CGFloat, hi: CGFloat)] = []
        for other in frames.indices where other != index {
            let f = frames[other]
            guard abs(f.minY - me.maxY) < flushTolerance else { continue }
            let lo = max(f.minX, me.minX)
            let hi = min(f.maxX, me.maxX)
            if hi - lo > 0 { blockers.append((lo, hi)) }
        }
        blockers.sort { $0.lo < $1.lo }

        // Sweep left to right, emitting the gaps. `cursor` only ever moves
        // right (`max`), so overlapping and nested blockers collapse instead of
        // re-opening a span that something already covers — the one way this
        // arithmetic could emit a span over a blocker.
        var spans: [CGRect] = []
        var cursor = me.minX
        func emit(upTo limit: CGFloat) {
            guard limit - cursor >= flushTolerance else { return }
            spans.append(
                CGRect(x: cursor, y: me.minY, width: limit - cursor, height: me.height)
            )
        }
        for blocker in blockers {
            emit(upTo: blocker.lo)
            cursor = max(cursor, blocker.hi)
        }
        emit(upTo: me.maxX)
        return spans
    }

    // MARK: - Inputs

    /// Everything the decision reads, captured as a value so it is pure.
    public struct Snapshot: Sendable, Equatable {
        public let displays: [DisplayInfo]
        /// The display the Dock should stay on. `nil` when the user has not
        /// chosen one — the guard has no target and stays idle.
        public let preferredDisplayID: CGDirectDisplayID?
        public let dockEdge: DockOrientation
        public let separateSpacesEnabled: Bool
        /// `Settings.isEnabled` — DockKeeper's master switch. Carried
        /// separately from `featureEnabled` so a refusal can name which of the
        /// two is off, and required rather than defaulted for the reason #65
        /// established: an omitted guard input must not be silently supplied.
        public let appEnabled: Bool
        /// `Settings.lockBottomDockToDisplay` — opt-in, default false.
        public let featureEnabled: Bool
        /// `AXIsProcessTrusted()`. Without it `CGEventTapCreate` yields a tap
        /// that never fires, so the guard reports *why* rather than pretending.
        public let accessibilityTrusted: Bool

        public init(
            displays: [DisplayInfo],
            preferredDisplayID: CGDirectDisplayID?,
            dockEdge: DockOrientation,
            separateSpacesEnabled: Bool,
            appEnabled: Bool,
            featureEnabled: Bool,
            accessibilityTrusted: Bool
        ) {
            self.displays = displays
            self.preferredDisplayID = preferredDisplayID
            self.dockEdge = dockEdge
            self.separateSpacesEnabled = separateSpacesEnabled
            self.appEnabled = appEnabled
            self.featureEnabled = featureEnabled
            self.accessibilityTrusted = accessibilityTrusted
        }
    }

    // MARK: - Outputs

    /// A band along one **free span** of a display's bottom edge that the
    /// pointer is held out of. A display with a wholly free bottom edge yields
    /// one zone spanning it; a display overhanging another yields one per
    /// overhang, and none over the shared span (#83).
    public struct ClampZone: Sendable, Equatable {
        public let displayID: CGDirectDisplayID
        /// The guarded span: a sub-rectangle of the display's frame, CG
        /// top-left, narrowed in `x` to the free stretch and keeping the
        /// display's full `y` extent — so `clampY` and the `frame.maxY` bound
        /// below still describe the display this zone names, never a
        /// neighbour. For a wholly free edge this *is* the display's frame.
        public let frame: CGRect
        /// The greatest `y` the pointer may hold inside `frame`. A location
        /// below this, within the frame's horizontal span, is pulled back here.
        public let clampY: CGFloat

        public init(displayID: CGDirectDisplayID, frame: CGRect) {
            self.displayID = displayID
            self.frame = frame
            self.clampY = frame.maxY - BottomDockGuard.guardBand
        }

        /// Whether `point` (CG global, top-left) falls in this zone's guarded
        /// band. Horizontal containment is half-open on the right so two
        /// side-by-side displays never both claim the seam.
        ///
        /// **Bounded below by `frame.maxY`, and that bound is load-bearing.**
        /// Without it the band is an unbounded half-plane: every point below
        /// `clampY` anywhere on the desktop matches, so one wrong frame — stale,
        /// mirrored, or transient during reconfiguration — stops being a local
        /// nuisance and yanks an entire other display's worth of pointer
        /// positions onto this one. The gate that authorises a zone
        /// (`bottomEdgeIsFree`) only proves something about a one-point
        /// neighbourhood beneath the edge, so a zone must not act on more than
        /// the display it names. Keeping the two predicates the same shape caps
        /// the blast radius of failure modes nobody has thought of yet.
        public func contains(_ point: CGPoint) -> Bool {
            point.x >= frame.minX && point.x < frame.maxX
                && point.y > clampY && point.y < frame.maxY
        }

        /// `point` with its `y` pulled back to the band's upper limit. `x` is
        /// never altered — horizontal travel along the bottom of a guarded
        /// display stays free, so the pointer is slowed, never cornered.
        public func clamping(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: clampY)
        }
    }

    /// Why the guard is not holding anything. Every case is a safe no-op, and
    /// every case is reportable — `--diagnostics` prints it, so "nothing is
    /// happening" is never silent.
    public enum IdleReason: Sendable, Equatable {
        /// DockKeeper itself is off, so nothing runs. Kept distinct from
        /// `featureDisabled` because the two switches sit in the same window:
        /// a report that conflated them pointed support at the toggle the user
        /// had *not* touched (#63).
        case appDisabled
        /// `lockBottomDockToDisplay` is off. The default.
        case featureDisabled
        /// Only a bottom Dock is pointer-summoned; left/right home to the main
        /// display and are already handled by `MainDisplayPinner` (ADR-009).
        case edgeNotBottom
        /// With one Space across all displays there is no per-display summon.
        case separateSpacesOff
        /// Nothing to guard against with one display.
        case singleDisplay
        /// No preferred display chosen, so there is no display to keep it on.
        case noPreferredDisplay
        /// The preferred display is not currently attached.
        case preferredDisplayNotConnected
        /// The tap cannot be created without an Accessibility grant.
        case accessibilityNotGranted
        /// Every non-preferred display has a bottom edge blocked along its
        /// **whole** length, so no span of one can be clamped. Refusing is a
        /// safety requirement; whether such an edge also cannot host a summon
        /// is INFERRED (see `bottomEdgeIsFree`). Since #83 a display reaches
        /// this list only when nothing of its edge is free — a partial overlap
        /// is guarded over its free spans instead.
        case nothingToGuard(blockedDisplayIDs: [CGDirectDisplayID])
        /// Every other display mirrors the preferred one — same pixels, so a
        /// band drawn on the "other" display lands on the one the user is
        /// looking at. Nothing to guard, and guarding would be actively wrong.
        case mirrorsPreferredDisplay
    }

    public enum Decision: Sendable, Equatable {
        case idle(IdleReason)
        /// Hold these bands. `zones` is never empty.
        ///
        /// `skipped` names displays that were deliberately **not** guarded at
        /// all — a bottom edge blocked along its whole length, or a mirror of
        /// the preferred display.
        ///
        /// `partiallyGuarded` names displays covered over some of their bottom
        /// edge but not all of it: the free spans are held, the shared spans
        /// are left open because they are the route between screens. It is a
        /// third list rather than more entries in `skipped` because the two
        /// say different things to a user — "the Dock can still be summoned
        /// there" versus "the Dock can still be summoned there, in the strip
        /// above your other screen" — and one list would force the report to
        /// pick one of those and be wrong about the other.
        ///
        /// Both are carried so the UI can say "active, and here is what it
        /// does not cover" instead of an unqualified "active". A display
        /// appears in exactly one of `zones`' display IDs, `skipped`, or
        /// `partiallyGuarded`, and `partiallyGuarded` is always a subset of
        /// the displays `zones` names.
        case guarding(
            zones: [ClampZone],
            skipped: [CGDirectDisplayID],
            partiallyGuarded: [CGDirectDisplayID]
        )
    }

    // MARK: - Decision

    /// The whole rule, in the order the conditions must be checked.
    ///
    /// Order is load-bearing in one place: the safety geometry is evaluated
    /// **last**, after every cheap disqualifier, so a refusal reported to the
    /// user is always about the arrangement rather than about a setting they
    /// have already turned off.
    public static func decide(_ snapshot: Snapshot) -> Decision {
        guard snapshot.appEnabled else { return .idle(.appDisabled) }
        guard snapshot.featureEnabled else { return .idle(.featureDisabled) }
        guard snapshot.dockEdge == .bottom else { return .idle(.edgeNotBottom) }
        guard snapshot.separateSpacesEnabled else { return .idle(.separateSpacesOff) }
        guard snapshot.displays.count > 1 else { return .idle(.singleDisplay) }

        guard let preferredID = snapshot.preferredDisplayID else {
            return .idle(.noPreferredDisplay)
        }
        guard snapshot.displays.contains(where: { $0.displayID == preferredID }) else {
            return .idle(.preferredDisplayNotConnected)
        }
        guard snapshot.accessibilityTrusted else { return .idle(.accessibilityNotGranted) }

        guard let preferredFrame = snapshot.displays
            .first(where: { $0.displayID == preferredID })?.frame
        else { return .idle(.preferredDisplayNotConnected) }

        let frames = snapshot.displays.map(\.frame)
        var zones: [ClampZone] = []
        var blocked: [CGDirectDisplayID] = []
        var partial: [CGDirectDisplayID] = []
        var mirrored: [CGDirectDisplayID] = []

        for (index, display) in snapshot.displays.enumerated() {
            guard display.displayID != preferredID else { continue }

            // A mirror of the preferred display shares its pixels, so a band on
            // "the other display" is drawn on the screen the user is actually
            // looking at — the Dock becomes unsummonable on the only visible
            // surface. Mirror-set members have distinct display IDs and
            // identical bounds, so the ID check above does not catch them.
            //
            // Tested by intersection rather than by CGDisplayMirrorsDisplay on
            // purpose: it keeps this decision pure and hardware-free, and it
            // also covers a transiently overlapping bounds report during
            // reconfiguration, which a mirror-specific query would not.
            // `CGRect.intersects` is false for edge-adjacent rects, so no real
            // side-by-side or stacked arrangement is disturbed.
            guard !display.frame.intersects(preferredFrame) else {
                mirrored.append(display.displayID)
                continue
            }

            // One zone per free span, not one per display (#83). A display
            // overhanging another is guarded over the overhangs and left open
            // over the shared strip, so the pointer's route between the two
            // screens survives while the spans that can host a summon do not.
            let spans = freeBottomSpans(index, among: frames)
            guard !spans.isEmpty else {
                blocked.append(display.displayID)
                continue
            }
            for span in spans {
                zones.append(ClampZone(displayID: display.displayID, frame: span))
            }
            // Whole-display truth, asked of the predicate that has no interval
            // arithmetic in it, so the report cannot inherit a bug from the
            // spans. Anything short of a wholly free edge is reported as
            // partial rather than as full coverage.
            if !bottomEdgeIsFree(index, among: frames) {
                partial.append(display.displayID)
            }
        }

        guard !zones.isEmpty else {
            // Mirror-only is its own reason: telling the user "a display sits
            // directly below another" when their screens are mirrored is a false
            // statement about their desk.
            if blocked.isEmpty && !mirrored.isEmpty { return .idle(.mirrorsPreferredDisplay) }
            return .idle(.nothingToGuard(blockedDisplayIDs: blocked))
        }
        return .guarding(
            zones: zones, skipped: blocked + mirrored, partiallyGuarded: partial
        )
    }

    /// Applies the zones to a pointer location, or returns `nil` when the
    /// location is already allowed. Pure, so the tap callback holds no policy.
    ///
    /// The first containing zone wins, and no two can ever contain the same
    /// point: zones on different displays cannot overlap because displays
    /// cannot, `ClampZone.contains` is half-open horizontally so neighbours
    /// never both claim the seam column, and the several zones a single display
    /// contributes are the gaps between its blockers — disjoint by construction
    /// and separated by at least one blocker each (#83).
    public static func clamp(_ point: CGPoint, zones: [ClampZone]) -> CGPoint? {
        for zone in zones where zone.contains(point) {
            return zone.clamping(point)
        }
        return nil
    }
}

extension BottomDockGuard.IdleReason {

    /// One line for `--diagnostics`. Support reads this to answer "I turned it
    /// on and nothing happens", so each case names the specific unmet condition.
    public var explanation: String {
        switch self {
        case .appDisabled:
            return "off — DockKeeper is disabled"
        case .featureDisabled:
            return "off — not enabled in Preferences"
        case .edgeNotBottom:
            return "idle — only a bottom Dock is pointer-summoned"
        case .separateSpacesOff:
            return "idle — needs \u{201C}Displays have separate Spaces\u{201D} on"
        case .singleDisplay:
            return "idle — needs a second display"
        case .noPreferredDisplay:
            return "idle — no preferred display chosen"
        case .preferredDisplayNotConnected:
            return "idle — preferred display isn't connected"
        case .accessibilityNotGranted:
            return "idle — waiting for Accessibility permission"
        case .nothingToGuard(let blocked):
            return "idle — no guardable display "
                + "(\(blocked.count) whose bottom edge is blocked along its whole length; "
                + "clamping the shared span would trap the pointer)"
        case .mirrorsPreferredDisplay:
            return "idle — the other display mirrors the preferred one"
        }
    }
}
