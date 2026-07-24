import AppIntents
import DockKeeperCore

/// Apple Shortcuts / App Intents surface (DK-FR-010). Every intent funnels
/// through the shared `ControlCommand` / `AppState` control surface — no new
/// engine mechanism and no new permission.
///
/// Runtime note (INFERRED — not executed on-device): App Intents metadata
/// extraction is normally an Xcode build phase. The current `swift build` +
/// `Scripts/build-app.sh` packaging does not emit `Metadata.appintents`, so
/// Shortcuts/Siri *discovery* is UNKNOWN until packaging adds that step. The
/// code below compiles under Swift 6 strict concurrency and is structurally
/// correct.

// MARK: - Edge enum

/// The user-selectable Dock edges, as an App Intents enum (excludes `top`,
/// which macOS does not support — mirrors `DockOrientation.userSelectable`).
enum DockEdgeAppEnum: String, AppEnum {
    case bottom
    case left
    case right

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Dock Edge")
    }

    static var caseDisplayRepresentations: [DockEdgeAppEnum: DisplayRepresentation] {
        [
            .bottom: "Bottom",
            .left: "Left",
            .right: "Right",
        ]
    }

    var orientation: DockOrientation {
        switch self {
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        }
    }
}

// MARK: - Intents

struct LockDockIntent: AppIntent {
    static var title: LocalizedStringResource { "Lock Dock to Edge" }
    static var description: IntentDescription {
        IntentDescription("Enable DockKeeper and lock the Dock to the bottom, left, or right edge.")
    }
    // Automation drives the running app's control surface; launch it if needed.
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Edge", default: .left)
    var edge: DockEdgeAppEnum

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared?.perform(.lock(edge.orientation))
        return .result()
    }
}

struct UnlockDockIntent: AppIntent {
    static var title: LocalizedStringResource { "Unlock Dock" }
    static var description: IntentDescription {
        IntentDescription("Disable DockKeeper so the Dock edge is no longer enforced.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared?.perform(.unlock)
        return .result()
    }
}

struct PauseDockKeeperIntent: AppIntent {
    static var title: LocalizedStringResource { "Pause DockKeeper" }
    static var description: IntentDescription {
        IntentDescription("Pause DockKeeper corrections, optionally for a number of minutes; omit to pause until resumed.")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Minutes")
    var minutes: Int?

    @MainActor
    func perform() async throws -> some IntentResult {
        let duration = Self.clampedDuration(fromMinutes: minutes)
        AppState.shared?.perform(.pause(duration))
        return .result()
    }

    /// `nil` (or non-positive) → pause until resumed; otherwise seconds capped
    /// at 24h, matching `ControlCommand` URL semantics.
    static func clampedDuration(fromMinutes minutes: Int?) -> TimeInterval? {
        guard let minutes, minutes > 0 else { return nil }
        return min(TimeInterval(minutes) * 60, ControlCommand.maxPauseSeconds)
    }
}

struct ResumeDockKeeperIntent: AppIntent {
    static var title: LocalizedStringResource { "Resume DockKeeper" }
    static var description: IntentDescription {
        IntentDescription("Resume DockKeeper and re-enforce the locked edge.")
    }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared?.perform(.resume)
        return .result()
    }
}

struct DockKeeperStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "Get DockKeeper Status" }
    static var description: IntentDescription {
        IntentDescription("Report whether DockKeeper is enabled, its locked edge, the Dock's current edge, and the active mechanism.")
    }
    // Status reads the shared settings/engine directly, so it need not launch
    // the menu-bar app.
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let summary = AppState.shared?.statusSummary() ?? StatusSummary.live()
        let line = summary.voiceLine
        return .result(value: line, dialog: IntentDialog(stringLiteral: line))
    }
}

// MARK: - Shortcuts

/// App Shortcuts phrases. Each phrase must include the app name token
/// (`\(.applicationName)`), so the "Lock my Dock to the left" phrasing carries
/// a "with DockKeeper" suffix; it uses the intent's default `left` edge.
struct DockKeeperShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseDockKeeperIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause \(.applicationName) corrections",
            ],
            shortTitle: "Pause DockKeeper",
            systemImageName: "pause.rectangle"
        )
        AppShortcut(
            intent: ResumeDockKeeperIntent(),
            phrases: [
                "Resume \(.applicationName)",
            ],
            shortTitle: "Resume DockKeeper",
            systemImageName: "play.rectangle"
        )
        AppShortcut(
            intent: LockDockIntent(),
            phrases: [
                "Lock my Dock to the left with \(.applicationName)",
            ],
            shortTitle: "Lock Dock",
            systemImageName: "dock.rectangle"
        )
    }
}
