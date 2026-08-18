# DockKeeper — Hardware Matrix Results (M6)

| | |
|---|---|
| **Status** | Living record — session 1 complete |
| **Rig** | MacBook Pro built-in Retina (1728×1117) + Dell S2719DGF on external, **portrait** (1440×2560, rotation 90°), macOS 26.5 Apple Silicon |
| **Inputs** | [Test strategy §3](test-strategy.md) matrix, risk R-002/R-003 |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

## Session 1 — 2026-07-23 (first two-display session)

### Fingerprint capture on real hardware — CONFIRMED ✅

Every ADR-004 identity field populated for the external display:

| Field | Built-in | Dell S2719DGF |
|---|---|---|
| UUID | `37D8832A-2D66-02CA-B9F7-8F30A301B230` | `F4F6E6E4-69D2-40D1-A83C-6F346E264A9B` |
| vendor / model | 1552 / 41053 | 4268 / 53476 |
| serial | 4251086178 | **810177365 (non-zero!)** |
| localizedName | Built-in Retina Display | S2719DGF |
| isBuiltin / rotation | true / 0° | false / 90° |

Notable: this panel ships a real serial, so the 85-point `vendor+model+serial` rule applies to it — matching survives even a UUID change from a dock/adapter. The UUIDs above are the **stability baseline**: re-probe after replug (different port), reboot, and adapter changes and diff (open question #2, R-003).

### Main-display relocation mechanics — CONFIRMED ✅ (R-002, mechanism half)

The exact `MainDisplayPinner.liveApplyMain` origin math, run as a standalone probe:

| Step | Result |
|---|---|
| Pin (make Dell main) | `CGError=0`; `CGMainDisplayID` 1 → 2; origins `2:(0,0) 1:(-130,2560)` — relative arrangement preserved exactly, **portrait geometry handled** |
| Restore | `CGError=0`; main back to 1; origins byte-identical to the original `1:(0,0) 2:(130,-2560)` |

Conclusions: the public-API pin transaction **works on real multi-monitor hardware including a rotated display**, is arrangement-preserving, and is cleanly reversible. What remains INFERRED: that the **Dock itself** homes to the new main display — observable only with "Displays have separate Spaces" OFF (see gate below).

### Separate Spaces gate — CONFIRMED ON (macOS default)

`com.apple.spaces spans-displays` unset → separate Spaces ON. DockKeeper declines pinning in this mode by design (Decision 2A). **The definitive Dock-follow test requires:** System Settings ▸ Desktop & Dock → turn **off** "Displays have separate Spaces" → log out and back in.

## Matrix cells

| Cell | Result | Session |
|---|---|---|
| 2 displays: enumeration, UUIDs, fingerprints | ✅ CONFIRMED | 1 |
| Portrait/rotated external geometry in snapshots | ✅ CONFIRMED (bounds account for rotation) | 1 |
| Pin transaction + arrangement preservation + restore | ✅ CONFIRMED | 1 |
| **Left/right Dock follows main display (Spaces ON)** | ✅ CONFIRMED both directions — basis of ADR-009 | 1 |
| End-to-end pin through the app UI (Spaces ON, left Dock → Dell) | ✅ CONFIRMED by owner — "works and looks good" | 1 |
| Window migration on pin (coordinate re-base) | ✅ CONFIRMED — windows whose global coords land on the swapped displays move with the re-base (same as a System Settings primary change). Mitigation candidate: opt-in AX window restore (open question #11) | 1 |
| **Bottom Dock does NOT follow main (Spaces ON)** | ✅ CONFIRMED (stayed put through a main swap) | 1 |
| Pointer summon: shared bottom edge (stacked) / free left edge | ✅ CONFIRMED fails for both (owner-observed) | 1 |
| Leftmost-arrangement hypothesis for left Dock | ✅ falsified | 1 |
| killall-relocation candidate (bottom Dock, pointer parked on Dell) | ✅ falsified — restarted Dock returns to previous host | 2 |
| `CoreDockGetRect` signature + accuracy | ✅ CONFIRMED (963×78 at (382,1039), matches insets exactly) | 2 |
| **Dock follows main display (Spaces OFF)** | ⏳ pending Spaces-OFF logout (strongly corroborated by the Spaces-ON left-Dock result) | — |
| Live edge set + defaults write-through, 2 displays attached | ✅ CONFIRMED (re-ran the CoreDock spike with both displays: flicker-free set, write-through intact) | 1 |
| Edge lock survives display events (2-display, app running) | ⏳ | — |
| Unplug / replug drift presentation | ⏳ | — |
| **Screen-capture hide: `kill -9` mid-capture → relaunch restores auto-hide** (DK-FR-013 S5, issue #29) | ⏳ | — |
| **Screen-capture hide: relaunch *during* a live capture adopts, Dock does not flash** (DK-FR-013 S6) | ⏳ | — |
| **Screen-capture hide: logout with a hide held → auto-hide off after login** (DK-FR-013 S4) | ⏳ | — |
| **`applicationWillTerminate` / `SIGTERM` restore in the signed bundle** (DK-FR-013 S3) | ⏳ | — |
| UUID stability across ports/adapters/reboot | ⏳ baseline recorded | — |
| Sleep/wake with external connected | ⏳ | — |
| Mirroring / clamshell | ⏳ UNKNOWN behavior (open question #6) | — |
| Identical twin externals | n/a on this rig (different panels) | — |

---

## Session 3 run-sheet — the six cells that remain

Everything below is what stands between today and closing M6. Ordered by what
each cell *buys*: the first retires the project's top risk, the rest are
regression evidence. Work top-down and stop whenever you like — each cell is
independently recordable.

Rig assumed: the same MacBook Pro built-in + Dell S2719DGF (portrait) as
sessions 1–2, macOS 26.5.

### 1. Dock follows main display, separate Spaces OFF — **the v1.0.0 gate** (R-002)

This is the last unverified half of the project's founding claim, and the only
cell that gates the release. Everything else here is nice to have.

**Setup (needs a logout):**
1. System Settings ▸ Desktop & Dock → scroll to Mission Control → turn **off**
   "Displays have separate Spaces".
2. Log out and back in. The setting does not take effect until you do.
3. Confirm it took: `defaults read com.apple.spaces spans-displays` → `1`.

**Test, for each edge:**
1. `dockkeeper status` — note the current edge and preferred display.
2. Set the Dock to **bottom**. Pin the preferred display to the **Dell**.
3. Observe: does the Dock move to the Dell?
4. Repeat for **left**, then **right**.

**Why bottom matters most:** session 1 CONFIRMED that with Spaces **ON**, a
left/right Dock follows the main display but a **bottom** Dock does not — that
asymmetry is the entire basis of ADR-009. If bottom follows with Spaces OFF,
ADR-009's scope is a Spaces-ON limitation, not a fundamental one, and the
README's copy should say so. If bottom still does not follow, that is a genuine
macOS constraint and DK-FR-002 stays best-effort for bottom permanently.

Record: pass/fail per edge, and whether the menu bar moved with it.

**Afterwards:** turn separate Spaces back ON and log in again — it is the macOS
default and the mode most users run.

### 2. Edge lock survives display events, app running, 2 displays

With the app enabled and an edge locked, perform each and check the edge is
restored: unplug the Dell · replug · sleep/wake (close the lid, reopen) ·
change the Dell's resolution · change arrangement in Settings · `killall Dock`.

Record: restored / not, and roughly how long it took. The latency number feeds
ADR-005's poll-interval evidence — a drift caught only by the 30 s poll rather
than an event is worth noting specifically.

### 3. Unplug / replug drift presentation

Same as above but watching the **menu bar UI**, not just the outcome: does the
state read `Degraded` or `Error` at any point, and is what it says true? This is
the honesty check — a wrong `Degraded` is a bug even if the Dock ends up right.

### 4. UUID stability across ports, adapters, reboot (R-003)

Baseline from session 1: Dell UUID `F4F6E6E4-69D2-40D1-A83C-6F346E264A9B`.

Re-probe after each of: a different physical port · a dock or adapter if you
have one · a full reboot. Diff each against the baseline.

If the UUID changes, that is the case ADR-004's scored matching exists for —
check the app still recognises the display (it should, via
`vendor+model+serial`, since this panel ships a real serial). A UUID change with
successful re-match is a **pass**, and closes open question #2.

### 5. Sleep/wake with external connected

Lid close and reopen, plus an idle sleep if you can wait one out. Check the edge
and the pin both survive, and that no oscillation is visible on wake.

### 6. Mirroring / clamshell — currently UNKNOWN (open question #6)

Turn on display mirroring, then try clamshell (lid shut, external only). There
is no expected result recorded for these — the goal is to find out what happens
and write it down. If DockKeeper does something wrong or confusing here, that
is a finding worth an issue rather than a failure.

### Recording

Append results to the "Matrix cells" table above, one row per cell, with macOS
version and hardware path. Anything surprising goes in the risk register.
Cell 1 additionally updates R-002 and, if bottom follows, ADR-009's scope.
