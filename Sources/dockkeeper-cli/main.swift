import Foundation
import DockKeeperCore

/// `dockkeeper` — a small command-line front end over the same engine the
/// menu-bar app uses. Shares settings via `UserDefaults`, so `dockkeeper lock
/// left` and the app's menu stay in sync.
///
/// Usage:
///   dockkeeper lock <bottom|left|right>
///   dockkeeper unlock
///   dockkeeper status

let settings = Settings.shared
let controller = DockController(settings: settings)

func printUsage() {
    print("""
    DockKeeper CLI

    Usage:
      dockkeeper lock <bottom|left|right>   Lock the Dock to an edge
      dockkeeper unlock                     Stop enforcing the locked edge
      dockkeeper status                     Show current state
    """)
}

func runStatus() {
    // Shared with the `DockKeeperStatusIntent` so the two cannot drift.
    let summary = StatusSummary(
        isEnabled: settings.isEnabled,
        lockEdge: settings.lockEdge,
        currentEdge: controller.currentOrientation(),
        mechanism: controller.activeMechanismName,
        coreDockAvailable: CoreDock.isAvailable
    )
    print(summary.cliText)
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
    runStatus()

case "-h", "--help", "help":
    printUsage()

default:
    print("error: unknown command '\(command)'")
    printUsage()
    exit(EXIT_FAILURE)
}
