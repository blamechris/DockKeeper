import Foundation

/// The fields `dockkeeper status` reports, in one place so the CLI and the
/// `DockKeeperStatusIntent` cannot drift. Pure and `Sendable`; the live read
/// happens in `live(settings:)`.
public struct StatusSummary: Equatable, Sendable {
    public let isEnabled: Bool
    public let lockEdge: DockOrientation
    /// The Dock's current edge, or `nil` when macOS reports an unknown value.
    public let currentEdge: DockOrientation?
    /// Human-readable name of the active edge mechanism (primary or fallback).
    public let mechanism: String
    public let coreDockAvailable: Bool

    public init(
        isEnabled: Bool,
        lockEdge: DockOrientation,
        currentEdge: DockOrientation?,
        mechanism: String,
        coreDockAvailable: Bool
    ) {
        self.isEnabled = isEnabled
        self.lockEdge = lockEdge
        self.currentEdge = currentEdge
        self.mechanism = mechanism
        self.coreDockAvailable = coreDockAvailable
    }

    /// Snapshot the live state from the shared engine surface. Works without the
    /// menu-bar app running — it reads the same `Settings`/`DockController`/
    /// `CoreDock` the CLI does.
    public static func live(settings: Settings = .shared) -> StatusSummary {
        let controller = DockController(settings: settings)
        return StatusSummary(
            isEnabled: settings.isEnabled,
            lockEdge: settings.lockEdge,
            currentEdge: controller.currentOrientation(),
            mechanism: controller.activeMechanismName,
            coreDockAvailable: CoreDock.isAvailable
        )
    }

    /// The exact lines `dockkeeper status` prints, in order.
    public var cliLines: [String] {
        [
            "Enabled:    \(isEnabled ? "yes" : "no")",
            "Lock edge:  \(lockEdge.displayName)",
            "Dock is on: \(currentEdge?.displayName ?? "unknown")",
            "CoreDock:   \(coreDockAvailable ? "available" : "unavailable (using defaults fallback)")",
        ]
    }

    /// The CLI `status` block as a single string.
    public var cliText: String { cliLines.joined(separator: "\n") }

    /// A one-line, voice-friendly summary for Siri / Shortcuts results.
    public var voiceLine: String {
        let state = isEnabled
            ? "enabled, locking the Dock to the \(lockEdge.displayName.lowercased())"
            : "disabled"
        let current = currentEdge.map { " The Dock is on the \($0.displayName.lowercased())." } ?? ""
        return "DockKeeper is \(state).\(current) Mechanism: \(mechanism)."
    }
}
