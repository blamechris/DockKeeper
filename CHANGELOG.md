# Changelog

All notable user-facing changes to DockKeeper, newest first.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Both 0.9.x releases are public betas (GitHub pre-releases).

## [Unreleased]

### Added

- **Single-instance guard.** Launching a second copy of DockKeeper — a second install, or a fresh copy opened while an older one is still running — now exits immediately instead of leaving two copies fighting over the Dock. macOS treats an upgraded or rebuilt app bundle as a brand-new application, so this was reachable just by dragging a new copy over the old one without quitting first. There is no alert: the second launch simply does nothing, and the copy already running stays in charge.
- `--diagnostics` gained an `Other instances:` line, so a support report shows every live copy and its path — useful because a menu-bar-only app has no Force Quit entry to check.
- `DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES=1` runs two on purpose, for anyone comparing builds side by side.
- Launch-prep docs: README screenshots and badges, `SECURITY.md` (private vulnerability reporting), `CONTRIBUTING.md`, a PR template, and this changelog.

## [0.9.1] — 2026-07-28

Second public beta. The headline is an install-path fix that v0.9.0 users cannot see but do feel.

### Fixed

- **The app now carries its own notarization ticket.** v0.9.0 stapled only the DMG, and `brew install --cask` copies `DockKeeper.app` out of the image — so every first launch had to reach Apple's Gatekeeper service online. The pipeline now notarizes and staples the `.app` *before* packaging, then the DMG: two tickets, verified from inside the shipped image.
- `Scripts/package-dmg.sh` refuses to package an un-stapled app and re-mounts the finished image to confirm the ticket survived.

### Added

- `Scripts/release.sh` drives the whole build → notarize app → package → notarize DMG sequence in one invocation, validating the signing identity once and asserting a postcondition between every step.
- The CI no-networking-symbols gate now checks both binaries (app and CLI) for high-level networking APIs, raw socket syscalls, and linked networking frameworks.

### Changed

- App and CLI share one settings domain.
- Privacy claims audited to match the build exactly (security-audit follow-ups).

## [0.9.0] — 2026-07-24

First public release: a free, open-source, native macOS utility that keeps your Dock on the edge and display you chose. Signed and notarized (Developer ID, hardened runtime, stapled ticket).

### Added

- **Edge lock** (Bottom / Left / Right) with flicker-free live restore and automatic recovery after sleep, wake, and display changes — retry ladder, burst coalescing, and an oscillation guard that refuses to fight other software.
- **Preferred-display pinning**, including left/right Docks with *Displays have separate Spaces* **on** (the macOS default).
- **Display fingerprinting** that survives docks, adapters, and UUID churn — and never guesses between identical monitors.
- Opt-in **Keep windows in place** after a pin (the app's only permission, Accessibility, strictly optional).
- **Pause** for 15 min / 1 hour / until resumed, plus an optional ⌃⌥⌘D hotkey (off by default).
- Opt-in **hide the Dock while screen sharing**.
- Automation: `dockkeeper` CLI, `dockkeeper://` URL scheme, Apple Shortcuts intents.
- Menu-bar-only app (`.accessory`, no Dock icon of its own); **Launch at Login** via `SMAppService`.
- Distribution: notarized DMG on GitHub Releases and a Homebrew cask (`blamechris/tap/dockkeeper`).

### Known beta limits (why 0.9, not 1.0)

- The multi-monitor hardware test matrix is still being completed; preferred-display pinning is best-effort and partly unverified on real hardware.
- A bottom Dock can't be pinned while *separate Spaces* is on (macOS limitation — DockKeeper explains instead of fighting).
- Shortcuts-app discovery of the intents lands in v1.1; the `dockkeeper://` URL scheme works today.

[Unreleased]: https://github.com/blamechris/DockKeeper/compare/v0.9.1...HEAD
[0.9.1]: https://github.com/blamechris/DockKeeper/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/blamechris/DockKeeper/releases/tag/v0.9.0
