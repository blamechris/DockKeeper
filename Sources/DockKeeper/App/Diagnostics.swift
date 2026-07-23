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
        guard CommandLine.arguments.contains("--diagnostics") else { return }
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
        LSUIElement:     \(bundle.infoDictionary?["LSUIElement"] as? Bool ?? false)
        Launch at Login: \(loginStatus)
        CoreDock API:    \(CoreDock.isAvailable ? "available" : "unavailable")
        Dock edge:       \(DockController().currentOrientation()?.displayName ?? "unknown")
        Displays:        \(DisplayManager.activeDisplays().count)
        Separate Spaces: \(separateSpaces ? "on (pinning unsupported)" : "off (pinning supported)")
        """
    }
}
