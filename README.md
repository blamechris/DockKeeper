# DockKeeper

A lightweight, native macOS menu-bar utility that keeps your Dock exactly where you want it — locked to your chosen edge and restored automatically whenever macOS tries to move it.

**Free forever. Open source. No subscriptions, no telemetry, no ads.**

> ⚠️ Early development (v0.1). Core engine, menu-bar app, and CLI are scaffolded and building; not yet feature-complete.

## Why

macOS loves to relocate the Dock — after sleep, display changes, or when you least expect it. DockKeeper watches for those events and puts the Dock back on your preferred edge, silently.

## Features

- Lock the Dock to **Bottom**, **Left**, or **Right**
- Automatic recovery after sleep, wake, display plug/unplug, resolution and arrangement changes
- Menu-bar app that stays out of your way (`.accessory` — no Dock icon of its own)
- Command-line interface: `dockkeeper lock left`
- Uses the private `CoreDock` API for flicker-free repositioning, with a `defaults`+restart fallback

### Planned (see roadmap)

- Preferred-display pinning
- Launch at login
- Global hotkeys, Apple Shortcuts, AppleScript
- Follow mouse / active window / active app

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode 26 / Swift 6.3)
- Apple Silicon (primary) or Intel (best effort)

## Build & Run

```sh
# Build everything
swift build

# Run the menu-bar app
swift run DockKeeper

# Use the CLI
swift run dockkeeper status
swift run dockkeeper lock left

# Run tests
swift test
```

## Architecture

```
DockKeeperCore   — shared engine (no UI deps; used by app + CLI)
├── Dock         — DockController, DockMonitor, CoreDock bridge, orientation model
├── Display      — DisplayManager (UUID-stable display identification)
└── Core         — Settings, logging

DockKeeper       — menu-bar app (SwiftUI MenuBarExtra + preferences)
dockkeeper-cli   — command-line front end
```

The Dock is repositioned via the private `CoreDock` C API (`CoreDockSetOrientationAndPinning`), resolved at runtime with `dlsym` so a future macOS change degrades gracefully to the `defaults write com.apple.dock orientation` + `killall Dock` fallback.

## License

MIT © 2026 blamechris. See [LICENSE](LICENSE).
