import Foundation
import SwiftUI
import ApplicationServices  // AXIsProcessTrusted / kAXTrustedCheckOptionPrompt
import DockKeeperCore

/// Observable bridge between SwiftUI and the `DockKeeperCore` engine.
///
/// Owns the long-lived monitor (event sources) and coordinator (the single
/// owner of reconciliation) and exposes the settings the menu and preferences
/// bind to. Lives on the main actor.
@MainActor
final class AppState: ObservableObject {

    /// The live instance, exposed so the `dockkeeper://` URL handler and App
    /// Intents can funnel through the same control surface. Set on `init`;
    /// there is exactly one `AppState` for the app's lifetime, held strongly by
    /// the `@StateObject` in `DockKeeperApp`.
    static private(set) weak var shared: AppState?

    private let settings = Settings.shared
    private let controller: DockController
    private let monitor: DockMonitor
    private let coordinator: RecoveryCoordinator
    private let hotKeyCenter = HotKeyCenter()

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

    /// Whether a preferred display is stored at all (drives the "Any" row).
    @Published private(set) var hasPreferredDisplay = false

    /// `DisplayInfo.id` of the connected display the stored fingerprint
    /// resolves to (drives the menu checkmark); `nil` when no preference is
    /// stored or the display isn't connected / is ambiguous.
    @Published private(set) var preferredDisplaySelectionID: String?

    @Published private(set) var displays: [DisplayInfo] = []

    /// Last pin result, surfaced to the UI (e.g. "separate Spaces is on").
    @Published private(set) var lastPinMessage: String?

    /// Recovery-state note (degraded / preferred display missing / error);
    /// `nil` when everything is healthy.
    @Published private(set) var statusMessage: String?

    /// Current recovery state — drives the state-distinct menu-bar icon.
    @Published private(set) var recoveryState: RecoveryState = .disabled

    /// Whether corrections are currently paused (DK-FR-009) — drives the menu's
    /// pause/resume section. Mirrors the coordinator via `onStateChange`.
    @Published private(set) var isPaused = false

    /// When a timed pause auto-resumes; `nil` when paused until resumed (or not
    /// paused). Drives the "Paused until …" menu note.
    @Published private(set) var pausedUntil: Date?

    /// Opt-in global hotkey (⌃⌥⌘D) to toggle pause (DK-FR-009). Off by default;
    /// registered only while on (kickoff rule 20 — no surprise global hotkey).
    @Published var pauseHotkeyEnabled: Bool {
        didSet {
            settings.pauseHotkeyEnabled = pauseHotkeyEnabled
            applyHotkeyState()
        }
    }

    /// Opt-in bounded diagnostics file (DK-PRIV-001 S2).
    @Published var diagnosticsFileEnabled: Bool {
        didSet {
            settings.diagnosticsFileEnabled = diagnosticsFileEnabled
            FileDiagnostics.shared.isEnabled = diagnosticsFileEnabled
        }
    }

    @Published var verboseLogging: Bool {
        didSet { settings.verboseLogging = verboseLogging }
    }

    /// Opt-in window restore across a pin (ADR-010). Enabling without the
    /// Accessibility grant prompts once (the caption is the contextual
    /// explanation shown *before* this point — TDD §10); the toggle may stay on
    /// while the grant is pending — `WindowLayoutPreserver` no-ops until trusted.
    @Published var preserveWindowLayout: Bool {
        didSet {
            settings.preserveWindowLayout = preserveWindowLayout
            if preserveWindowLayout, !AXIsProcessTrusted() {
                requestAccessibilityPermission()
            }
            refreshAccessibilityStatus()
        }
    }

