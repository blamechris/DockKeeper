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
        Separate Spaces: \(separateSpaces ? "on (pinning unsupported)" : "off (pinning supported)")
        Screen-share:    \(screenShareHideStatus())
        """
    }

    /// Whether a screen-capture hide record is outstanding — the support answer
    /// to "why is my Dock auto-hiding?" (DK-FR-013). Strictly read-only, and a
    /// relative age rather than a wall-clock stamp, matching the state-only
    /// content rule the rest of the report follows.
    private static func screenShareHideStatus() -> String {
        guard let record = Settings.shared.screenShareHideRecord else { return "no record held" }
        let age = Int(Date().timeIntervalSince(record.hiddenAt))
        let window = Int(ScreenShareHider.repairWindow)
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
    /// The peer read itself comes from `SingleInstance`, so the report can never
    /// disagree with the guard about who counts as another instance — the same
    /// anti-drift reason `InstanceGuard.oneShotFlags` is shared rather than
    /// re-spelled. Each pid printed here is also the recovery handle: an
    /// `LSUIElement` agent has no Force Quit row, so `kill <pid>` is the only
    /// way to clear a wedged instance that is deflecting every new launch.
    @MainActor
    private static func otherInstances() -> String {
        guard let bundleID = Bundle.main.bundleIdentifier else { return "unknown (running unbundled)" }
        let others = SingleInstance.otherRunningInstances(
            bundleID: bundleID,
            selfPID: ProcessInfo.processInfo.processIdentifier
        )
        guard !others.isEmpty else { return "none" }
        return others
            .map { "pid \($0.processIdentifier) at \($0.bundleURL?.path ?? "unknown path")" }
            .joined(separator: ", ")
    }
}
