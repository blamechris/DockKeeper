# Spike: Pinning the Dock in separate-Spaces mode (parity workstream)

**Date started:** 2026-07-23 · **Status:** In progress · **Drives:** ADR-008, implementation-plan M8

## Question

With "Displays have separate Spaces" **ON** (the macOS default — and the only
mode DockLock Lite/Plus supports), the Dock hops to whichever display the user
summons it on. Can DockKeeper (a) detect which display currently hosts the
Dock, and (b) reliably return it to the preferred display — without
oscillation, and with the smallest possible permission footprint?

Owner directive 2026-07-23: full DockLock replacement — this mode must
eventually be covered ([product-investigation §3](../product-investigation.md)).

## Findings so far (2026-07-23, on the 2-display rig, separate Spaces ON)

### (a) Detection — CONFIRMED with public API, zero permissions

`NSScreen.visibleFrame` excludes the menu bar *and* the Dock. Observed:

| Display | top inset | bottom inset | Verdict |
|---|---|---|---|
| Built-in Retina | 33 (menu bar) | **78** | **Dock host** |
| Dell S2719DGF (portrait) | 30 (menu bar) | 0 | not host |

A per-display "bottom inset beyond ~4 pt" test identifies the Dock host with
no private API and no Accessibility. Wired to the existing
`didChangeScreenParametersNotification` (which INFERRED fires on Dock
migration — verify next), this is the sensor for the whole feature.
Left/right-edge insets would detect side-Dock hosts the same way.

### (b) Recovery — no direct private setter under the obvious names

Resolve-only `dlsym` sweep (nothing invoked): every known `CoreDock*` symbol
resolves (orientation/pinning/autohide/rect/tilesize/magnification/workspaces),
plus `CGSMainConnectionID`/`SLSMainConnectionID` — but **none** of
`CoreDock{Get,Set}DisplayID`, `CoreDock{Get,Set}PreferredDisplay`,
`CGS{Get,Set}DockDisplay`, `CGS/SLS*DockRect` exist. CONFIRMED (this macOS).
So there is no obvious "set Dock display" call; recovery candidates, in
preference order:

1. **Re-summon via pointer gesture at the preferred display's Dock edge.**
   Almost certainly DockLock Lite/Plus's mechanism (INFERRED — it matches
   their Accessibility requirement and their bottom-edge-only limitation).
   Sub-questions: does `CGWarpMouseCursorPosition` alone (no permission)
   trigger the summon, or does it need synthesized move events
   (`CGEventPost` → Accessibility/TCC)? Correction is rare and event-driven,
   so a momentary pointer round-trip differs materially from the *continuous*
   cursor-warping the original spike rejected — but the bar stays: no visible
   jank, restore pointer exactly, never fight the user's hand.
2. **`killall Dock` with the pointer parked on the preferred display** — does
   a restarted Dock appear on the pointer's display, the previous host, or
   the main display? UNKNOWN; if pointer-follows, this is a crude fallback
   (visible restart — degraded-quality tier only).
3. **Deeper SkyLight enumeration** — dump `SkyLight`/`HIServices` export
   tables for dock-display-related symbols beyond the guessed names (read
   `nm`/`dyld_info` output; resolve-only probes). Higher fragility; only if
   1–2 disappoint (Decision 1's fragility concern still applies).
4. `CoreDockGetRect` (resolves ✓) — likely returns the Dock's global rect;
   careful read-only call would corroborate (a) and give exact geometry.
   Signature must be verified before calling (crash risk contained to spike).

## Field observations — 2026-07-23, stacked-portrait rig

**The summon gesture fails on a shared bottom edge.** With the Dell portrait
display arranged **directly above** the laptop, its bottom edge is a
pass-through boundary: pushing the pointer down crosses into the laptop
display instead of dwelling, and holding at the Dell's bottom edge did **not**
migrate the Dock (owner-observed; DockLock confirmed not running — clean
observation, CONFIRMED for this arrangement). Whether any harder push can
summon on a shared edge is UNKNOWN → side-by-side rearrangement test queued.

**The competitor knows.** DockLock Lite's local preferences (black-box read of
the owner's legitimately installed copy, v1.4.8) contain
`warn_incompatible_display = 1` — it ships an "incompatible display" warning
concept — plus `control_mode`/`lock_position` flags and per-workspace rule
storage. INFERRED: bottom-only summon-based locking is known-fragile on
topologies like this one.

**Design implication (important).** A re-summon mechanism must be
**edge-aware**: on stacked arrangements the bottom edge of the upper display
may be unusable, while its left/right edges are free. DockKeeper's any-edge
support isn't just a differentiator here — a left/right Dock may be the *only*
edge that can host/summon on the upper display of a stacked pair. Test queued:
set Dock edge to left (CLI), attempt summon at the Dell's free left edge.

## Next steps

- [x] ~~Interactive: owner summons the Dock to the Dell (bottom edge)~~ —
      **failed on this topology** (shared edge; see field observations).
- [ ] **Side-by-side test**: temporarily rearrange Dell beside laptop
      (programmatic, reversible), retry bottom summon on the freed edge.
- [ ] **Left-edge test**: `dockkeeper lock left`, attempt summon at the Dell's
      free left edge in the current stacked arrangement.
- [ ] Careful `CoreDockGetRect` read-only call (probe script only).
- [ ] Warp-only summon experiment; if inert, event-synthesis experiment (needs
      a one-time Accessibility grant **for the dev machine only** — a product
      permission decision belongs to ADR-009).
- [ ] `killall`-relocation observation (candidate 2).
- [ ] Findings → ADR-009 (mechanism + permission posture), then
      `SeparateSpacesPinner` behind the existing `DisplayPinner` protocol.

## Permission-footprint note

Detection needs nothing. If recovery ends up requiring Accessibility, it would
be **opt-in for this mode only** — the v1 zero-permission story stays true for
edge lock and Spaces-off pinning; the kickoff's full permission model
(explanation before prompt, denial UX, revocation) would return with it
(TDD §10 anticipated exactly this).
