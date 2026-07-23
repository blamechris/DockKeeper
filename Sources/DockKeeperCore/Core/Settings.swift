import Foundation

/// Persistent user settings, backed by `UserDefaults`.
///
/// `DockKeeperCore` deliberately keeps this as a plain `ObservableObject`-free
/// store so it is usable from the CLI. The menu-bar app layers SwiftUI
/// observation on top via its own wrapper.
public final class Settings: @unchecked Sendable {

    public static let shared = Settings()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaults.register(defaults: Self.registrationDomain())
    }

    private static func registrationDomain() -> [String: Any] { [
        Keys.enabled: true,
        Keys.lockEdge: DockOrientation.bottom.rawValue,
        Keys.autoRecover: true,
        Keys.launchAtLogin: false,
        Keys.showMenuBarIcon: true,
        Keys.verboseLogging: false,
        Keys.restoreDelay: 0.4,
        Keys.recoveryInterval: 2.0,
    ] }

    enum Keys {
        static let enabled = "enabled"
        static let lockEdge = "lockEdge"
        static let preferredDisplayUUID = "preferredDisplayUUID"
        static let autoRecover = "autoRecover"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let verboseLogging = "verboseLogging"
        static let restoreDelay = "restoreDelay"
        static let recoveryInterval = "recoveryInterval"
    }

    // MARK: General

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    public var showMenuBarIcon: Bool {
        get { defaults.bool(forKey: Keys.showMenuBarIcon) }
        set { defaults.set(newValue, forKey: Keys.showMenuBarIcon) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    // MARK: Dock

    public var lockEdge: DockOrientation {
        get { DockOrientation(rawValue: defaults.integer(forKey: Keys.lockEdge)) ?? .bottom }
        set { defaults.set(newValue.rawValue, forKey: Keys.lockEdge) }
    }

    /// UUID string of the display the Dock should stay on. `nil` means "any /
    /// don't pin to a specific display".
    public var preferredDisplayUUID: String? {
        get { defaults.string(forKey: Keys.preferredDisplayUUID) }
        set { defaults.set(newValue, forKey: Keys.preferredDisplayUUID) }
    }

    public var autoRecover: Bool {
        get { defaults.bool(forKey: Keys.autoRecover) }
        set { defaults.set(newValue, forKey: Keys.autoRecover) }
    }

    // MARK: Advanced

    public var verboseLogging: Bool {
        get { defaults.bool(forKey: Keys.verboseLogging) }
        set {
            defaults.set(newValue, forKey: Keys.verboseLogging)
            Log.verbose = newValue
        }
    }

    /// Seconds to wait after a display/wake event before restoring the Dock,
    /// letting the system settle first.
    public var restoreDelay: TimeInterval {
        get { defaults.double(forKey: Keys.restoreDelay) }
        set { defaults.set(newValue, forKey: Keys.restoreDelay) }
    }

    /// Polling interval (seconds) for the periodic recovery check.
    public var recoveryInterval: TimeInterval {
        get { defaults.double(forKey: Keys.recoveryInterval) }
        set { defaults.set(newValue, forKey: Keys.recoveryInterval) }
    }
}
