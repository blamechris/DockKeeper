# Spike: Pinning the Dock in separate-Spaces mode (parity workstream)

**Date started:** 2026-07-23 · **Status:** Core question RESOLVED same day (→ ADR-009 shipped); bottom-mode (G1) track open — probe written 2026-08-27, awaiting a run on a free-bottom-edge rig · **Drives:** ADR-008/009, implementation-plan M8

## Resolution (2026-07-23, hardware-confirmed)

| Hypothesis | Result |
|---|---|
| H1: pointer summon at the Dell's free **left** edge migrates a left Dock | ✗ no migration (owner-observed) |
| H2: a left Dock lives on the **leftmost** display of the arrangement | ✗ falsified (Dell moved leftmost; Dock stayed) |
| H3: a left Dock follows the **main** display | **✓ CONFIRMED both directions** (main → Dell: Dock followed; restore: followed back) |
| H4: a bottom Dock also follows main | ✗ CONFIRMED it does **not** (stayed on laptop when Dell became main) |

**Conclusion:** separate-Spaces mode is edge-asymmetric. Left/right Docks home to the main display → the shipped `MainDisplayPinner` pins them in this mode with no new API and no permissions (and no menu-bar cost — per-display menu bars). Bottom Docks are per-display pointer toys → still declined honestly (ADR-009). The only remaining research track is a bottom-mode summon mechanism (candidates below, deprioritized).

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

## Bottom-mode (G1) probe results — 2026-07-23, second session

| Candidate / probe | Result |
|---|---|
| **killall-relocation** (park pointer on Dell → restart Dock) | ✗ **FALSIFIED** — the restarted Dock reappeared on the previous host (laptop), not the pointer's display. CONFIRMED on-rig. |
| **`CoreDockGetRect(CGRect*)`** (signature verified by careful call) | ✓ **works** — returned the Dock's exact global rect (origin (382,1039), 963×78 = centered, bottom of laptop, height == the 78 pt visibleFrame inset). A second, corroborating host-detection signal. CONFIRMED. |

