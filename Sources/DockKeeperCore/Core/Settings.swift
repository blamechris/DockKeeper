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
        migratePreferredDisplayIfNeeded()
    }

    private static func registrationDomain() -> [String: Any] { [
        Keys.enabled: true,
        Keys.lockEdge: DockOrientation.bottom.rawValue,
        Keys.launchAtLogin: false,
        Keys.showMenuBarIcon: true,
        Keys.verboseLogging: false,
        Keys.restoreDelay: 0.4,
        Keys.recoveryInterval: 30.0,
    ] }

    // Note: v0.1 had an `autoRecover` key gating the poll; ADR-007 retired it —
    // `enabled` is the single switch. Any leftover on-disk value is ignored.
    enum Keys {
        static let enabled = "enabled"
        static let lockEdge = "lockEdge"
        static let preferredDisplayUUID = "preferredDisplayUUID"          // legacy (pre-ADR-004); kept in sync for rollback until v1.1
        static let preferredDisplayFingerprint = "preferredDisplayFingerprint"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let verboseLogging = "verboseLogging"
        static let restoreDelay = "restoreDelay"
        static let recoveryInterval = "recoveryInterval"
    }

    /// The keys whose external (e.g. CLI) edits should refresh a running app —
    /// observed via KVO by `DockMonitor` (DK-FR-007-S3).
    static let externallyObservedKeys = [Keys.enabled, Keys.lockEdge, Keys.preferredDisplayFingerprint]

    /// Backing store handle for KVO observation by `DockMonitor`.
    var observableDefaults: UserDefaults { defaults }

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

    /// The fingerprint of the display the Dock should stay on (ADR-004).
    /// `nil` means "any / don't pin to a specific display". Set via
    /// `setPreferredDisplay(fingerprint:)`.
    public var preferredDisplayFingerprint: DisplayFingerprint? {
        guard let data = defaults.data(forKey: Keys.preferredDisplayFingerprint) else { return nil }
        return try? JSONDecoder().decode(DisplayFingerprint.self, from: data)
    }

    /// Store (or clear, with `nil`) the preferred display. The legacy UUID key
    /// is mirrored so a rolled-back pre-fingerprint build still works
    /// (implementation-plan M2 rollback note; drop with v1.1).
    public func setPreferredDisplay(fingerprint: DisplayFingerprint?) {
        guard let fingerprint else {
            defaults.removeObject(forKey: Keys.preferredDisplayFingerprint)
            defaults.removeObject(forKey: Keys.preferredDisplayUUID)
            return
        }
        defaults.set(try? JSONEncoder().encode(fingerprint), forKey: Keys.preferredDisplayFingerprint)
        defaults.set(fingerprint.uuid, forKey: Keys.preferredDisplayUUID)
    }

    /// Stale-preference repair (TDD §7.3): a fallback-evidence match rewrites
    /// the stored fingerprint with fresh identifiers so it heals instead of
    /// rotting.
    public func repairPreferredDisplay(_ fresh: DisplayFingerprint) {
        Log.display.info("Repairing stale preferred-display fingerprint")
        setPreferredDisplay(fingerprint: fresh)
    }

    /// v0.1 stored a bare UUID string. Build a fingerprint from it once;
    /// unstable `"cg-<id>"` placeholders are discarded outright (they must
    /// never be persisted — TDD §7.1). The legacy key itself is kept in sync
    /// for rollback.
    private func migratePreferredDisplayIfNeeded() {
        guard
            defaults.data(forKey: Keys.preferredDisplayFingerprint) == nil,
            let legacy = defaults.string(forKey: Keys.preferredDisplayUUID)
        else { return }
        if legacy.hasPrefix("cg-") {
            Log.display.info("Discarding unstable legacy display preference")
            defaults.removeObject(forKey: Keys.preferredDisplayUUID)
            return
        }
        setPreferredDisplay(fingerprint: DisplayFingerprint(uuid: legacy))
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
