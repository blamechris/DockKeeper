import CoreGraphics
import Foundation

// MARK: - What the user is told about the guard

/// The three user-facing renderings of a `BottomDockGuard.Decision`, as pure
/// functions of the decision itself.
///
/// They live in Core rather than beside their call sites because the app target
/// has no test coverage and cannot be given any (TDD rule 8) — and these
/// particular strings are *claims about the user's desk*. Since #83 each of them
/// counts **distinct displays** rather than zones, because one display
/// contributes one zone per free span; each also branches on a
/// `partiallyGuarded` list that says something materially different from
/// `skipped`. Both are edits no existing test could see while the construction
/// sat in `AppState` and `Diagnostics` (#84).
///
/// This repo treats a false user-facing claim as a defect of the same severity
/// as a code bug (#72), so the half of the feature that makes such claims is the
/// half that most needs to be reachable from a test.
///
/// **What moved is every string computed from a decision** — the ones carrying
/// counts, which are the ones that can miscount. The app target performs no
/// arithmetic over a decision and holds no wording derived from one.
///
/// **Fixed text does remain in the app target, and it is still uncovered.** Three
/// consecutive review rounds corrected this paragraph — "no wording remains",
/// then "four lines in `BottomDockGuardTap`", then a two-file list that omitted
/// `Diagnostics` — so it no longer tries to be a list. Re-derive it instead:
///
///     grep -rlE "bottomDockGuard|lockBottomDock|Bottom guard" Sources/DockKeeper
///
/// At the time of writing that returns four files. `AppState` is binding only.
/// The other three hold fixed strings: `BottomDockGuardTap`'s lifecycle log lines
/// and its main-thread `precondition` message (#87); `Diagnostics`' `Bottom guard:`
/// row label, which is the label on the very line whose *value* moved here; and
/// `PreferencesView`'s toggle label, Accessibility button and help paragraph —
/// whose closing sentence is a conditional claim about the user's arrangement,
/// rewritten by #83 in the same commit as the caption below it (#89).
///
/// None of it counts anything, so none of it can miscount. It can go stale.
///
/// So: uncovered wording does remain in the app target. What no longer lives
/// there is anything that counts.
extension BottomDockGuard {

    /// The live status caption under the bottom-Dock toggle. Says what the
    /// guard is doing *right now* — the toggle can be on while every
    /// precondition is unmet, and silence there is what makes a feature feel
    /// broken (the same reasoning as ADR-010's "waiting for permission").
    public static func caption(for decision: Decision) -> String {
        switch decision {
        case .guarding(let zones, let skipped, let partial):
            // Distinct displays, not `zones.count`: an overhanging display
            // contributes one zone per free span (#83), and "holding the bottom
            // edge on 2 other displays" when there is one would be a false
            // statement about the user's desk.
            let guarded = Set(zones.map(\.displayID)).count
            var caption = "Active — holding the bottom edge on \(guarded) other display(s)."
            if !partial.isEmpty {
                // Plural for the same reason the `skipped` sentence below is:
                // a bottom edge can sit above two screens at two separate
                // stretches, so neither "the stretch" nor "another screen" is
                // a claim the sweep makes. Fixing one and leaving its twin was
                // itself a review finding (#83 delta review).
                caption += " \(partial.count) of them only partly: the stretches that sit directly "
                    + "above your other screens are left open, because that is the route your "
                    + "pointer takes between them, and the Dock can still be summoned there."
            }
            if !skipped.isEmpty {
                // Not "another display" — the sweep blocks on the UNION of every
                // neighbour flush beneath, so an edge can be covered by two
                // screens together with neither covering it alone. The singular
                // was a claim the computation never made (#83 review).
                caption += " \(skipped.count) display(s) are not covered at all, because other "
                    + "screens sit beneath their whole bottom edge, or they mirror your preferred "
                    + "display — the Dock can still be summoned there."
            }
            return caption
        case .idle(.featureDisabled):
            return ""
        case .idle(.appDisabled):
            // Not blank, unlike `featureDisabled`. `.appDisabled` is returned
            // whatever the feature toggle reads, because the master switch is
            // disqualified first (TDD §10a) — so this caption names the switch
            // the user actually turned off, rather than leaving a blank space
            // under a toggle that looks like it should be doing something.
            return "Inactive while DockKeeper is turned off."
        case .idle(.accessibilityNotGranted):
            return "Waiting for Accessibility permission — grant it in System Settings \u{203A} "
                + "Privacy & Security \u{203A} Accessibility."
        case .idle(.nothingToGuard):
            return "Not available on this arrangement: every bottom edge DockKeeper could hold "
                + "is covered along its whole length by the screens below it, so that edge is "
                + "the route your pointer takes between them. Holding it would trap your cursor."
        case .idle(.mirrorsPreferredDisplay):
            return "Not available while your displays are mirrored — they show the same pixels, "
                + "so there is no second bottom edge to hold."
        case .idle(let reason):
            return "Inactive — \(reason.explanation.replacingOccurrences(of: "idle — ", with: ""))."
        }
    }

