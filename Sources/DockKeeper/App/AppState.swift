import Foundation
import SwiftUI
import DockKeeperCore

/// Observable bridge between SwiftUI and the `DockKeeperCore` engine.
///
/// Owns the long-lived monitor (event sources) and coordinator (the single
/// owner of reconciliation) and exposes the settings the menu and preferences
/// bind to. Lives on the main actor.
@MainActor
final class AppState: ObservableObject {

    private let settings = Settings.shared
    private let controller: DockController
    private let monitor: DockMonitor
    private let coordinator: RecoveryCoordinator

    @Published var isEnabled: Bool {
        didSet {
            guard !isSyncingFromExternal else { return }
            settings.isEnabled = isEnabled
            applyEnabledState()
        }
    }

    @Published var lockEdge: DockOrientation {
        didSet {
            guard !isSyncingFromExternal else { return }
            settings.lockEdge = lockEdge
            guard isEnabled else { return }
            // Apply immediately for snappy UX, then let the coordinator verify
            // (and re-pin) through the normal reconcile path.
            controller.forceOrientation(lockEdge)
            coordinator.requestReconcile()
        }
    }

    /// Launch DockKeeper at login. Source of truth is `SMAppService`; this
    /// mirrors it for the UI. Guarded against re-entrancy when we revert on
    /// failure.
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLoginItem else { return }
            applyLaunchAtLogin()
        }
    }
    private var isSyncingLoginItem = false

    /// Guards the published-property didSets while syncing FROM settings
    /// (external CLI edits observed via KVO), so we don't write back or loop.
    private var isSyncingFromExternal = false

    /// User-facing note about the login-item state (approval needed, etc.).
    @Published private(set) var loginItemMessage: String?

    /// UUID of the display the Dock should stay on; `nil` = no preference.
    @Published var preferredDisplayUUID: String? {
        didSet {
            guard !isSyncingFromExternal else { return }
            settings.preferredDisplayUUID = preferredDisplayUUID
            if isEnabled { coordinator.requestReconcile() }
        }
    }

    @Published private(set) var displays: [DisplayInfo] = []

    /// Last pin result, surfaced to the UI (e.g. "separate Spaces is on").
    @Published private(set) var lastPinMessage: String?

    /// Recovery-state note (degraded / preferred display missing / error);
    /// `nil` when everything is healthy.
    @Published private(set) var statusMessage: String?

    init() {
        let controller = DockController(settings: settings)
        self.controller = controller
        self.monitor = DockMonitor(settings: settings)
        self.coordinator = RecoveryCoordinator(
            controller: controller,
            settings: settings,
            machine: RecoveryMachine(config: RecoveryMachine.Config(debounce: settings.restoreDelay))
        )
        self.isEnabled = settings.isEnabled
        self.lockEdge = settings.lockEdge
        self.preferredDisplayUUID = settings.preferredDisplayUUID
        // System is the source of truth for login-item state.
        self.launchAtLogin = LoginItemManager.isEnabled
        self.loginItemMessage = LoginItemManager.statusMessage
        self.displays = DisplayManager.activeDisplays()

        monitor.onEvent = { [weak self] event in
            guard let self else { return }
            self.coordinator.handle(event)
            switch event {
            case .settingsChanged:
                self.syncFromSettings()
            case .displayReconfigured, .screenParametersChanged:
                self.refreshDisplays()
            default:
                break
            }
        }
        coordinator.onStateChange = { [weak self] state in
            self?.statusMessage = state.userMessage
        }
        coordinator.onPinOutcome = { [weak self] outcome in
            self?.lastPinMessage = outcome.userMessage
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

    /// Open System Settings so the user can approve the login item.
    func openLoginItemsSettings() {
        LoginItemManager.openLoginItemsSettings()
    }

    private func applyLaunchAtLogin() {
        do {
            try LoginItemManager.setEnabled(launchAtLogin)
            settings.launchAtLogin = launchAtLogin
            loginItemMessage = LoginItemManager.statusMessage
            Log.app.info("Launch at Login set to \(self.launchAtLogin, privacy: .public)")
        } catch {
            Log.app.error("Launch at Login change failed: \(error.localizedDescription, privacy: .public)")
            loginItemMessage = "Couldn't update Launch at Login: \(error.localizedDescription)"
            // Revert the toggle to the real system state without re-triggering.
            isSyncingLoginItem = true
            launchAtLogin = LoginItemManager.isEnabled
            isSyncingLoginItem = false
        }
    }

    private func applyEnabledState() {
        if isEnabled {
            monitor.start()
            coordinator.enable()  // performs the initial full reconcile
        } else {
            coordinator.disable()
            monitor.stop()
        }
    }

    /// Refresh published values after an external (CLI) settings edit
    /// (DK-FR-007-S3). Assignments are skipped when unchanged so the guarded
    /// didSets stay quiet.
    private func syncFromSettings() {
        isSyncingFromExternal = true
        defer { isSyncingFromExternal = false }
        if lockEdge != settings.lockEdge {
            lockEdge = settings.lockEdge
        }
        if preferredDisplayUUID != settings.preferredDisplayUUID {
            preferredDisplayUUID = settings.preferredDisplayUUID
        }
        if isEnabled != settings.isEnabled {
            isEnabled = settings.isEnabled
            // The didSet was suppressed; enact the enable/disable transition.
            applyEnabledState()
        }
    }
}
