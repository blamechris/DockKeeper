import ApplicationServices
import Foundation
import AppKit
import ServiceManagement
import DockKeeperCore

/// Prints a one-shot diagnostics report and exits. Handy for support ("run
/// `DockKeeper --diagnostics` and paste the output") and for verifying the
/// bundle wiring — Launch-at-Login status is only meaningful from inside the
/// signed `.app`.
enum Diagnostics {

    @MainActor
    static func runIfRequested() {
        // The same set the single-instance guard refuses to pre-empt (DK-FR-012),
        // shared rather than re-spelled so the two cannot drift apart.
        guard CommandLine.arguments.contains(where: InstanceGuard.oneShotFlags.contains) else { return }
        print(report())
        exit(EXIT_SUCCESS)
    }

    @MainActor
    static func report() -> String {
        let bundle = Bundle.main
        let loginStatus: String
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "enabled"
        case .notRegistered: loginStatus = "notRegistered (registerable)"
        case .requiresApproval: loginStatus = "requiresApproval"
        case .notFound: loginStatus = "notFound (not a valid bundle)"
        @unknown default: loginStatus = "unknown"
        }

        let separateSpaces = MainDisplayPinner.readSeparateSpacesEnabled()
        // ADR-009: with the setting ON macOS treats edges asymmetrically — a
        // bottom Dock is pointer-summoned and cannot be pinned, a left/right
        // Dock homes to the main display and pins normally. Report the verdict
        // for *this* machine's lock edge rather than a blanket claim (#45).
        let lockEdge = Settings.shared.lockEdge
        let pinningVerdict: String
        if separateSpaces {
            pinningVerdict = lockEdge == .bottom
                ? "on \u{2014} bottom Dock does not pin (left/right would; ADR-009)"
                : "on \u{2014} \(lockEdge.displayName.lowercased()) Dock pins (ADR-009)"
        } else {
            pinningVerdict = "off \u{2014} any edge pins"
        }

