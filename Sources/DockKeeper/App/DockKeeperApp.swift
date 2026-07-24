import SwiftUI
import DockKeeperCore

/// DockKeeper — a menu-bar utility that keeps the macOS Dock locked to the
/// user's chosen edge, restoring it automatically after the system moves it.
@main
struct DockKeeperApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    init() {
        // Handle one-shot CLI flags before any UI or engine starts.
        Diagnostics.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra("DockKeeper", systemImage: state.recoveryState.menuSymbolName) {
            MenuBarContent()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
                .environmentObject(state)
        }
    }
}

/// Minimal AppKit delegate: makes DockKeeper a menu-bar accessory (no Dock
/// icon of its own) and kicks off the engine once the app is ready.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Handle `dockkeeper://` automation URLs (DK-FR-010). Registered via
    /// `CFBundleURLTypes`; macOS routes matching URLs here once the app runs.
    /// Parsing is pure (`ControlCommand.parse`) and execution funnels through
    /// the shared `AppState`. Privacy: query values could be anything, so the
    /// debug log records only the host and a validity flag — never the query.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = ControlCommand.parse(url: url) else {
                Log.app.debug("dockkeeper URL rejected (host: \(url.host ?? "none", privacy: .public), valid: false)")
                continue
            }
            Log.app.debug("dockkeeper URL accepted (host: \(url.host ?? "none", privacy: .public), valid: true)")
            AppState.shared?.perform(command)
        }
    }
}