    /// DK-FR-014's state, in one line, for `--diagnostics`. Reports the *reason*
    /// when idle, because "I enabled it and nothing happens" is the support
    /// question this feature will generate — every precondition it needs is
    /// invisible to the user.
    ///
    /// `paused` qualifies rather than suppresses: pause suspends *corrections*,
    /// and the guard is prevention with nothing to resume (DK-FR-014 Known cost,
    /// #62). It is a parameter rather than read here so this stays pure.
    public static func diagnosticsLine(for decision: Decision, paused: Bool) -> String {
        switch decision {
        case .idle(let reason):
            return reason.explanation
        case .guarding(let zones, let skipped, let partial):
            // Distinct displays, never `zones.count`: since #83 one display
            // contributes one zone per free span, so counting zones would
            // report two displays guarded where a single overhanging display
            // is guarded twice over. Spans are named alongside so the figure
            // is not silently a different unit than the one v0.9.3 printed.
            let guarded = Set(zones.map(\.displayID)).count
            var base = "guarding \(guarded) display(s) over \(zones.count) span(s)"
            if !partial.isEmpty {
                // Partial is not "not covered", and conflating the two is how a
                // report overstates coverage in one direction or understates it
                // in the other. Say which, and say what is left open.
                base += "; \(partial.count) partly covered "
                    + "(the strips above other displays stay open — they are the route between them)"
            }
            if !skipped.isEmpty {
                // Naming the uncovered displays matters: a display whose bottom
                // edge is blocked along its whole length is not guarded at all,
                // so an unqualified "guarding" would overstate the coverage to
                // whoever reads this.
                base += "; \(skipped.count) not covered (blocked edge or mirrored)"
            }
            // `Paused:` sits directly below this one, and both are new in this
            // release, so this is the first build whose report can pair a
            // guarding decision with an active pause. Read cold that looks self-contradictory.
            // It is not: pause suspends *corrections*, and the guard is prevention
            // with nothing to resume (DK-FR-014 Known cost, #62). Qualify rather
            // than suppress — the same rule #69 applied to `status`.
            if paused {
                base += "; unaffected by the pause below (this feature is not released by pausing)"
            }
            return base
        }
    }

    /// The line logged when the tap arms. Per #77/#78 this is the *only* honest
    /// evidence that the tap armed — `--diagnostics` re-derives in a fresh
    /// process and cannot observe a live tap — so it must not overstate what
    /// armed.
    ///
    /// Takes zones rather than a `Decision` because that is what the tap holds
    /// at the moment it arms, and because the count it must not get wrong is a
    /// property of the zones: spans and distinct displays are different numbers
    /// whenever a display overhangs another (#83).
    public static func armedLogLine(zones: [ClampZone]) -> String {
        let spanCount = zones.count
        let displayCount = Set(zones.map(\.displayID)).count
        return "Bottom-Dock guard: armed over \(spanCount) span(s) on \(displayCount) display(s)"
    }
}
