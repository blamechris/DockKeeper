# DockKeeper

A lightweight, native macOS menu-bar utility that keeps your Dock exactly where you want it — locked to your chosen edge and restored automatically whenever macOS tries to move it.

**Free forever. Open source. No subscriptions, no telemetry, no ads.**

> ⚠️ Early development (v0.1). Core engine, menu-bar app, and CLI are scaffolded and building; not yet feature-complete.

## Why

macOS loves to relocate the Dock — after sleep, display changes, or when you least expect it. DockKeeper watches for those events and puts the Dock back on your preferred edge, silently.

## Features

- Lock the Dock to **Bottom**, **Left**, or **Right**
- Automatic recovery after sleep, wake, display plug/unplug, resolution and arrangement changes
- **Preferred display (best-effort):** keep the Dock on a chosen monitor by making it the main display
- **Launch at Login** via Apple's supported `SMAppService` API (requires the packaged `.app`)
- Menu-bar app that stays out of your way (`.accessory` — no Dock icon of its own)
- Command-line interface: `dockkeeper lock left`
- Uses the private `CoreDock` API for flicker-free repositioning, with a `defaults`+restart fallback

> **Note on Preferred Display:** macOS ties the Dock to the *main* display, so
> pinning the Dock to a monitor also moves the **menu bar** there — this is
> expected. Pinning requires *Displays have separate Spaces* to be **off**
> (System Settings → Desktop & Dock); when it's on, edge-locking still works and
> DockKeeper tells you why pinning is unavailable. See
> [the spike](Documentation/spikes/preferred-display-spike.md).

### Planned (see roadmap)

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

# Use the CLI (build product is `dockkeeper-cli`; ships as `dockkeeper`)
swift run dockkeeper-cli status
swift run dockkeeper-cli lock left

# Run tests
swift test
```

### Build the app bundle

SwiftPM produces a bare executable; the bundle script wraps it into a proper
`DockKeeper.app` (with `Info.plist` + entitlements) and ad-hoc code-signs it:

```sh
# Build dist/DockKeeper.app
Scripts/build-app.sh            # release; use "debug" for a faster loop

# Build and launch it
Scripts/run-app.sh

# One-shot status report (handy for bug reports)
dist/DockKeeper.app/Contents/MacOS/DockKeeper --diagnostics
```

> **Launch at Login note:** macOS registers login items through Background Task
> Management, which requires the app to live in **`/Applications`** with a full
> signature. From a dev build directory (or with an ad-hoc signature) the status
> reads `notFound` and the app tells you to move it to Applications. Everything
> else — menu bar, edge lock, preferred display — works from anywhere.

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
