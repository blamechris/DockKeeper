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
    // `StatusSummary.live` is shared with the `DockKeeperStatusIntent` so the
    // two cannot drift. This used to re-spell the same construction by hand,
    // which is the drift the comment was warning about — adding the pause field
    // to one copy and not the other would have shipped a CLI that still could
    // not see a pause (#36).
    print(StatusSummary.live(settings: settings).cliText)
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