**Sharpened G1 scope (INFERRED, important):** on stacked arrangements where
the target display's bottom edge is shared, even a *real* pointer cannot
summon the Dock there — so any summon-based mechanism (synthesized events
included) is likely impossible on such topologies, which is presumably exactly
why DockLock ships `warn_incompatible_display`. G1 should therefore target
only topologies where the preferred display has a **free bottom edge**
(detectable from pure geometry), with honest copy otherwise ("that display's
bottom edge borders another screen — use a left/right Dock to pin there").

## Free-bottom-edge summon probe (G1) — queued, not yet run

**Topology unblock (2026-08-27).** The 2026-07-23 sessions ran on the stacked
portrait rig, where the Dell's bottom edge is shared and *no* summon can
succeed — so they could not distinguish "the mechanism doesn't work" from "this
arrangement forbids it". An owner rig is now available with the laptop
(primary) **left** and the external monitor **right**: side-by-side, so **both
displays have a free bottom edge**. That is the precondition this probe needs,
and it is an entirely ordinary arrangement, so a result here generalizes.

**The question, precisely.** Candidate 1 (pointer re-summon) splits into a
cheap variant and an expensive one, and the difference decides DockKeeper's
permission story for the whole feature:

| Variant | API | Permission | If it works |
|---|---|---|---|
| **Warp-only** | `CGWarpMouseCursorPosition` | **none** | G1 ships zero-permission — *better* than DockLock, which requires Accessibility |
| Synthesized events | `CGEventPost` | Accessibility (TCC) | G1 matches DockLock; needs an opt-in permission decision in ADR-009 |

The probe tries the free one first and escalates only within the free tier
(single warp → repeated nudges). It never posts a synthetic event, so it can
be run with no permission grant and no TCC prompt.

**What it does not touch.** No Dock preference is written, no `killall`, no
display reconfiguration. The only mutation is the pointer position, saved
before and restored after.

```swift
// ssprobe.swift — swiftc -O ssprobe.swift -o ssprobe
// Read-only except for a transient pointer warp, which is restored on exit.
import AppKit
import CoreGraphics

// --- Detection (spike §(a), corroborated by CoreDockGetRect) --------------

struct ScreenRow {
    let index: Int, name: String
    let frame: CGRect, bottomInset: CGFloat
    var hostsDock: Bool { bottomInset > 4 }   // ~78pt observed on the host, 0 elsewhere
}

func rows() -> [ScreenRow] {
    NSScreen.screens.enumerated().map { i, s in
        ScreenRow(index: i, name: s.localizedName, frame: s.frame,
                  bottomInset: s.visibleFrame.minY - s.frame.minY)
    }
}
func dockHostIndex() -> Int? { rows().first(where: { $0.hostsDock })?.index }

/// Second, independent signal. Signature verified by careful call, 2026-07-23.
func coreDockRect() -> CGRect? {
    guard let h = dlopen("/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock",
                         RTLD_LAZY), let sym = dlsym(h, "CoreDockGetRect") else { return nil }
    typealias Fn = @convention(c) (UnsafeMutablePointer<CGRect>) -> Void
    var r = CGRect.zero
    unsafeBitCast(sym, to: Fn.self)(&r)
    return r
}

// --- Cocoa (origin bottom-left, +Y up) → CG global (top-left, +Y down) ----
// NSScreen.screens[0] is the primary display, whose Cocoa origin is (0,0).

let flipHeight = NSScreen.screens[0].frame.maxY
func toCG(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: flipHeight - p.y) }

// --- Probe ---------------------------------------------------------------

// Establish a window-server connection and let AppKit refresh `NSScreen`
// between reads — without this the post-summon re-read can return cached
// geometry and manufacture a false negative, which is the one failure mode
// this probe must not have.
_ = NSApplication.shared

guard NSScreen.screens.count > 1 else {
    print("REFUSE: needs >= 2 displays; found \(NSScreen.screens.count)"); exit(2)
}
guard CommandLine.arguments.count == 2, let target = Int(CommandLine.arguments[1]),
      NSScreen.screens.indices.contains(target) else {
    print("usage: ssprobe <target-screen-index>")
    for r in rows() {
        print("  [\(r.index)] \(r.name)  frame=\(r.frame)  bottomInset=\(r.bottomInset)"
            + (r.hostsDock ? "  <- Dock host" : ""))
    }
    exit(2)
}

let before = dockHostIndex()
print("Dock host before: \(before.map(String.init) ?? "none detected")")
print("CoreDockGetRect:  \(coreDockRect().map(String.init(describing:)) ?? "unavailable")")
guard before != target else {
    print("REFUSE: the Dock is already on screen \(target); nothing to summon"); exit(2)
}

// `exit()` does NOT unwind `defer`, so the restore is explicit on every path.
let restore = CGEvent(source: nil)?.location
func finish(_ code: Int32, _ message: String) -> Never {
    if let restore { CGWarpMouseCursorPosition(restore) }
    print(message)
    exit(code)
}

let f = NSScreen.screens[target].frame
// Bottom-centre of the target, one row inside it.
let bottom = toCG(CGPoint(x: f.midX, y: f.minY))
let edge = CGPoint(x: bottom.x, y: bottom.y - 1)

func settled(_ seconds: Double) -> Int? {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if let h = dockHostIndex(), h != before { return h }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return dockHostIndex()
}

// Stage 1 — a single warp. The cheapest thing that could possibly work.
CGWarpMouseCursorPosition(edge)
if let h = settled(2.0), h == target {
    finish(0, "RESULT: stage 1 (single warp) SUMMONED the Dock to \(target) — zero-permission path viable")
}

// Stage 2 — repeated warps along the edge. Still no synthetic events; this
// tests whether the summon needs apparent *motion* rather than mere position.
for i in 0..<40 {
    CGWarpMouseCursorPosition(CGPoint(x: edge.x + CGFloat(i % 2 == 0 ? -3 : 3), y: edge.y))
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
if let h = settled(2.0), h == target {
    finish(0, "RESULT: stage 2 (repeated warps) SUMMONED the Dock to \(target) — zero-permission path viable")
}

finish(1, """
        RESULT: warp-only did NOT summon (host still \(dockHostIndex().map(String.init) ?? "none")).
                Next: synthesized-event variant (CGEventPost) — needs an Accessibility grant.
        """)
```

**Run recipe** (from a two-display side-by-side rig, Dock at bottom, separate
Spaces ON, Dock **not** auto-hidden — auto-hide zeroes the inset and breaks
detection):

```sh
swiftc -O ssprobe.swift -o ssprobe
./ssprobe                 # lists screens and marks the current Dock host
./ssprobe 1               # attempt to summon to screen index 1
```

Repeat each stage at least 5× in both directions (laptop → external, external →
laptop) before recording a verdict: a single negative could be a suppression
artifact (`CGWarpMouseCursorPosition` suppresses local mouse deltas for a
short interval after the warp, which is itself a candidate explanation for a
stage-1 failure and a reason stage 2 might differ).

**How to read the outcome.**

- **Stage 1 or 2 succeeds** → G1 is viable *and* zero-permission. Write it up,
  then ADR-009 gains a mechanism section and `SeparateSpacesPinner` lands
  behind the existing `DisplayPinner` protocol. Still bottom-only, still
  needs the free-bottom-edge geometry check and honest copy otherwise.
- **Both fail** → the summon needs synthetic events. That is a *product
  permission decision*, not a spike outcome: it would make G1 the second
  feature to require Accessibility, and it would put DockKeeper at parity
  with DockLock rather than ahead of it.

## Next steps

- [x] ~~Interactive: owner summons the Dock to the Dell (bottom edge)~~ —
      **failed on this topology** (shared edge; see field observations).
- [x] ~~killall-relocation candidate~~ — falsified (table above).
- [x] ~~`CoreDockGetRect` read-only call~~ — verified; usable as a detector.
- [x] ~~**Side-by-side test**: temporarily rearrange Dell beside laptop~~ —
      **superseded 2026-08-27**: an owner rig already has laptop-left /
      external-right, so both bottom edges are free. No rearrangement needed,
      and the observation is on a natural arrangement rather than a contrived
      one.
- [ ] **Run `ssprobe` (above) on that rig, both directions, 5× per stage.**
      Decides whether the summon is zero-permission (warp) or Accessibility-
      gated (`CGEventPost`) — the single highest-value unknown in this spike,
      because it decides whether G1 beats DockLock or merely matches it.
      Probe compiles clean and refuses safely on a 1-display machine (verified
      2026-08-27); the summon path itself is **unrun**.
- [ ] Only if warp-only fails: synthesized-event variant (needs a one-time
      dev-machine Accessibility grant; a *product* permission decision belongs
      to ADR-009, not to this spike).
- [ ] SkyLight/HIServices export enumeration for dock-display symbols beyond
      the guessed names (resolve-only).
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
