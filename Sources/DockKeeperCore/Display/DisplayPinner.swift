import Foundation
import CoreGraphics

/// A point-in-time view of the display environment, used to decide whether and
/// how to pin the Dock to a preferred display. Captured as a value so the
/// decision logic is pure and unit-testable without real hardware.
public struct DisplaySnapshot: Sendable, Equatable {
    public let displays: [DisplayInfo]
    public let mainDisplayID: CGDirectDisplayID
    public let separateSpacesEnabled: Bool

    public init(displays: [DisplayInfo], mainDisplayID: CGDirectDisplayID, separateSpacesEnabled: Bool) {
        self.displays = displays
        self.mainDisplayID = mainDisplayID
        self.separateSpacesEnabled = separateSpacesEnabled
    }

    /// The displays offered to fingerprint matching (ADR-004).
    public var identityCandidates: [FingerprintMatcher.Candidate] {
        displays.compactMap { display in
            display.fingerprint.map {
                FingerprintMatcher.Candidate(displayID: display.displayID, fingerprint: $0)
            }
        }
    }
}

/// The result of a pin attempt. All non-`pinned` cases are safe no-ops.
public enum PinOutcome: Sendable, Equatable {
    case pinned                     // Reconfigured; target is now the main display.
    case alreadyOnTarget            // Target was already the main display.
    case singleDisplay              // Only one display; nothing to pin.
    case displayNotConnected        // Preferred display isn't currently attached.
    case ambiguousIdentity          // Two candidates are indistinguishable — never guess (TDD §7.2).
    case unsupportedSeparateSpaces  // "Displays have separate Spaces" is on (Decision 2A).
    case noPreference               // No preferred display configured.
    case failed(Int32)              // CoreGraphics reconfigure error (CGError raw value).

    /// Short, user-facing explanation for the menu / preferences.
    public var userMessage: String? {
        switch self {
        case .pinned, .alreadyOnTarget, .noPreference:
            return nil  // Nothing to explain; it worked or isn't set.
        case .singleDisplay:
            return "Only one display is connected."
        case .displayNotConnected:
            return "Your preferred display isn't connected."
        case .ambiguousIdentity:
            return "Two connected displays look identical, so DockKeeper won't "
                + "guess. Please pick your preferred display again."
        case .unsupportedSeparateSpaces:
            return "Pinning needs \u{201C}Displays have separate Spaces\u{201D} turned off "
                + "(System Settings \u{203A} Desktop & Dock). Edge locking still works."
        case .failed:
            return "Couldn't move the Dock to your preferred display."
        }
    }
}

/// Abstraction over "keep the Dock on the user's preferred monitor". v1.0 has a
/// single public-API implementation; the protocol leaves room for an
/// experimental private-API strategy later without touching call sites.
/// Main-actor because live snapshots read `NSScreen`.
@MainActor
public protocol DisplayPinner {
    /// Attempt to pin to a concrete, already-resolved display.
    func pin(toDisplayID targetID: CGDirectDisplayID) -> PinOutcome
}

/// Pins the Dock by making the preferred display the **main** display (moving
/// its origin to `(0,0)` and shifting the others to preserve the arrangement).
///
/// Per Decision 1 this also relocates the menu bar — an accepted, documented
/// consequence. Per Decision 2A, when "Displays have separate Spaces" is on we
/// decline rather than fight the OS. Identity resolution (fingerprint →
/// display) happens *before* the pinner via `DisplayIdentityResolver`.
@MainActor
public struct MainDisplayPinner: DisplayPinner {

    /// What `decide` concludes: either a terminal outcome, or "go make this
    /// display the main one".
    enum Decision: Equatable {
        case terminal(PinOutcome)
        case reconfigure(CGDirectDisplayID)
    }

    private let snapshotProvider: @MainActor () -> DisplaySnapshot
    private let applyMain: @MainActor (_ targetID: CGDirectDisplayID, _ displays: [DisplayInfo]) -> Int32