        return """
        DockKeeper diagnostics
        ----------------------
        Version:         \(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        Bundle ID:       \(bundle.bundleIdentifier ?? "(none — running unbundled)")
        Bundle path:     \(bundle.bundlePath)
        Other instances: \(otherInstances())
        LSUIElement:     \(bundle.infoDictionary?["LSUIElement"] as? Bool ?? false)
        Launch at Login: \(loginStatus)
        CoreDock API:    \(CoreDock.isAvailable ? "available" : "unavailable")
        Dock edge:       \(DockController().currentOrientation()?.displayName ?? "unknown")
        Displays:        \(DisplayManager.activeDisplays().count)
        Separate Spaces: \(pinningVerdict)
        Bottom guard:    \(bottomDockGuardStatus())
        Paused:          \(pauseStatus())
        Screen-share:    \(screenShareHideStatus())
        """
    }

    /// DK-FR-014's state, in one line. Reports the *reason* when idle, because
    /// "I enabled it and nothing happens" is the support question this feature
    /// will generate — every precondition it needs is invisible to the user.
    ///
    /// Read from a fresh process, so it reports what the *decision* would be
    /// here rather than what a running instance currently holds; the tap itself
    /// lives in the running app. That is enough to answer every precondition
    /// question, which is what support needs.
    @MainActor
    private static func bottomDockGuardStatus() -> String {
        let settings = Settings()
        let displays = DisplayManager.activeDisplays()
        let stored = settings.preferredDisplayFingerprint
        let candidates = displays.compactMap { display in
            display.fingerprint.map {
                FingerprintMatcher.Candidate(displayID: display.displayID, fingerprint: $0)
            }
        }
        var preferredID: CGDirectDisplayID?
        if case .resolved(let displayID, _) = DisplayIdentityResolver.resolve(
            stored: stored, candidates: candidates
        ) {
            preferredID = displayID
        }

        let decision = BottomDockGuard.decide(
            BottomDockGuard.Snapshot(
                displays: displays,
                preferredDisplayID: preferredID,
                dockEdge: settings.lockEdge,
                separateSpacesEnabled: MainDisplayPinner.readSeparateSpacesEnabled(),
                appEnabled: settings.isEnabled,
                featureEnabled: settings.lockBottomDockToDisplay,
                accessibilityTrusted: AXIsProcessTrusted()
            )
        )
        switch decision {
        case .idle(let reason):
            return reason.explanation
        case .guarding(let zones, let skipped):
            var base = "guarding \(zones.count) display(s)"
            if !skipped.isEmpty {
                // Naming the uncovered displays matters: a whole-display refusal
                // leaves spans that really can host a summon, so an unqualified
                // "guarding" would overstate the coverage to whoever reads this.
                base += " (\(skipped.count) not covered — blocked edge or mirrored)"
            }
            // `Paused:` sits directly below this one, and both are new in this
            // release, so this is the first build whose report can pair a
            // guarding decision with an active pause. Read cold that looks self-contradictory.
            // It is not: pause suspends *corrections*, and the guard is prevention
            // with nothing to resume (DK-FR-014 Known cost, #62). Qualify rather
            // than suppress — the same rule #69 applied to `status`.
            if settings.pauseRecord != nil {
                base += "; unaffected by the pause below (this feature is not released by pausing)"
            }
            return base
        }
    }

    /// Whether corrections are suspended (DK-FR-009) — the support answer to
    /// "DockKeeper says enabled but does nothing" (#36). `Enabled:` cannot carry
    /// this: a paused instance is enabled and correctly idle, so a report from
    /// one is otherwise indistinguishable from a working install.
    ///
    /// Ages are **relative**, never wall-clock — DK-PRIV-001 S2, matching
    /// `Screen-share:` above. The age is also what exposes the one stale case:
    /// ADR-014 makes a restart an implicit resume, so a record older than the
    /// running instance means DockKeeper died while paused and this report is
    /// from a cold process. Cross-check `Other instances:` when it looks odd.
    private static func pauseStatus() -> String {
        guard let record = Settings.shared.pauseRecord else { return "no" }
        // One clock read for both quantities, so the age and the remaining time
        // cannot disagree about when "now" was.
        let now = Date()
        guard let age = DisplayDuration.wholeSeconds(now.timeIntervalSince(record.pausedAt)) else {
            return "yes (timestamp unreadable — record may be corrupt)"
        }
        guard let until = record.pausedUntil else {
            return "yes (\(age)s ago; until resumed — no timer)"
        }
        guard let remaining = DisplayDuration.wholeSeconds(until.timeIntervalSince(now)) else {
            return "yes (\(age)s ago; deadline unreadable — record may be corrupt)"
        }
        // Negating is safe: `wholeSeconds` bounds the magnitude well inside
        // `Int`, so `-remaining` cannot overflow the way `-Int.min` would.
        return remaining > 0
            ? "yes (\(age)s ago; auto-resumes in \(remaining)s)"
            : "yes (\(age)s ago; auto-resume overdue by \(-remaining)s)"
    }

    /// Whether a screen-capture hide record is outstanding — the support answer
    /// to "why is my Dock auto-hiding?" (DK-FR-013). Strictly read-only, and a
    /// relative age rather than a wall-clock stamp, matching the state-only
    /// content rule the rest of the report follows.
    private static func screenShareHideStatus() -> String {
        guard let record = Settings.shared.screenShareHideRecord else { return "no record held" }
        let window = Int(ScreenShareHider.repairWindow)
        // Same trap as `pauseStatus()`, and pre-existing here since ADR-013:
        // `hiddenAt` is decoded from a user-writable defaults domain, so a
        // decodable-but-absurd stamp crashed the support command outright.
        guard let age = DisplayDuration.wholeSeconds(Date().timeIntervalSince(record.hiddenAt)) else {
            return "record held (timestamp unreadable — record may be corrupt; repair window \(window)s)"
        }
        return "record held (\(age)s old; repair window \(window)s)"
    }

    /// Every *other* live copy, with its path — so a support report answers
    /// "do you have two installed?" without the user needing to know that
    /// `LSUIElement` apps hide from the app switcher and from Force Quit.
    ///
    /// Strictly read-only, on purpose: the diagnostics flow must never take or
    /// perturb anything the single-instance guard consults, or the support
    /// command becomes a way to refuse a legitimate launch.
    ///
    /// The peer read itself comes from `SingleInstance`, so the report and the
    /// guard can never disagree about **what is running** — the same anti-drift
    /// reason `InstanceGuard.oneShotFlags` is shared rather than re-spelled.
    ///
    /// They do deliberately differ about what counts as a *duplicate*. Since the
    /// guard became session-scoped it ignores instances owned by another uid
    /// (fast user switching: a different user's Dock, not a duplicate), while
    /// this report still lists them — support wants to know a second user is
    /// running one. Those entries are marked `(another user)` precisely so the
    /// report cannot mislead in the other direction: without the marker, support
    /// would read a foreign pid as the recovery handle below and tell the user
    /// to kill a process they can neither see nor signal.
    ///
    /// Each pid printed here is also the recovery handle: an
    /// `LSUIElement` agent has no Force Quit row, so `kill -9 <pid>` is the only
    /// way to clear a wedged instance that is deflecting every new launch —
    /// plain `kill` sends SIGTERM, which `TerminationSignals` ignores and
    /// re-dispatches through the main queue that is itself wedged.
    @MainActor
    private static func otherInstances() -> String {
        guard let bundleID = Bundle.main.bundleIdentifier else { return "unknown (running unbundled)" }
        let others = SingleInstance.otherRunningInstances(
            bundleID: bundleID,
            selfPID: ProcessInfo.processInfo.processIdentifier
        )
        guard !others.isEmpty else { return "none" }
        let me = getuid()
        return others
            .map { app -> String in
                let path = app.bundleURL?.path ?? "unknown path"
                let uid = SingleInstance.processInfo(of: app.processIdentifier)?.uid
                let foreign = (uid != nil && uid != me) ? " (another user)" : ""
                return "pid \(app.processIdentifier) at \(path)\(foreign)"
            }
            .joined(separator: ", ")
    }
}
