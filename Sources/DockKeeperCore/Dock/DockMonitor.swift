import Foundation
import AppKit

/// Event sources only (TDD §4.3 post-refactor): watches everything that can
/// move the Dock and emits typed `DockEvent`s. All decisions — debounce,
/// retries, cooldown — belong to `RecoveryCoordinator`, the single consumer.
///
/// Sources:
/// - Wake from sleep / screens wake
/// - Display reconfiguration (plug/unplug, resolution, arrangement)
/// - Active-space changes / Mission Control
/// - Fast user switching (session activation)
/// - External settings edits (CLI while the app runs) via KVO
/// - A periodic safety-net poll (ADR-005: 30 s default)
///
/// Runs on the main actor because it touches AppKit notification centers.
/// Callers must pair `start()`/`stop()`; the CG callback and KVO registrations
/// hold unretained references to this object.
@MainActor
public final class DockMonitor {

    private let settings: Settings

    /// The single event sink. Set before `start()`.
    public var onEvent: (@MainActor (DockEvent) -> Void)?

    private var pollTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultCenterObservers: [NSObjectProtocol] = []
    private var displayCallbackRegistered = false
    private var settingsObserver: SettingsKVObserver?

    public init(settings: Settings = .shared) {
        self.settings = settings
    }

    public func start() {
        stop()
        registerNotifications()
        registerDisplayReconfigurationCallback()
        registerSettingsObservation()
        startPolling()
        Log.dock.info("DockMonitor started")
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        for observer in defaultCenterObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        defaultCenterObservers.removeAll()
        if displayCallbackRegistered {
            CGDisplayRemoveReconfigurationCallback(Self.displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
            displayCallbackRegistered = false
        }
        settingsObserver?.invalidate()
        settingsObserver = nil
    }

    deinit {
        // Timers and observers are cleaned up in `stop()`; callers must call
        // it before releasing. Kept minimal to stay MainActor-safe.
    }

    private func emit(_ event: DockEvent) {
        Log.dock.debug("Event: \(event.rawValue, privacy: .public)")
        onEvent?(event)
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        let workspaceEvents: [(NSNotification.Name, DockEvent)] = [
            (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.screensDidWakeNotification, .screensWake),
            (NSWorkspace.activeSpaceDidChangeNotification, .spaceChanged),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
        ]
        for (name, event) in workspaceEvents {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.emit(event)
                }
            }
            workspaceObservers.append(observer)
        }

        // Screen parameter changes (resolution / arrangement) come through the
        // standard NotificationCenter via NSApplication.
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.emit(.screenParametersChanged)
            }
        }
        defaultCenterObservers.append(screenObserver)
    }

    // MARK: - Display reconfiguration

    private func registerDisplayReconfigurationCallback() {
        let result = CGDisplayRegisterReconfigurationCallback(
            Self.displayReconfigured,
            Unmanaged.passUnretained(self).toOpaque()
        )
        displayCallbackRegistered = (result == .success)
        if !displayCallbackRegistered {
            Log.dock.error("Display reconfiguration callback failed to register; poll covers the gap")
        }
    }

    private static let displayReconfigured: CGDisplayReconfigurationCallBack = {
        _, flags, userInfo in
        guard let userInfo else { return }
        // Only react once the reconfiguration has completed.
        let done: CGDisplayChangeSummaryFlags = [.setModeFlag, .addFlag, .removeFlag, .desktopShapeChangedFlag]
        guard !flags.intersection(done).isEmpty else { return }
        let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            monitor.emit(.displayReconfigured)
        }
    }

    // MARK: - External settings changes (DK-FR-007-S3)

    /// KVO on the shared defaults sees cross-process edits (the CLI changing
    /// the lock edge while the app runs), unlike `UserDefaults.didChange`,
    /// which is in-process only. In-process writes also land here; they are
    /// harmless — reconciliation is idempotent and the coordinator debounces.
    private func registerSettingsObservation() {
        settingsObserver = SettingsKVObserver(
            defaults: settings.observableDefaults,
            keys: Settings.externallyObservedKeys
        ) { [weak self] in
            Task { @MainActor in
                self?.emit(.settingsChanged)
            }
        }
    }

    private final class SettingsKVObserver: NSObject {
        private let defaults: UserDefaults
        private let keys: [String]
        private let onChange: @Sendable () -> Void
        private var invalidated = false

        init(defaults: UserDefaults, keys: [String], onChange: @escaping @Sendable () -> Void) {
            self.defaults = defaults
            self.keys = keys
            self.onChange = onChange
            super.init()
            for key in keys {
                defaults.addObserver(self, forKeyPath: key, options: [.new], context: nil)
            }
        }

        func invalidate() {
            guard !invalidated else { return }
            invalidated = true
            for key in keys {
                defaults.removeObserver(self, forKeyPath: key)
            }
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            onChange()
        }

        deinit {
            invalidate()
        }
    }

    // MARK: - Polling safety net (ADR-005)

    private func startPolling() {
        let interval = max(5, settings.recoveryInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.emit(.pollTick)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
