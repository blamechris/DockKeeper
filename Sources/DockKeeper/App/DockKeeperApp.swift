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

    /// Converts SIGTERM/SIGINT into the same orderly quit ⌘Q takes, so the
    /// termination cleanup below is not skipped on those paths. See the type.
    private let terminationSignals = TerminationSignals()

    /// Install the signal sources as early as a delegate hook allows.
    /// `willFinishLaunching` rather than `didFinishLaunching` because the
    /// `@StateObject` autoclosure that builds `AppState` — and therefore the
    /// first hider tick, which can already hide the Dock and write the record —
    /// runs before both (measured ~65 ms ahead of `didFinishLaunching`). The
    /// record covers that gap either way, so this is latency, not correctness.
    func applicationWillFinishLaunching(_ notification: Notification) {
        terminationSignals.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Put back what DockKeeper borrowed from the system before the process
    /// goes away (DK-FR-013).
    ///
    /// Fires for `NSApp.terminate(nil)` — the menu's "Quit DockKeeper" / ⌘Q
    /// (measured: `terminate` posts `willTerminateNotification` before the run
    /// loop unwinds) — and, via `TerminationSignals`, for SIGTERM and SIGINT. At
    /// logout/restart the Quit Apple Event **is sent but not waited for** for
    /// background (`LSUIElement`) processes, which loginwindow then kills
    /// (Apple, *System Startup Programming Topics*, "Terminating Processes"), so
    /// this hook is a *latency optimization*, not the mechanism. Correctness on
    /// every untrappable path — SIGKILL, Force Quit, crash, the logout kill —
    /// comes from the persisted record and the launch repair (DK-FR-013,
    /// ADR-013).
    ///
    /// `AppState.shared` is a weak static assigned at the end of
    /// `AppState.init`. The `@StateObject` autoclosure that builds it is
    /// evaluated when the scene graph is built — measured to be *before*
    /// `applicationWillFinishLaunching`, which is the ordering `init()` above
    /// depends on — so it is non-nil at any terminate that can follow a launch.
    /// The only nil case is a quit before the scene graph exists, where no
    /// hider ever ran and there is by definition nothing to restore.
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared?.prepareForTermination()
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
