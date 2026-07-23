import Foundation
import AppKit

/// Watches for the events that make macOS move or reset the Dock, and asks the
/// `DockController` to restore the locked edge afterward.
///
/// Sources of drift we react to:
/// - Wake from sleep
/// - Display reconfiguration (plug/unplug, resolution, arrangement)
/// - Active-space changes / Mission Control
/// - Fast user switching (session activation)
/// - A periodic safety-net poll (covers anything the notifications miss)
///
/// Runs on the main actor because it touches AppKit notification centers.
@MainActor
public final class DockMonitor {

    private let controller: DockController
    private let settings: Settings

    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var displayCallbackRegistered = false

    public init(controller: DockController, settings: Settings = .shared) {
        self.controller = controller
        self.settings = settings
    }

    public func start() {
        stop()
        registerNotifications()
        registerDisplayReconfigurationCallback()
        startPolling()
        Log.dock.info("DockMonitor started")
        restoreSoon()
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            workspaceCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        observers.removeAll()
        if displayCallbackRegistered {
            CGDisplayRemoveReconfigurationCallback(Self.displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
            displayCallbackRegistered = false
        }
    }

    deinit {
        // Timers and observers are cleaned up in `stop()`; callers should call
        // it before releasing. Kept minimal to stay MainActor-safe.
    }

    // MARK: - Restoration

    /// Restore after a short settle delay so the system finishes its own
    /// layout work first.
    public func restoreSoon() {
        let delay = settings.restoreDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.controller.restoreToLockedEdge() {
                Log.dock.info("Restored Dock to locked edge after event")
            }
        }
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        let workspaceEvents: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in workspaceEvents {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    Log.dock.debug("Workspace event: \(name.rawValue, privacy: .public)")
                    self?.restoreSoon()
                }
            }
            observers.append(observer)
        }

        // Screen parameter changes (resolution / arrangement) come through the
        // standard NotificationCenter via NSApplication.
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.dock.debug("Screen parameters changed")
                self?.restoreSoon()
            }
        }
        observers.append(screenObserver)
    }

    // MARK: - Display reconfiguration

    private func registerDisplayReconfigurationCallback() {
        let result = CGDisplayRegisterReconfigurationCallback(
            Self.displayReconfigured,
            Unmanaged.passUnretained(self).toOpaque()
        )
        displayCallbackRegistered = (result == .success)
    }

    private static let displayReconfigured: CGDisplayReconfigurationCallBack = {
        _, flags, userInfo in
        guard let userInfo else { return }
        // Only react once the reconfiguration has completed.
        let done: CGDisplayChangeSummaryFlags = [.setModeFlag, .addFlag, .removeFlag, .desktopShapeChangedFlag]
        guard !flags.intersection(done).isEmpty else { return }
        let monitor = Unmanaged<DockMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        Task { @MainActor in
            monitor.restoreSoon()
        }
    }

    // MARK: - Polling safety net

    private func startPolling() {
        let interval = max(0.5, settings.recoveryInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.settings.isEnabled, self.settings.autoRecover else { return }
                self.controller.restoreToLockedEdge()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
