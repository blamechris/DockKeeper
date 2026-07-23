import Foundation

/// Opt-in, bounded, on-device diagnostics file (TDD §4.3 DiagnosticsLogger,
/// §12 privacy rules).
///
/// os_log retention is short and hard for users to export; when the user opts
/// in (`Settings.diagnosticsFileEnabled`) DockKeeper appends a curated,
/// high-signal trail — state transitions, corrections, pin outcomes — to
/// `~/Library/Logs/DockKeeper/dockkeeper.log`, suitable for attaching to a
/// GitHub issue.
///
/// Bounds: the file rotates once past ~1 MB (one `.1` predecessor kept) and
/// anything older than 7 days is pruned when logging is (re)enabled. Content
/// rules match the os_log discipline: edge names, event names, and numeric
/// display IDs only — never window titles, app names, or other sensitive
/// values.
@MainActor
public final class FileDiagnostics {

    public static let shared = FileDiagnostics()

    public var isEnabled = false {
        didSet { if isEnabled, !oldValue { pruneOldFiles() } }
    }

    public let fileURL: URL
    private let directory: URL
    private let maxBytes: Int
    private let maxAge: TimeInterval

    /// Injectable for tests; production uses `~/Library/Logs/DockKeeper`.
    public init(
        directory: URL = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DockKeeper", isDirectory: true),
        maxBytes: Int = 1_000_000,
        maxAge: TimeInterval = 7 * 24 * 3600
    ) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("dockkeeper.log")
        self.maxBytes = maxBytes
        self.maxAge = maxAge
    }

    /// Append one diagnostic line. No-op unless the user opted in.
    public func note(_ category: String, _ message: String) {
        guard isEnabled else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) [\(category)] \(message)\n"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded()
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            Log.app.error("Diagnostics file write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Bounds

    private var rotatedURL: URL { directory.appendingPathComponent("dockkeeper.log.1") }

    private func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        guard size >= maxBytes else { return }
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
    }

    private func pruneOldFiles() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
