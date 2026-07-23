import Foundation
import SwiftUI
import DockKeeperCore

/// Observable bridge between SwiftUI and the `DockKeeperCore` engine.
///
/// Holds the long-lived controller and monitor and exposes the settings the
/// menu and preferences bind to. Lives on the main actor.
@MainActor
final class AppState: ObservableObject {

    private let settings = Settings.shared
    private let controller: DockController
    private let monitor: DockMonitor

    @Published var isEnabled: Bool {
        didSet {
            settings.isEnabled = isEnabled
            applyEnabledState()
        }
    }

    @Published var lockEdge: DockOrientation {
        didSet {
            settings.lockEdge = lockEdge
            if isEnabled { controller.forceOrientation(lockEdge) }
        }
    }

    @Published var autoRecover: Bool {
        didSet { settings.autoRecover = autoRecover }
    }

    @Published private(set) var displays: [DisplayInfo] = []

    init() {
        let controller = DockController(settings: settings)
        self.controller = controller
        self.monitor = DockMonitor(controller: controller, settings: settings)
        self.isEnabled = settings.isEnabled
        self.lockEdge = settings.lockEdge
        self.autoRecover = settings.autoRecover
        self.displays = DisplayManager.activeDisplays()

        // Property observers don't fire from within init, so start explicitly.
        Log.verbose = settings.verboseLogging
        applyEnabledState()
    }

    /// Set the lock edge from the menu and immediately enforce it.
    func lock(to edge: DockOrientation) {
        lockEdge = edge
    }

    func refreshDisplays() {
        displays = DisplayManager.activeDisplays()
    }

    private func applyEnabledState() {
        if isEnabled {
            monitor.start()          // start() also performs an initial restore
        } else {
            monitor.stop()
        }
    }
}
