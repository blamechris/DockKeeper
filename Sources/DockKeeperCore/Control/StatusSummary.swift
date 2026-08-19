import Foundation

/// The fields `dockkeeper status` reports, in one place so the CLI and the
/// `DockKeeperStatusIntent` cannot drift — a claim that now holds because both
/// go through `live(settings:)` rather than re-spelling the construction, and
/// because no field may be silently omitted (see `init`). Pure and `Sendable`; the live read
/// happens in `live(settings:)`.
public struct StatusSummary: Equatable, Sendable {
    public let isEnabled: Bool
    public let lockEdge: DockOrientation
    /// The Dock's current edge, or `nil` when macOS reports an unknown value.
    public let currentEdge: DockOrientation?
    /// Human-readable name of the active edge mechanism (primary or fallback).
    public let mechanism: String
    public let coreDockAvailable: Bool

    /// The durable pause record, or `nil` when corrections are not paused
    /// (DK-FR-009, ADR-014). Distinct from `isEnabled`: a paused instance is
    /// still enabled and still configured, it is simply not correcting — which
    /// is why reporting only `Enabled: yes` was actively misleading (#36).
    public let pauseRecord: PauseRecord?

    public init(
        isEnabled: Bool,
        lockEdge: DockOrientation,
        currentEdge: DockOrientation?,
        mechanism: String,
        coreDockAvailable: Bool,
        // Deliberately **not** defaulted. It was, for source compatibility, and
        // that default silently kept a stale hand-rolled copy in
        // `AppState.statusSummary()` compiling — so the Shortcuts/Siri intent
        // went on reporting "enabled" while paused. A required argument turns
        // that class of miss into a build error instead of a wrong answer.
        pauseRecord: PauseRecord?
    ) {
        self.isEnabled = isEnabled
        self.lockEdge = lockEdge
        self.currentEdge = currentEdge
        self.mechanism = mechanism
        self.coreDockAvailable = coreDockAvailable
        self.pauseRecord = pauseRecord
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
            coreDockAvailable: CoreDock.isAvailable,
            pauseRecord: settings.pauseRecord
        )
    }

    /// The exact lines `dockkeeper status` prints, in order.
    public var cliLines: [String] {
        [
            "Enabled:    \(isEnabled ? "yes" : "no")",
            "Lock edge:  \(lockEdge.displayName)",
            "Dock is on: \(currentEdge?.displayName ?? "unknown")",
            "Paused:     \(pauseLine)",
            "CoreDock:   \(coreDockAvailable ? "available" : "unavailable (using defaults fallback)")",
        ]
    }

    /// The `Paused:` value, printed whether or not a pause is in force — the
    /// point of #36 is that the two cases be *distinguishable*, which a line
    /// that vanishes when unpaused does not achieve in a pasted support report.
    ///
    /// A wall-clock deadline is fine here: unlike `--diagnostics`, `status` is
    /// read by the user at their own machine, and "until 3:45 PM" is what the
    /// menu already shows them (`AppState.pausedStatusText`).
    var pauseLine: String {
        guard let pauseRecord else { return "no" }
        guard let until = pauseRecord.pausedUntil else {
            return "yes (until resumed — no timer)"
        }
        return "yes (until \(until.formatted(date: .omitted, time: .shortened)))"
    }

    /// The CLI `status` block as a single string.
    public var cliText: String { cliLines.joined(separator: "\n") }

    /// A one-line, voice-friendly summary for Siri / Shortcuts results.
    public var voiceLine: String {
        let state = isEnabled
            ? "enabled, locking the Dock to the \(lockEdge.displayName.lowercased())"
            : "disabled"
        let current = currentEdge.map { " The Dock is on the \($0.displayName.lowercased())." } ?? ""
        // Pause leads, and suppresses the mechanism tail: asked out loud whether
        // DockKeeper is on, "enabled" alone is the wrong answer while it is
        // deliberately not correcting anything (#36).
        if let pauseRecord {
            let deadline = pauseRecord.pausedUntil
                .map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return "DockKeeper is paused\(deadline), so it is not correcting the Dock right now.\(current)"
        }
        return "DockKeeper is \(state).\(current) Mechanism: \(mechanism)."
    }
}