    /// Default initializer wires up real CoreGraphics. Tests inject fakes.
    public init(
        snapshotProvider: @escaping @MainActor () -> DisplaySnapshot = MainDisplayPinner.liveSnapshot,
        applyMain: @escaping @MainActor (_ targetID: CGDirectDisplayID, _ displays: [DisplayInfo]) -> Int32 = MainDisplayPinner.liveApplyMain
    ) {
        self.snapshotProvider = snapshotProvider
        self.applyMain = applyMain
    }

    public func pin(toDisplayID targetID: CGDirectDisplayID) -> PinOutcome {
        let snapshot = snapshotProvider()
        guard snapshot.displays.contains(where: { $0.displayID == targetID }) else {
            // The display vanished between resolution and application.
            return .displayNotConnected
        }
        switch Self.decide(snapshot: snapshot, resolution: .resolved(targetID, repaired: nil)) {
        case .terminal(let outcome):
            Log.display.debug("Pin decision: \(String(describing: outcome), privacy: .public)")
            return outcome
        case .reconfigure(let targetID):
            let code = applyMain(targetID, snapshot.displays)
            if code == 0 {
                Log.display.info("Pinned Dock by making display \(targetID) main")
                return .pinned
            }
            Log.display.error("Display reconfigure failed with CGError \(code)")
            return .failed(code)
        }
    }

    // MARK: - Pure decision logic (unit-tested)

    /// Placement decision for an already-resolved preference. Outcome
    /// precedence: no preference → single display → identity outcomes →
    /// separate Spaces → already-on-target.
    nonisolated static func decide(
        snapshot: DisplaySnapshot,
        resolution: PreferredDisplayResolution
    ) -> Decision {
        if case .none = resolution { return .terminal(.noPreference) }
        guard snapshot.displays.count > 1 else { return .terminal(.singleDisplay) }
        switch resolution {
        case .none:
            return .terminal(.noPreference)  // unreachable; kept exhaustive
        case .notConnected:
            return .terminal(.displayNotConnected)
        case .ambiguous:
            return .terminal(.ambiguousIdentity)
        case .resolved(let targetID, _):
            if snapshot.separateSpacesEnabled {
                return .terminal(.unsupportedSeparateSpaces)
            }
            if targetID == snapshot.mainDisplayID {
                return .terminal(.alreadyOnTarget)
            }
            return .reconfigure(targetID)
        }
    }

    // MARK: - Live implementations

    public static let liveSnapshot: @MainActor () -> DisplaySnapshot = {
        DisplaySnapshot(
            displays: DisplayManager.activeDisplays(),
            mainDisplayID: CGMainDisplayID(),
            separateSpacesEnabled: readSeparateSpacesEnabled()
        )
    }

    /// Reconfigure display origins so `targetID` sits at `(0,0)` — making it the
    /// main display — while preserving every display's relative position.
    /// Returns `0` on success or the failing `CGError` raw value.
    public static let liveApplyMain: @Sendable (CGDirectDisplayID, [DisplayInfo]) -> Int32 = { targetID, displays in
        guard let target = displays.first(where: { $0.displayID == targetID }) else {
            return CGError.illegalArgument.rawValue
        }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { return begin.rawValue }

        let dx = target.frame.origin.x
        let dy = target.frame.origin.y
        for display in displays {
            let newX = Int32(display.frame.origin.x - dx)
            let newY = Int32(display.frame.origin.y - dy)
            let err = CGConfigureDisplayOrigin(config, display.displayID, newX, newY)
            if err != .success {
                CGCancelDisplayConfiguration(config)
                return err.rawValue
            }
        }
        return CGCompleteDisplayConfiguration(config, .permanently).rawValue
    }

    /// Reads the "Displays have separate Spaces" setting.
    /// `com.apple.spaces spans-displays` == 1 means displays span one Space
    /// (separate Spaces OFF); absent or 0 means separate Spaces ON (the macOS
    /// default).
    public nonisolated static func readSeparateSpacesEnabled() -> Bool {
        guard
            let spaces = UserDefaults(suiteName: "com.apple.spaces"),
            spaces.object(forKey: "spans-displays") != nil
        else { return true }
        return spaces.integer(forKey: "spans-displays") != 1
    }
}
