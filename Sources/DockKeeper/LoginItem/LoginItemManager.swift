import Foundation
import ServiceManagement
import DockKeeperCore

/// Manages DockKeeper's "Launch at Login" state via `SMAppService` — Apple's
/// current, supported login-item API (macOS 13+). No helper tool or
/// deprecated `LSSharedFileList` shenanigans.
///
/// The system is the source of truth: `SMAppService.mainApp.status` reflects
/// the real registration, including the user approving/revoking it in System
/// Settings. This wrapper just reads that and toggles registration.
@MainActor
enum LoginItemManager {

    /// Whether DockKeeper is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Register or unregister the app as a login item. Throws if the system
    /// rejects the change (e.g. the app isn't a proper bundle yet).
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }

    /// Opens System Settings → General → Login Items, for when the user needs
    /// to approve DockKeeper.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// A user-facing note for states that need explanation. `nil` when there's
    /// nothing to say (enabled or plainly not registered).
    static var statusMessage: String? {
        message(for: status)
    }

    /// Pure mapping from status to message, split out for clarity/testing.
    static func message(for status: SMAppService.Status) -> String? {
        switch status {
        case .requiresApproval:
            return "Approve DockKeeper in System Settings \u{203A} General \u{203A} Login Items."
        case .notFound:
            return "Launch at Login needs the packaged app (build the .app, not \u{201C}swift run\u{201D})."
        case .enabled, .notRegistered:
            return nil
        @unknown default:
            return nil
        }
    }
}
