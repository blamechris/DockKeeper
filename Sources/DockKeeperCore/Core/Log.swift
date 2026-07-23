import Foundation
import os

/// Centralized logging via the unified logging system (`os.Logger`).
///
/// Per the project's privacy stance there is no telemetry or crash reporting —
/// these logs stay on-device and are viewable in Console.app under the
/// `com.dockkeeper.app` subsystem. Verbose logging is opt-in via preferences.
public enum Log {
    public static let subsystem = "com.dockkeeper.app"

    public static let dock = Logger(subsystem: subsystem, category: "dock")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let accessibility = Logger(subsystem: subsystem, category: "accessibility")

    /// When false, `debug`-level statements should be skipped by callers that
    /// gate on it. `os.Logger` already elides debug in release, but this lets
    /// the user toggle verbose behavior at runtime.
    public nonisolated(unsafe) static var verbose = false
}
