import Foundation
import DockKeeperCore

/// A clean, isolated `UserDefaults` suite for one test.
///
/// Deliberately **deterministic** rather than UUID-named. Every
/// `UserDefaults(suiteName:)` creates a real plist in
/// `~/Library/Preferences`, and a fresh UUID per run meant those accumulated
/// forever — 203 stale `com.dockkeeper.tests.*.plist` files on the dev machine
/// before this helper existed. Keying on the suite plus the test name keeps
/// them unique across parallel tests (so no cross-talk) while reusing the same
/// handful of files run over run.
///
/// The domain is wiped on creation, so each test still starts empty regardless
/// of what the previous run left behind.
func makeTestDefaults(_ suite: String, _ test: String = #function) -> UserDefaults {
    let sanitized = "\(suite).\(test)"
        .replacingOccurrences(of: "(", with: "")
        .replacingOccurrences(of: ")", with: "")
        .replacingOccurrences(of: " ", with: "-")
    let name = "com.dockkeeper.tests.\(sanitized)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// `makeTestDefaults` wrapped in the `Settings` most tests actually want.
func makeTestSettings(_ suite: String, _ test: String = #function) -> Settings {
    Settings(defaults: makeTestDefaults(suite, test))
}
