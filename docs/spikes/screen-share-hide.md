# Spike: Hide the Dock during screen sharing (parity gap G5)

**Date:** 2026-07-23 · **Status:** Findings complete; needs an owner decision (ADR) before building · **Drives:** parity gap G5, a future DK-FR

## Question

DockLock Lite hides the Dock during screen sharing / meetings. Can DockKeeper
(a) reliably **detect** a screen-capture/recording session, and (b) hide the
Dock while it lasts, then restore — within the reliability + permission bar?

## Findings (on-rig, 2026-07-23)

### (a) Detection

| Signal | API | Result |
|---|---|---|
| `CGSIsScreenWatcherPresent` | private (SkyLight), resolve + read | ✓ resolves, returns `Bool` (false with nothing capturing). This is the **screen-capture** signal — what "someone is screen-sharing/recording" actually means. CONFIRMED resolves; true-case not yet exercised (start a capture to confirm). |
| `SLSIsScreenWatcherPresent` | private (SkyLight) | ✓ resolves (SLS alias of the same). |
| Camera "running somewhere" | **public** `CMIODevicePropertyDeviceIsRunningSomewhere` | ✓ works, no permission, no TCC prompt — but this detects a **camera** (video call), NOT screen capture. Different event; useful only if the feature is reframed as "hide during video calls." |

**Key point:** true screen-share detection has no public API — the reliable
signal is the private `CGSIsScreenWatcherPresent`. So **G5 is a private-API
decision**, like ADR-003 was for CoreDock. The public camera signal is a
*different* feature (video-call presence), not a substitute.

### (b) Hide mechanism + a real gotcha

- Toggling Dock auto-hide via `CoreDockSetAutoHideEnabled(true/false)` works
  (symbols already CONFIRMED). Read-back via `CoreDockGetAutoHideEnabled`
  confirmed the writes.
- **Gotcha (CONFIRMED):** with auto-hide ON, the `NSScreen.visibleFrame`
  bottom-inset host detector did **not** change (stayed 78) in-process — i.e.
  our primary Dock-host sensor is **blinded while the Dock is auto-hidden**.
  Any G5 implementation that toggles auto-hide must switch host detection to
  `CoreDockGetRect` (verified in the separate-spaces spike) or suspend
  detection while hiding — otherwise pinning logic reads stale geometry.
- Restoring auto-hide to its prior value cleanly returned the state.

## Recommendation

Defer to an **owner decision (new ADR)**, because:

1. It requires **another private API** (`CGSIsScreenWatcherPresent`) — the
   kickoff's rule-7 bar. It degrades safely (symbol missing → feature simply
   unavailable, like CoreDock's fallback), but it's an explicit trade to sign.
2. Scope question for the owner: "hide during **screen capture**" (private
   flag) vs. "hide during **video calls**" (public camera signal) vs. both.
   They are different triggers; DockLock's copy says "screen sharing/meetings"
   — ambiguous.
3. Interaction with pinning must be designed: DockKeeper must **not** count its
   own auto-hide toggle as drift, and must not fight a user who set auto-hide
   themselves (remember the prior value; only toggle if we changed it; use
   `CoreDockGetRect` for detection while hidden).

Not building it in this spike — findings + the decision are the deliverable
(a spike succeeds even when it defers). Candidate ordering unchanged: G1
before G5.

## Next steps (when G5 is greenlit)

- [ ] Exercise the true-case: start a screen recording, confirm the watcher
      flag flips; measure latency and whether it fires for QuickTime, Zoom,
      Teams, Screen Sharing.app.
- [ ] Decide scope (screen-capture / camera / both) → ADR.
- [ ] Design the auto-hide-vs-pinning interaction (prior-value memory,
      CoreDockGetRect detection, echo/drift suppression).
