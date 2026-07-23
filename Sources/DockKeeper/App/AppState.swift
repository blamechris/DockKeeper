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
    private let pinner: DisplayPinner = MainDisplayPinner()

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

    /// UUID of the display the Dock should stay on; `nil` = no preference.
    @Published var preferredDisplayUUID: String? {
        didSet {
            settings.preferredDisplayUUID = preferredDisplayUUID
            applyPreferredDisplay()
        }
    }

    @Published private(set) var displays: [DisplayInfo] = []

    /// Last pin result, surfaced to the UI (e.g. "separate Spaces is on").
    @Published private(set) var lastPinMessage: String?

    init() {
        let controller = DockController(settings: settings)
        self.controller = controller
        self.monitor = DockMonitor(controller: controller, settings: settings)
        self.isEnabled = settings.isEnabled
        self.lockEdge = settings.lockEdge
        self.autoRecover = settings.autoRecover
        self.preferredDisplayUUID = settings.preferredDisplayUUID
        self.displays = DisplayManager.activeDisplays()

        // Re-apply the preferred-display pin whenever the monitor restores the
        // edge (wake, display change, poll, launch).
        monitor.additionalRestore = { [weak self] in
            self?.applyPreferredDisplay()
        }

        // Property observers don't fire from within init, so start explicitly.
        Log.verbose = settings.verboseLogging
        applyEnabledState()
    }

    /// Set the lock edge from the menu and immediately enforce it.
    func lock(to edge: DockOrientation) {
        lockEdge = edge
    }

    /// Choose (or clear, with `nil`) the preferred display from the menu.
    func setPreferredDisplay(_ uuid: String?) {
        preferredDisplayUUID = uuid
    }

    func refreshDisplays() {
        displays = DisplayManager.activeDisplays()
    }

    /// Ask the pinner to keep the Dock on the preferred display, recording any
    /// user-facing message from the outcome.
    private func applyPreferredDisplay() {
        guard isEnabled else { return }
        let outcome = pinner.pin(toUUID: preferredDisplayUUID)
        lastPinMessage = outcome.userMessage
    }

    private func applyEnabledState() {
        if isEnabled {
            monitor.start()          // start() also performs an initial restore
        } else {
            monitor.stop()
        }
    }
}
