// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockKeeper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DockKeeper", targets: ["DockKeeper"]),
        // Build product is `dockkeeper-cli` to avoid a case-insensitive
        // filesystem collision with the `DockKeeper` app binary. It ships /
        // symlinks as `dockkeeper` at install time (Homebrew, installer).
        .executable(name: "dockkeeper-cli", targets: ["dockkeeper-cli"]),
        .library(name: "DockKeeperCore", targets: ["DockKeeperCore"]),
    ],
    targets: [
        // Shared engine: Dock control, display tracking, settings, logging.
        // No SwiftUI/AppKit-UI dependencies so it stays usable from the CLI.
        .target(
            name: "DockKeeperCore"
        ),
        // Menu-bar application.
        .executableTarget(
            name: "DockKeeper",
            dependencies: ["DockKeeperCore"]
        ),
        // Command-line interface: `dockkeeper lock left`, etc.
        .executableTarget(
            name: "dockkeeper-cli",
            dependencies: ["DockKeeperCore"]
        ),
        .testTarget(
            name: "DockKeeperTests",
            dependencies: ["DockKeeperCore"]
        ),
    ]
)
