# DockKeeper

A lightweight, native macOS menu-bar utility that keeps your Dock exactly where you want it — locked to your chosen edge and restored automatically whenever macOS tries to move it.

**Free forever. Open source. No subscriptions, no telemetry, no ads, no permissions.**

> 🚧 **v0.9 public beta** — feature-complete for v1.0; the multi-monitor
> hardware test matrix is still being worked through. Signed and notarized.

## Why

macOS loves to relocate the Dock — after sleep, display changes, or when you least expect it. DockKeeper watches for those events and puts the Dock back on your preferred edge, silently.

## Features

- Lock the Dock to **Bottom**, **Left**, or **Right** — flicker-free live repositioning
- Automatic recovery after sleep, wake, display plug/unplug, resolution and arrangement changes — with burst coalescing, a retry ladder for slow wakes, and an oscillation guard that refuses to fight other software
- **Preferred display:** keep the Dock on a chosen monitor. Works with *Displays have separate Spaces* **on** (the macOS default) for left/right Docks, and for any edge with it off
- Displays recognized by a **multi-signal fingerprint** (survives docks, adapters, and UUID churn; never guesses between identical monitors)
- **Keep windows in place** (opt-in): restores your window layout after a display pin — the only feature that uses a permission (Accessibility), strictly optional
- **Pause** (15 min / 1 hour / until resumed) for temporary Dock moves, with an optional global hotkey (⌃⌥⌘D, off by default)
- **Hide the Dock while screen sharing** (opt-in)
- Automation: `dockkeeper` CLI, a `dockkeeper://` URL scheme, and Apple Shortcuts intents
- Menu-bar app that stays out of your way (`.accessory` — no Dock icon of its own); **Launch at Login** via Apple's supported `SMAppService`
- Opt-in, bounded, local-only diagnostics file for bug reports — nothing ever leaves your Mac ([privacy statement](PRIVACY.md))

> **How pinning works:** macOS ties the Dock to the *main* display, so pinning
> re-bases which display is main. With separate Spaces **off** that also moves
> the menu bar (expected); with it **on** (default), every display keeps its own
> menu bar and left/right Docks pin cleanly — a bottom Dock can't be pinned in
> that mode, and DockKeeper says so instead of fighting the OS.

### Planned

- Bottom-Dock pinning in separate-Spaces mode (mechanism research ongoing)
- Follow mouse / active window / active app
- Raycast extension; Shortcuts app discovery (the intents exist; the metadata packaging lands in v1.1 — the URL scheme works today)

## Install

**Download:** grab the notarized `DockKeeper-x.y.z.dmg` from [Releases](https://github.com/blamechris/DockKeeper/releases), drag `DockKeeper.app` to Applications (required for Launch at Login), and optionally copy `dockkeeper` somewhere on your `PATH`.

**Homebrew:**

```sh
brew install --cask blamechris/tap/dockkeeper
```

## Requirements

- macOS 14+
- To build from source: Swift 6 toolchain (Xcode 26 / Swift 6.3)
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
