// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockKeeper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DockKeeper", targets: ["DockKeeper"]),
        .executable(name: "dockkeeper", targets: ["dockkeeper-cli"]),
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
