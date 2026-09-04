import AppKit
import Foundation
import DockKeeperCore

/// `dockkeeper` — a small command-line front end over the same engine the
/// menu-bar app uses. Shares settings via `UserDefaults`, so `dockkeeper lock
/// left` and the app's menu stay in sync.
///
/// Usage:
///   dockkeeper lock <bottom|left|right>
///   dockkeeper unlock
///   dockkeeper status [--live]

let settings = Settings.shared
let controller = DockController(settings: settings)

func printUsage() {
    print("""
    DockKeeper CLI

    Usage:
      dockkeeper lock <bottom|left|right>   Lock the Dock to an edge
      dockkeeper unlock                     Stop enforcing the locked edge
      dockkeeper status                     Show current state
      dockkeeper status --live              Ask the running instance what it holds
    """)
}

func runStatus() {
    // `StatusSummary.live` is shared with the `DockKeeperStatusIntent` so the
    // two cannot drift. This used to re-spell the same construction by hand,
    // which is the drift the comment was warning about — adding the pause field
    // to one copy and not the other would have shipped a CLI that still could
    // not see a pause (#36).
    print(StatusSummary.live(settings: settings).cliText)
}

/// `dockkeeper status --live` — DK-FR-015.
///
/// Distinct from `runStatus()` in the one way that matters: `status` reports
/// **configured state, not liveness** and has always printed `Enabled: yes` with
/// no app running (ADR-014). This subcommand reports only what a running
/// instance published about itself, and when there is no such instance it says
/// so and prints nothing else. The two must never be blended — a block that
/// falls back to re-derivation when the app is absent is the instrument that
/// told two on-device sessions the opposite of the truth.
///
/// The fallback is foreclosed structurally: `LiveGuardReport` is handed a
/// reading, three plain disk values and the running-instance list, and has no
/// access to `Settings`, `DockController` or `BottomDockGuard.decide`.
@MainActor
func runLiveStatus() -> Int32 {
    let reading = LiveGuardReading.classify(
        stored: settings.liveGuardRecord,
        // The kernel decides liveness, and it is injected here rather than read
        // inside `classify` so every verdict — dead writer, recycled pid,
        // another user's process — is reachable from a unit test.
        writerIdentityNow: { ProcessIdentity.of(pid: $0) },
        readerUID: getuid()
    )
    let onDisk = DiskSettings(
        isEnabled: settings.isEnabled,
        lockEdge: settings.lockEdge,
        lockBottomDockToDisplay: settings.lockBottomDockToDisplay
    )
    print(
        LiveGuardReport.cliLines(
            for: reading,
            onDisk: onDisk,
            instances: observedInstances(),
            now: Date()
        ).joined(separator: "\n")
    )
    return LiveGuardReport.status(for: reading, onDisk: onDisk).rawValue
}

/// Other DockKeeper processes this machine can see — context only, never the
/// liveness verdict.
///
/// `runningApplications(withBundleIdentifier:)` resolves through LaunchServices,
/// where an unbundled `swift run DockKeeper` checks in under a null bundle
/// identifier and is therefore invisible (DK-FR-012 S7, confirmed on-device).
/// Treating this as the answer to "is DockKeeper running" would reproduce
/// #78's own false negative in the dev loop; it is used only to explain why a
/// record is *missing*.
@MainActor
func observedInstances() -> [ObservedInstance] {
    NSRunningApplication
        .runningApplications(withBundleIdentifier: Settings.suiteName)
        .map { app in
            let version = app.bundleURL
                .flatMap(Bundle.init(url:))
                .flatMap { $0.infoDictionary?["CFBundleShortVersionString"] as? String }
            return ObservedInstance(
                pid: app.processIdentifier,
                bundlePath: app.bundleURL?.path,
                version: version
            )
        }
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printUsage()
    exit(EXIT_FAILURE)
}

switch command {
case "lock":
    guard
        let edgeArg = arguments.dropFirst().first,
        let edge = DockOrientation(defaultsValue: edgeArg),
        DockOrientation.userSelectable.contains(edge)
    else {
        print("error: expected one of bottom, left, right")
        exit(EXIT_FAILURE)
    }
    settings.isEnabled = true
    settings.lockEdge = edge
    controller.forceOrientation(edge)
    print("Locked Dock to \(edge.displayName).")

case "unlock":
    settings.isEnabled = false
    print("DockKeeper disabled. The Dock will no longer be enforced.")

case "status":
    // Trailing arguments used to be discarded silently, so `dockkeeper status
    // --liv` printed the configured-state block and exited 0 — a typo answering
    // a question nobody asked, which is the acceptance criterion for #78
    // violated by a slip of the finger. Every token is accounted for now.
    let statusArguments = Array(arguments.dropFirst())
    switch statusArguments {
    case []:
        runStatus()
    case ["--live"]:
        exit(runLiveStatus())
    default:
        print("error: unknown option for status: \(statusArguments.joined(separator: " "))")
        printUsage()
        exit(EXIT_FAILURE)
    }

case "-h", "--help", "help":
    printUsage()

default:
    print("error: unknown command '\(command)'")
    printUsage()
    exit(EXIT_FAILURE)
}
