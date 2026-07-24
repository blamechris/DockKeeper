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
| **Bottom Dock does NOT follow main (Spaces ON)** | ✅ CONFIRMED (stayed put through a main swap) | 1 |
| Pointer summon: shared bottom edge (stacked) / free left edge | ✅ CONFIRMED fails for both (owner-observed) | 1 |
| Leftmost-arrangement hypothesis for left Dock | ✅ falsified | 1 |
| **Dock follows main display (Spaces OFF)** | ⏳ pending Spaces-OFF logout (strongly corroborated by the Spaces-ON left-Dock result) | — |
| Live edge set + defaults write-through, 2 displays attached | ✅ CONFIRMED (re-ran the CoreDock spike with both displays: flicker-free set, write-through intact) | 1 |
| Edge lock survives display events (2-display, app running) | ⏳ | — |
| Unplug / replug drift presentation | ⏳ | — |
| UUID stability across ports/adapters/reboot | ⏳ baseline recorded | — |
| Sleep/wake with external connected | ⏳ | — |
| Mirroring / clamshell | ⏳ UNKNOWN behavior (open question #6) | — |
| Identical twin externals | n/a on this rig (different panels) | — |
