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
    /// - **Necessity.** A blocked bottom edge cannot host a summon either: the
    ///   pointer crosses into the display beneath instead of dwelling, so the
    ///   Dock cannot be called there. Confirmed 2026-07-23 on the stacked
    ///   portrait rig — not even a real hand could summon there.
    ///
    /// Together they mean a blocked display is both unguardable and not in need
    /// of guarding, so `decide` simply emits no zone for it.
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

    // MARK: - Inputs

    /// Everything the decision reads, captured as a value so it is pure.
    public struct Snapshot: Sendable, Equatable {
        public let displays: [DisplayInfo]
        /// The display the Dock should stay on. `nil` when the user has not
        /// chosen one — the guard has no target and stays idle.
        public let preferredDisplayID: CGDirectDisplayID?
        public let dockEdge: DockOrientation
        public let separateSpacesEnabled: Bool
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
            featureEnabled: Bool,
            accessibilityTrusted: Bool
        ) {
            self.displays = displays
            self.preferredDisplayID = preferredDisplayID
            self.dockEdge = dockEdge
            self.separateSpacesEnabled = separateSpacesEnabled
            self.featureEnabled = featureEnabled
            self.accessibilityTrusted = accessibilityTrusted
        }
    }

    // MARK: - Outputs

    /// A band along one display's bottom edge that the pointer is held out of.
    public struct ClampZone: Sendable, Equatable {
        public let displayID: CGDirectDisplayID
        /// The guarded display's frame, CG top-left.
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
        public func contains(_ point: CGPoint) -> Bool {
            point.x >= frame.minX && point.x < frame.maxX && point.y > clampY
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
        /// Every non-preferred display has a blocked bottom edge, so none can
        /// host a summon and none may be clamped. Refusing here is correct on
        /// both counts, not a limitation.
        case nothingToGuard(blockedDisplayIDs: [CGDirectDisplayID])
    }

    public enum Decision: Sendable, Equatable {
        case idle(IdleReason)
        /// Hold these bands. Never empty.
        case guarding([ClampZone])
    }

    // MARK: - Decision

    /// The whole rule, in the order the conditions must be checked.
    ///
    /// Order is load-bearing in one place: the safety geometry is evaluated
    /// **last**, after every cheap disqualifier, so a refusal reported to the
    /// user is always about the arrangement rather than about a setting they
    /// have already turned off.
    public static func decide(_ snapshot: Snapshot) -> Decision {
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

        let frames = snapshot.displays.map(\.frame)
        var zones: [ClampZone] = []
        var blocked: [CGDirectDisplayID] = []

        for (index, display) in snapshot.displays.enumerated() {
            guard display.displayID != preferredID else { continue }
            if bottomEdgeIsFree(index, among: frames) {
                zones.append(ClampZone(displayID: display.displayID, frame: display.frame))
            } else {
                blocked.append(display.displayID)
            }
        }

        guard !zones.isEmpty else { return .idle(.nothingToGuard(blockedDisplayIDs: blocked)) }
        return .guarding(zones)
    }

    /// Applies the zones to a pointer location, or returns `nil` when the
    /// location is already allowed. Pure, so the tap callback holds no policy.
    ///
    /// The first containing zone wins; zones cannot overlap, because displays
    /// cannot, and `ClampZone.contains` is half-open horizontally.
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
        case .featureDisabled:
            return "off"
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
                + "(\(blocked.count) with a blocked bottom edge; clamping one would trap the pointer)"
        }
    }
}
