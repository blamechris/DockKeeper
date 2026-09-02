# Changelog

All notable user-facing changes to DockKeeper, newest first.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). All 0.9.x releases are public betas (GitHub pre-releases).

## [Unreleased]

### Added

- **A bottom Dock can now be kept on the display you chose.** With “Displays have separate Spaces” on, macOS hands a bottom Dock to whichever screen you push the pointer to — so it wanders. Turn on **Keep a bottom Dock on my preferred display** (Preferences › Advanced, off by default) and DockKeeper holds the pointer a few points clear of the bottom edge on your *other* displays, so the Dock is never called away. It needs Accessibility permission, at least two displays, and a bottom-edge lock. It **does not move the Dock back** — macOS does not allow that, and DockKeeper will not pretend otherwise. On arrangements where one display sits directly below another, the feature refuses to run: that bottom edge is how your pointer travels between the screens, and holding it would trap your cursor. While it is active, the bottom hot corners on the guarded displays stop working. ([G1](docs/parity-assessment.md))

- **You can now tell whether DockKeeper is paused without hunting for the menu-bar icon.** `dockkeeper status` gains a `Paused:` line — always present, so a paused install is distinguishable from a working one at a glance — and `DockKeeper --diagnostics` reports it too, which matters because a paused DockKeeper is *correctly* doing nothing and a support report from one used to look identical to a healthy install. Asking Siri or Shortcuts for the status now says the app is paused instead of just "enabled". Pausing does not survive a restart: relaunching DockKeeper resumes it. ([#36](https://github.com/blamechris/DockKeeper/issues/36))

### Fixed

- **A Dock that jumps between monitors now explains itself instead of going quiet.** On a multi-display Mac with the macOS default “Displays have separate Spaces” turned on, macOS hands a *bottom* Dock to whichever display your pointer summons it to — DockKeeper cannot pin it there, and has always declined rather than fight the OS. But the explanation only ever appeared if you had already chosen a preferred display, which most people never do, so the common case was total silence and DockKeeper looked broken. It now tells you what macOS is doing and offers both fixes: lock the Dock to the left or right edge and pick a preferred display, or turn the setting off. ([#44](https://github.com/blamechris/DockKeeper/issues/44))
- **`--diagnostics` no longer says pinning is unsupported when it works.** With “Displays have separate Spaces” on, the report claimed pinning was unsupported outright. That is only true of a bottom Dock — a left or right Dock pins normally in that mode — so a support report could send you to the disruptive fix (turning the setting off, which needs a logout and moves the menu bar) when the easy one would have worked. It now reports the verdict for your actual lock edge. ([#45](https://github.com/blamechris/DockKeeper/issues/45))
- **Two people sharing a Mac each get their own DockKeeper.** If you use fast user switching, DockKeeper could mistake another logged-in user's copy for a duplicate of your own and quietly decline to start — and because it lives only in the menu bar, there was nothing to see and no error to report: it simply never appeared. It now recognises another user's copy as theirs, not a duplicate of yours. `DockKeeper --diagnostics` also labels those, so a support report cannot point you at a process belonging to someone else. ([#30](https://github.com/blamechris/DockKeeper/issues/30))
- **`DockKeeper --diagnostics` could crash instead of printing a report.** A malformed value in DockKeeper's saved settings would take the command down rather than being reported, which is the worst possible moment to lose it — it is the one command we ask people to run when something is wrong. It now says the record looks corrupt and carries on.
- **`--diagnostics` no longer opens with a warning that reads like a fault.** Every support report began with a system line saying an internal settings name *"does not make sense and will not work"* — alarming, and the first thing anyone sends us. Nothing was ever wrong: the app and the command-line tool deliberately share one settings store, and the app was reaching it by a route macOS grumbles about but honours. It now takes the route macOS expects, reads and writes exactly the same settings, and prints nothing extra. ([#34](https://github.com/blamechris/DockKeeper/issues/34))

## [0.9.2] — 2026-08-18

Third public beta. Two reliability fixes: one for the opt-in screen-share feature, one for running DockKeeper twice by accident.

### Upgrading from 0.9.1 — quit DockKeeper first

**Quit DockKeeper before you install this version.** Click the menu-bar icon, choose *Quit DockKeeper*, then install 0.9.2 and open it.

macOS treats a replaced app bundle as a brand-new application, so opening 0.9.2 while 0.9.1 is still running starts a *second* copy — and 0.9.2's new single-instance guard correctly refuses to be that second copy. It exits immediately and silently: no alert, no error, and because DockKeeper has no Dock icon, nothing at all to see. The copy still in your menu bar is the old one, and it stays that way until you quit it or restart the Mac.

If it has already happened, the fix is the same and takes two seconds: quit DockKeeper from the menu, then open it again. To check whether an old copy is still resident, run `/Applications/DockKeeper.app/Contents/MacOS/DockKeeper --diagnostics` and read the `Other instances:` line — it names the pid and bundle path of every other live copy. (`Version:` reports the bundle you just ran, not the copy in your menu bar.) `Other instances: none` means no DockKeeper is running at all, so the next copy you open takes charge.

### Fixed

- **Your Dock no longer stays hidden after an interrupted screen share.** With "hide the Dock while screen sharing" on, DockKeeper turns macOS Dock auto-hide on for the length of a capture and off again afterwards. If it was force-quit, crashed, or was killed at logout while a share was running, auto-hide was left on — and DockKeeper, which never touches auto-hide for people who set it themselves, read it as yours and never put it back. It now remembers that it borrowed the setting, restores it at the next launch (within 7 days of the share), and says so in the menu. Quitting DockKeeper normally puts the Dock back on the way out, so most of the time you never see the repair happen. ([#29](https://github.com/blamechris/DockKeeper/issues/29))
- **A second copy of DockKeeper no longer starts.** Two copies both correcting the Dock is the worst way to run it, and it was easy to reach: dragging a new copy over a running one without quitting first was enough, because macOS treats the replacement as a different app. A second launch now exits before it starts an engine or touches the Dock, and the copy already running stays in charge. There is no alert — nothing appears to happen, which is the point.

### Added

- **Turn Off Dock Auto-Hide** — in the menu while your Dock is auto-hiding and the screen-share feature is on, and always available in Preferences ▸ Advanced. Use it if your Dock is still hiding itself after a screen share ended badly. It works even when there is nothing for DockKeeper to remember: a Dock left that way by an older version, or a preferences file that did not survive.
- `--diagnostics` gained two lines — `Other instances:` names every other live copy and its path, and `Screen-share:` says whether a Dock hide is currently outstanding. A menu-bar-only app has no Force Quit row to check, so a support report is the only place to look.
- `DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES=1` in the environment stands the single-instance guard down, for running two builds side by side from a terminal.
- README screenshots and badges, `SECURITY.md` (private vulnerability reporting), and contributor docs.

### Known beta limits

- The automatic Dock restore only fires within **7 days** of the interrupted share. Past that, DockKeeper assumes the setting is yours now and leaves it alone; **Turn Off Dock Auto-Hide** is the recovery, and it has no time limit.
- If a copy of DockKeeper is running but wedged, new launches now defer to it and appear to do nothing — and a menu-bar-only app has no Force Quit row. `DockKeeper --diagnostics` gives you its pid, or use `pkill -9 -x DockKeeper`.

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

[Unreleased]: https://github.com/blamechris/DockKeeper/compare/v0.9.2...HEAD
[0.9.2]: https://github.com/blamechris/DockKeeper/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/blamechris/DockKeeper/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/blamechris/DockKeeper/releases/tag/v0.9.0
