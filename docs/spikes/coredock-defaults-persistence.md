# Spike: Does a live CoreDock set persist across a Dock restart?

**Date:** 2026-07-22 · **Status:** Complete · **Answers:** TDD open question #3, risk R-011

## Question

`CoreDockSetOrientationAndPinning` moves the Dock live. If the Dock process later restarts (`killall Dock`, crash, macOS), it re-reads `com.apple.dock` defaults — so: does a live CoreDock set **write through** to that defaults domain, or would a restart silently revert the edge?

## Experimental setup

On-device (macOS 26.5, Apple Silicon), a standalone Swift script (AppKit loaded for symbol resolution):

1. Read live orientation via `CoreDockGetOrientationAndPinning` and `defaults read com.apple.dock orientation`.
2. Set a different edge via `CoreDockSetOrientationAndPinning`.
3. Re-read both after 1.5 s; restore the original edge; re-read both again.

## Result — CONFIRMED: CoreDock writes through to defaults

| Step | Live orientation | `defaults read com.apple.dock orientation` |
|---|---|---|
| Before | 2 (bottom) | *(key unset)* |
| After `set(3)` | 3 (left) | `left` |
| After `set(2)` restore | 2 (bottom) | `bottom` |

The defaults key was not even set before the experiment; the first CoreDock set created it and every subsequent set updated it within the 1.5 s observation window.

## Consequences

- **A Dock restart is benign**: the restarted Dock re-reads exactly the edge we last set. No `killall` needed to verify further — the defaults-on-launch behavior is standard.
- **No defaults mirroring is required** in `DockController` (the TDD §8.5 contingency is dead code we never have to write). Risk **R-011 → Closed**.
- **Dock-restart detection is deprioritized**: a restart cannot revert the edge, so the dedicated detection mechanism (TDD §8.1, mechanism UNKNOWN) is no longer needed for correctness; the 30 s poll covers any residual gap. Remove it from the M3 critical path.
- Permission note: the write-through lands in another app's defaults domain, performed by macOS's own API — DockKeeper still never writes `com.apple.dock` directly except on the explicit fallback path.

## Failure cases / uncertainty

- Single observation on one macOS version; the release-checklist CoreDock smoke test (R-004) re-verifies per macOS release.
- Whether the write-through is synchronous or eventually-consistent within `cfprefsd` is unmeasured (observed ≤1.5 s); irrelevant to correctness since restarts re-read at launch time.

## CPU / memory / permissions

Two C calls + two `defaults` spawns; no permission prompts; no Accessibility.
