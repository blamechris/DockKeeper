import Testing
import Foundation
@testable import DockKeeperCore

@Suite("FileDiagnostics")
@MainActor
struct FileDiagnosticsTests {

    private func makeSUT(maxBytes: Int = 200) -> (FileDiagnostics, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockkeeper-tests-\(UUID().uuidString)", isDirectory: true)
        return (FileDiagnostics(directory: dir, maxBytes: maxBytes), dir)
    }

    @Test("Disabled by default: writes nothing (DK-PRIV-001 S2)")
    func disabledWritesNothing() {
        let (sut, dir) = makeSUT()
        sut.note("test", "should not appear")
        #expect(!FileManager.default.fileExists(atPath: sut.fileURL.path))
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Enabled: appends timestamped lines")
    func appendsLines() throws {
        let (sut, dir) = makeSUT()
        sut.isEnabled = true
        sut.note("state", "monitoring")
        sut.note("pin", "pinned")
        let content = try String(contentsOf: sut.fileURL, encoding: .utf8)
        #expect(content.contains("[state] monitoring"))
        #expect(content.contains("[pin] pinned"))
        #expect(content.split(separator: "\n").count == 2)
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("Rotates past the byte cap; keeps exactly one predecessor (bounded)")
    func rotates() throws {
        let (sut, dir) = makeSUT(maxBytes: 120)
        sut.isEnabled = true
        for i in 0..<12 {
            sut.note("fill", "line \(i) padding padding padding")
        }
        let rotated = dir.appendingPathComponent("dockkeeper.log.1")
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        let liveSize = (try FileManager.default.attributesOfItem(atPath: sut.fileURL.path)[.size] as? Int) ?? 0
        #expect(liveSize < 240, "live file must stay near the cap after rotation")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["dockkeeper.log", "dockkeeper.log.1"], "exactly one predecessor is kept")
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite("RecoveryState menu symbol")
struct MenuSymbolTests {

    @Test("Every state maps to a visually distinct, intentional symbol")
    func mapping() {
        #expect(RecoveryState.disabled.menuSymbolName == "rectangle.dashed")
        #expect(RecoveryState.monitoring.menuSymbolName == "dock.rectangle")
        #expect(RecoveryState.restoring.menuSymbolName == "dock.rectangle")
        #expect(RecoveryState.preferredDisplayMissing.menuSymbolName == "dock.rectangle")
        #expect(RecoveryState.degraded.menuSymbolName == "exclamationmark.triangle")
        #expect(RecoveryState.error(.oscillation).menuSymbolName == "exclamationmark.triangle")
        #expect(RecoveryState.paused.menuSymbolName == "pause.rectangle")
        // The v0.1 bug was enabled == disabled; pin the distinction.
        #expect(RecoveryState.monitoring.menuSymbolName != RecoveryState.disabled.menuSymbolName)
    }
}
