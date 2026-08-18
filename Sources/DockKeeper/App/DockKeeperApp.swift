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
        // Then stand down if another DockKeeper already owns this user's Dock
        // (DK-FR-012). Ordering is load-bearing in both directions: strictly
        // after Diagnostics, because `--diagnostics` is a support flow run
        // *while* an instance is live; and strictly here rather than in
        // AppDelegate, because `@StateObject private var state = AppState()`
        // stores an @autoclosure thunk that is not evaluated until the scene
        // graph is built — i.e. after init() returns but before
        // applicationWillFinishLaunching. By either delegate hook the duplicate
        // has already run monitor.start()/coordinator.enable() and moved the
        // real Dock; by didFinishLaunching it also has a visible status item.
        SingleInstance.yieldIfDuplicate()
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
