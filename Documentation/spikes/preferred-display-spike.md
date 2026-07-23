# Core Spike: Preferred-Display Pinning

**Date:** 2026-07-22 · **Status:** Investigation complete, recommendation below · **Author:** blamechris

## Question

Can DockKeeper reliably keep the Dock on a **user-chosen monitor** (the "Preferred Display" requirement), and what mechanism should we build the architecture around?

## TL;DR

- **Edge locking is solved.** The private `CoreDock` API repositions the Dock (bottom/left/right) live and flicker-free. Verified working on-device.
- **Display pinning has no direct API — public or private.** `CoreDock` controls edge + start/mid/end anchoring only; it has **no display parameter**.
- The Dock's "home" is the **main display** (the one with the menu bar). The only *public-API* route to move it is to make the target display the main display via `CGConfigureDisplayOrigin` — **but that also moves the menu bar** and rearranges display origins.
- Whether pinning is even meaningful depends on the **"Displays have separate Spaces"** system setting, which is **ON by default**. With it on, the Dock follows the pointer/active display per-Space, so a hard "pin" partly fights the OS.
- **Recommendation:** ship edge-lock in v1.0 as the reliable core; model display-pinning behind a `DisplayPinner` strategy with a public-API `MainDisplayPinner` (best-effort, clearly communicated), and defer a private-API SkyLight approach to a later, opt-in experiment.

## Evidence gathered on-device (macOS 26.5, Apple Silicon)

| Probe | Result |
|---|---|
| `CoreDock` symbols via `dlsym(RTLD_DEFAULT)` | ✓ Get/Set OrientationAndPinning, Get/Set AutoHideEnabled all resolve |
| Live read | `orientation=2 (bottom) pinning=2 (middle)` — matches actual Dock |
| **Symbol availability precondition** | Symbols resolve **only when AppKit/HIServices is loaded**. A pure-CoreGraphics process returns `nil`. Our CLI works today because it links AppKit transitively via `DockKeeperCore`. |
| `CGGetActiveDisplayList` / UUID | ✓ Enumeration + stable UUID (`CGDisplayCreateUUIDFromDisplayID`) work |
| `CGBeginDisplayConfiguration` path | ✓ Available (probed + cancelled, no changes committed) |
| `com.apple.spaces spans-displays` | Not set → **separate Spaces ON** (macOS default) |

> ⚠️ **Test-rig limitation:** the dev machine has a **single built-in display**. API surface and edge-lock are verified end-to-end; multi-monitor *pinning behavior* (does relocating main display actually move the Dock? how does drift present on unplug/replug?) is **reasoned, not yet observed**. Needs a 2-monitor rig to confirm before we trust it.

## Mechanism options for display pinning

1. **Make target display the main display** — `CGConfigureDisplayOrigin(target, 0, 0)` inside a `CGDisplayConfiguration` transaction. *Public API.*
   - ✅ Supported, reversible, no private symbols.
   - ⚠️ Moves the **menu bar** too; rewrites all display origins. Intrusive as a default.
2. **Toggle "Displays have separate Spaces" off** to make the Dock deterministically live on the main display.
   - ⚠️ Requires **logout** to take effect — unacceptable UX. Detect and inform, don't auto-toggle.
3. **Cursor warp** (`CGWarpMouseCursorPosition` to the target edge) to summon the Dock there.
   - ❌ Hijacks the pointer; can't "hold" the Dock. Reject.
4. **Private SkyLight / CGS dock APIs** (what the Dock itself uses).
   - Potentially the only way to pin *without* moving the menu bar, but higher fragility across OS versions. Defer to an opt-in experiment behind the same strategy interface.

## Recommended architecture

Keep **edge control** and **display pinning** as separate, independently-testable concerns:

```
DockController        // edge lock via CoreDock (PROVEN) — always on
  └─ orientation/pinning only

DisplayPinner (protocol)               // NEW abstraction for "which monitor"
  ├─ MainDisplayPinner   (v1.0)        // public CG API; best-effort; documents the menu-bar tradeoff
  └─ SkyLightPinner      (later, opt-in, experimental)

SystemState
  └─ separateSpacesEnabled: Bool       // read com.apple.spaces; gates pinning UX + warnings
```

- **v1.0 scope:** edge lock is the headline, always-reliable feature. Preferred Display ships as **best-effort**, gated on detecting the Spaces setting, with honest UI copy ("On macOS, the Dock lives on your main display"). No private display APIs in v1.0.
- **Harden now (cheap, spike-validated):** have `CoreDock.swift` explicitly `dlopen` HIServices instead of relying on transitive AppKit linkage — removes a hidden dependency on link order for the CLI.

## Decisions (2026-07-22)

Resolved with the project owner. DockKeeper is a free replacement for an
expensive closed-source app — the bar is "reliable and honest," not "beat every
macOS limitation."

1. **Use the safe public-API pinner** (`MainDisplayPinner`, make the target the
   main display). The menu bar moving along with the Dock is an **accepted,
   documented consequence** — not a blocker. No private SkyLight APIs.
2. **Option A** — when "Displays have separate Spaces" is ON (the default), we
   do **not** fight the OS. Pinning reports `unsupportedSeparateSpaces`; the UI
   explains it and edge-locking continues to work. No private path.
3. **Ship the reliable 90%.** v1.0 = always-on edge-lock + best-effort Preferred
   Display via the public API. Robust pinning in every configuration is
   explicitly out of scope; keep it simple.

## Superseded open questions

_(kept for history — resolved above)_

1. ~~Is moving the menu bar acceptable?~~ → Yes, documented consequence.
2. ~~Treat "separate Spaces ON" as unsupported, or build the private path?~~ → Unsupported + inform.
3. ~~Edge-lock-only v1.0 with best-effort pinning?~~ → Yes.

## Next steps

- Get a **2-monitor rig** to confirm main-display relocation moves the Dock and to characterize drift on unplug/replug/resolution-change.
- Prototype `MainDisplayPinner` behind the protocol; measure how intrusive the menu-bar move feels.
- Spike the SkyLight path read-only (identify the symbols the Dock uses) to size the private-API option without committing to it.