    /// Whether Accessibility is currently granted — drives the "waiting for
    /// permission" caption. Refreshed on toggle and when the app reactivates
    /// (the user may grant it in System Settings and switch back).
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()

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
        self.diagnosticsFileEnabled = settings.diagnosticsFileEnabled
        self.verboseLogging = settings.verboseLogging
        self.preserveWindowLayout = settings.preserveWindowLayout
        self.pauseHotkeyEnabled = settings.pauseHotkeyEnabled
        FileDiagnostics.shared.isEnabled = settings.diagnosticsFileEnabled
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
            guard let self else { return }
            if state != self.recoveryState {
                FileDiagnostics.shared.note("state", String(describing: state))
            }
            self.recoveryState = state
            self.statusMessage = state.userMessage
            self.isPaused = (state == .paused)
            self.pausedUntil = self.coordinator.pausedUntil
        }
        hotKeyCenter.onHotKey = { [weak self] in self?.togglePause() }
        coordinator.onPinOutcome = { [weak self] outcome in
            if outcome != .noPreference, outcome != .alreadyOnTarget {
                FileDiagnostics.shared.note("pin", String(describing: outcome))
            }
            self?.lastPinMessage = outcome.userMessage
        }

        // Property observers don't fire from within init, so start explicitly.
        Log.verbose = settings.verboseLogging
        refreshPreferredSelection()
        applyEnabledState()
        applyHotkeyState()

        Self.shared = self
    }

    /// Set the lock edge from the menu and immediately enforce it.
    func lock(to edge: DockOrientation) {
        lockEdge = edge
    }

    // MARK: - Automation funnel (DK-FR-010)

    /// Single entry point for automation (`dockkeeper://` URLs and App Intents),
    /// routing a pure `ControlCommand` through the same published control
    /// surface the menu drives. No new engine mechanism — just the existing
    /// enable/lock/pause/resume paths.
    func perform(_ command: ControlCommand) {
        switch command {
        case .lock(let edge):
            // Parity with the CLI `lock`: enable, then pin to the edge.
            if !isEnabled { isEnabled = true }
            lock(to: edge)
        case .unlock:
            isEnabled = false
        case .pause(let duration):
            pause(for: duration)
        case .resume:
            resume()
        }
    }

    /// Live status for `DockKeeperStatusIntent`, built from the same fields the
    /// `dockkeeper status` CLI prints.
    func statusSummary() -> StatusSummary {
        StatusSummary(
            isEnabled: isEnabled,
            lockEdge: lockEdge,
            currentEdge: controller.currentOrientation(),
            mechanism: controller.activeMechanismName,
            coreDockAvailable: CoreDock.isAvailable
        )
    }

    // MARK: - Pause (DK-FR-009)

    /// Pause corrections. `duration == nil` pauses until an explicit resume.
    /// This is the "temporary move" path: pause, drag the Dock via normal
    /// macOS, then resume — a full reconcile re-enforces the edge/pin. A no-op
    /// while disabled (the menu hides pause items; the hotkey guards here).
    func pause(for duration: TimeInterval?) {
        guard isEnabled else { return }
        FileDiagnostics.shared.note("pause", Self.pauseLabel(for: duration))
        coordinator.pause(for: duration)
    }

    /// Resume corrections now and re-enforce (a full reconcile runs).
    func resume() {
        FileDiagnostics.shared.note("resume", "manual")
        coordinator.resume()
    }

    /// Toggle pause/resume — the shared code path for the menu and the hotkey.
    /// Pausing via toggle pauses until resumed (predictable; no hidden timer).
    func togglePause() {
        if coordinator.isPaused {
            resume()
        } else {
            pause(for: nil)
        }
    }

    /// Menu note while paused: "Paused" (until resumed) or "Paused until 3:45 PM".
    var pausedStatusText: String {
        guard isPaused else { return "" }
        guard let pausedUntil else { return "Paused" }
        return "Paused until \(pausedUntil.formatted(date: .omitted, time: .shortened))"
    }

    private static func pauseLabel(for duration: TimeInterval?) -> String {
        guard let duration else { return "until-resumed" }
        let minutes = Int(duration / 60)
        return minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m"
    }

    private func applyHotkeyState() {
        if pauseHotkeyEnabled {
            hotKeyCenter.start()
        } else {
            hotKeyCenter.stop()
        }
    }

    /// Choose (or clear, with `nil`) the preferred display from the menu.
    /// Persists the full fingerprint (ADR-004), never a bare pseudo-UUID.
    func setPreferredDisplay(_ display: DisplayInfo?) {
        if let display {
            settings.setPreferredDisplay(fingerprint: DisplayManager.fingerprint(for: display.displayID))
        } else {
            settings.setPreferredDisplay(fingerprint: nil)
        }
        refreshPreferredSelection()
        if isEnabled { coordinator.requestReconcile() }
    }

    func refreshDisplays() {
        displays = DisplayManager.activeDisplays()
        refreshPreferredSelection()
    }

    /// Re-resolve the stored fingerprint against the connected displays so the
    /// menu checkmark tracks identity, not a raw string comparison.
    private func refreshPreferredSelection() {
        let stored = settings.preferredDisplayFingerprint
        hasPreferredDisplay = stored != nil
        let candidates = displays.compactMap { display in
            display.fingerprint.map {
                FingerprintMatcher.Candidate(displayID: display.displayID, fingerprint: $0)
            }
        }
        if case .resolved(let displayID, _) = DisplayIdentityResolver.resolve(stored: stored, candidates: candidates) {
            preferredDisplaySelectionID = displays.first { $0.displayID == displayID }?.id
        } else {
            preferredDisplaySelectionID = nil
        }
    }

    /// Open System Settings so the user can approve the login item.
    func openLoginItemsSettings() {
        LoginItemManager.openLoginItemsSettings()
    }

    /// Re-check the Accessibility grant and publish it if changed. Called from
    /// the Advanced tab on appear and on app reactivation.
    func refreshAccessibilityStatus() {
        let granted = AXIsProcessTrusted()
        if granted != accessibilityGranted { accessibilityGranted = granted }
    }

    /// Deep-link to the Accessibility pane so the user can grant the permission.
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Explain-then-prompt: the caption is the contextual explanation, shown
    /// before the user enables the toggle; this fires the system prompt once.
    private func requestAccessibilityPermission() {
        // Literal value of `kAXTrustedCheckOptionPrompt` — referencing the SDK
        // global directly is a Swift 6 concurrency-unsafe shared-mutable read.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Reveal the diagnostics file in Finder (support-bundle flow).
    func revealDiagnosticsFile() {
        NSWorkspace.shared.activateFileViewerSelecting([FileDiagnostics.shared.fileURL])
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
        refreshPreferredSelection()
        if isEnabled != settings.isEnabled {
            isEnabled = settings.isEnabled
            // The didSet was suppressed; enact the enable/disable transition.
            applyEnabledState()
        }
    }
}
