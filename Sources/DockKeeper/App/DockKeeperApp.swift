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
}
