import CoreGraphics
import Foundation
import Testing

@testable import DockKeeperCore

// App text that must not contradict the bottom-Dock guard -------------------
//
// #79: the menu said a bottom Dock can't be kept on a display in separate-Spaces
// mode while the guard was doing exactly that, and never named the guard.
// #99: Preferences said the bottom hot corners stop working while the guard is
// on; on device (§3d row 7) they still fire.

private let guarding = BottomDockGuard.Decision.guarding(
    zones: [BottomDockGuard.ClampZone(displayID: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))],
    skipped: [],
    partiallyGuarded: []
)
private let guardingPartly = BottomDockGuard.Decision.guarding(
    zones: [BottomDockGuard.ClampZone(displayID: 2, frame: CGRect(x: 0, y: -1440, width: 800, height: 1440))],
    skipped: [],
    partiallyGuarded: [2]
)
private let everyDecision: [BottomDockGuard.Decision] = [
    guarding, guardingPartly,
    .idle(.appDisabled), .idle(.featureDisabled), .idle(.edgeNotBottom),
    .idle(.separateSpacesOff), .idle(.singleDisplay), .idle(.noPreferredDisplay),
    .idle(.preferredDisplayNotConnected), .idle(.accessibilityNotGranted),
    .idle(.nothingToGuard(blockedDisplayIDs: [2])), .idle(.mirrorsPreferredDisplay),
]
private let guardOffer = "Keep a bottom Dock on my preferred display"

@Suite("Separate-Spaces menu copy follows the guard (#79)")
struct SeparateSpacesMenuCopyTests {

    @Test("With the guard off, the message names it as a remedy and keeps the old two")
    func guardOffNamesTheGuard() {
        let lines = PinOutcome.unsupportedSeparateSpaces.userMessageLines(guardDecision: .idle(.featureDisabled))
        #expect(lines.contains { $0.contains(guardOffer) && $0.contains("Preferences \u{203A} Advanced") })
        #expect(lines.contains { $0.contains("Left or Right") })
        #expect(lines.contains { $0.contains("System Settings") })
        // ADR-015: prevent, never relocate. The offer must say it can't move
        // a Dock back.
        #expect(lines.contains { $0.contains("can\u{2019}t move it back") })
    }

    @Test("While the decision is guarding, the message makes no active-protection claim")
    func guardingIsDecisionOnly() {
        // `.guarding` is the plan, not proof the tap is filtering, and a healthy
        // guard still never sees where the Dock is. Exact string, so a claim
        // appended or reworded into it fails here (coordinator review of #104).
        let message = PinOutcome.unsupportedSeparateSpaces.userMessage(guardDecision: guarding)
        #expect(message == "macOS can\u{2019}t pin a bottom Dock while \u{201C}Displays have separate Spaces\u{201D} is on.\n"
            + "\u{201C}Keep a bottom Dock on my preferred display\u{201D} is on \u{2014} its live status is in Preferences \u{203A} Advanced.\n"
            + "When active, it blocks new summons on guarded edges; it can\u{2019}t move the Dock back.\n"
            + "Other options: a Left or Right edge, or turn that setting off.")
    }

    @Test("While guarding only part of an edge, the message says the Dock can still be summoned there")
    func partialGuardSaysSo() {
        let lines = PinOutcome.unsupportedSeparateSpaces.userMessageLines(guardDecision: guardingPartly)
        #expect(lines.contains("Some bottom edges are left open, so the Dock can still be summoned there."))
        #expect(!lines.contains { $0.contains("turn on") })
    }

    @Test("With the guard on but idle, the message does not offer to turn it on")
    func onButIdleDoesNotOfferIt() {
        for reason: BottomDockGuard.IdleReason in [.accessibilityNotGranted, .noPreferredDisplay,
                                                   .nothingToGuard(blockedDisplayIDs: [2])] {
            let lines = PinOutcome.unsupportedSeparateSpaces.userMessageLines(guardDecision: .idle(reason))
            #expect(!lines.contains { $0.contains("turn on") }, "\(reason): \(lines)")
            #expect(lines.contains { $0.contains("is on but inactive") }, "\(reason): \(lines)")
        }
    }

    @Test("With DockKeeper itself off, no stale advisory and no offer of the feature toggle")
    func appDisabledSuppressesTheAdvisory() {
        // The master switch is checked before the feature toggle, so this
        // decision says nothing about that toggle — it may be on already.
        #expect(PinOutcome.unsupportedSeparateSpaces.userMessage(guardDecision: .idle(.appDisabled)) == nil)
        #expect(PinOutcome.unsupportedSeparateSpaces.userMessageLines(guardDecision: .idle(.appDisabled)).isEmpty)
    }

    @Test("No variant claims the Dock is pinned or being kept, every line fits the #57 bound, and the old remedies survive")
    func everyVariantStaysHonest() {
        for decision in everyDecision where decision != .idle(.appDisabled) {
            let lines = PinOutcome.unsupportedSeparateSpaces.userMessageLines(guardDecision: decision)
            #expect(lines.count > 1)
            #expect(lines.contains { $0.contains("Left or Right") }, "\(decision): \(lines)")
            for line in lines {
                // A character bound, not a rendering check: real-menu fit is
                // verified by eye on the packaged build, not here.
                #expect(line.count <= 110, "too long to render: \(line)")
                for claim in ["is pinned", "keeping it", "is keeping", "is blocking", "is holding"] {
                    #expect(!line.contains(claim), "ADR-015 / no active claim: \(line)")
                }
            }
        }
    }

    @Test("Every other outcome is unaffected by the guard")
    func otherOutcomesPassThrough() {
        let others: [PinOutcome] = [.pinned, .alreadyOnTarget, .singleDisplay, .displayNotConnected,
                                    .ambiguousIdentity, .bottomDockFollowsPointer, .noPreference, .failed(1000)]
        for outcome in others {
            for decision in everyDecision {
                #expect(outcome.userMessage(guardDecision: decision) == outcome.userMessage)
            }
        }
    }
}

@Suite("Preferences description of the guard (#99)")
struct GuardToggleDescriptionTests {

    @Test("Does not claim the bottom hot corners stop working")
    func noHotCornerClaim() {
        #expect(!BottomDockGuard.toggleDescription.localizedCaseInsensitiveContains("hot corner"))
    }

    @Test("Keeps the confirmed mechanism, the no-relocation limit and the open strip")
    func keepsWhatIsTrue() {
        let text = BottomDockGuard.toggleDescription
        #expect(text.contains("holds the pointer a few points clear of the bottom edge"))
        #expect(text.contains("it does not move the Dock back"))
        #expect(text.contains("the overlapping strip is left unguarded"))
    }
}
