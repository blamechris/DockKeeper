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

### (a) Detection — ⚠️ **RETRACTED 2026-08-27** (was: CONFIRMED with public API, zero permissions)

> **This section's claim is narrower than it reads.** The `visibleFrame`
> bottom-inset test is correct on a **cold read**, but it did not update once
> within a long-lived process across a session in which the Dock migrated five
> times. `CoreDockGetRect` behaves the same way. Since DockKeeper is a
> long-running app, "correct at launch" is not the property the feature needs.
> See **"Sensor validation"** below for the measurements and for the sensor
> that does update live. The original text is kept for the record.

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
    let bottomEdgeFree: Bool
    var hostsDock: Bool { bottomInset > 4 }   // ~78pt observed on the host, 0 elsewhere
}

/// A display's bottom edge is *blocked* when another display sits flush
/// beneath it with overlapping x — the pointer then crosses into that display
/// instead of dwelling, and the summon cannot fire. Confirmed 2026-07-23 on the
/// stacked portrait rig: not even a real hand could summon there. This is the
/// pure-geometry precondition G1 has to check before it promises anything.
/// Identified by index, not by frame: mirrored displays share a frame, and an
/// identity test that cannot tell them apart is the wrong primitive for a
/// check the feature will rely on.
func bottomEdgeFree(_ i: Int, among all: [CGRect]) -> Bool {
    let f = all[i]
    return !all.indices.contains { j in
        j != i
            && abs(all[j].maxY - f.minY) < 1          // flush beneath
            && min(all[j].maxX, f.maxX) - max(all[j].minX, f.minX) > 0   // x overlap
    }
}

func rows() -> [ScreenRow] {
    let frames = NSScreen.screens.map(\.frame)
    return NSScreen.screens.enumerated().map { i, s in
        ScreenRow(index: i, name: s.localizedName, frame: s.frame,
                  bottomInset: s.visibleFrame.minY - s.frame.minY,
                  bottomEdgeFree: bottomEdgeFree(i, among: frames))
    }
}
/// Authoritative host detection — sensor C, the only one that tracks migration
/// (see "Sensor validation"). `hostsDock` above is the *inset* test and is kept
/// only to show, in the listing, that it disagrees.
func dockHostIndex() -> Int? {
    guard let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] else { return nil }
    guard let win = l.filter({ ($0[kCGWindowOwnerName as String] as? String) == "Dock" })
        .compactMap({ $0[kCGWindowBounds as String] as? [String: CGFloat] })
        .map({ CGRect(x: $0["X"] ?? 0, y: $0["Y"] ?? 0,
                      width: $0["Width"] ?? 0, height: $0["Height"] ?? 0) })
        .max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
    var n: UInt32 = 0; CGGetActiveDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n)); CGGetActiveDisplayList(n, &ids, &n)
    for (i, id) in ids.enumerated()
        where CGDisplayBounds(id).intersects(win) && CGDisplayBounds(id).width == win.width { return i }
    return nil
}

/// Second, independent signal. Signature verified by careful call, 2026-07-23.
func coreDockRect() -> CGRect? {
    // Resolve exactly as `CoreDock.swift` does. There is no
    // CoreDock.framework on disk — the symbols live in the shared dyld cache,
    // reached via ApplicationServices + RTLD_DEFAULT. The first draft of this
    // probe guessed a PrivateFrameworks path, silently returned nil, and threw
    // away the corroborating signal on the one run that mattered.
    _ = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
               RTLD_LAZY)
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockGetRect")
    else { return nil }
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
            + (r.bottomEdgeFree ? "  bottom-edge:FREE" : "  bottom-edge:BLOCKED")
            + (r.hostsDock ? "  <- Dock host" : ""))
    }
    print(rows().allSatisfy(\.bottomEdgeFree)
        ? "TOPOLOGY: qualifies — every display has a free bottom edge."
        : "TOPOLOGY: at least one display's bottom edge is blocked; a summon cannot "
          + "fire there. Rearrange side-by-side before drawing any conclusion.")
    exit(2)
}

let before = dockHostIndex()
print("Dock host before: \(before.map(String.init) ?? "none detected")")
print("CoreDockGetRect:  \(coreDockRect().map(String.init(describing:)) ?? "unavailable")")
guard before != target else {
    print("REFUSE: the Dock is already on screen \(target); nothing to summon"); exit(2)
}
// Without this the probe can only produce an uninterpretable negative — which
// is exactly what the two 2026-07-23 sessions produced.
guard rows()[target].bottomEdgeFree else {
    print("REFUSE: screen \(target)'s bottom edge is blocked by a display flush "
        + "beneath it. No summon can fire there, so a negative would say nothing "
        + "about the mechanism. Rearrange side-by-side and re-run."); exit(2)
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

**Geometry check confirmed against hardware (2026-08-27).** Run on the dev rig
with a DELL G3223Q attached, the detector classified the arrangement
unprompted:

```
[0] Built-in Retina Display  frame=(0.0, 0.0, 1728.0, 1117.0)      bottomInset=78.0  bottom-edge:FREE     <- Dock host
[1] DELL G3223Q              frame=(-919.0, 1117.0, 3840.0, 2160.0) bottomInset=0.0   bottom-edge:BLOCKED
TOPOLOGY: at least one display's bottom edge is blocked; a summon cannot fire there.
```

The Dell's `minY` (1117) is exactly the laptop's height, i.e. flush above —
the same blocking geometry as the July S2719DGF rig, on a different monitor.
CONFIRMED: the pure-geometry test identifies the blocked case on real
hardware, and the probe refuses rather than producing the uninterpretable
negative both 2026-07-23 sessions produced. The detector is therefore usable
as G1's precondition check, not just as probe scaffolding.

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

## Sensor validation — 2026-08-27 — **two of three detectors were blind**

The G1 track spent a day producing negatives from instruments nobody had ever
shown could register a positive. Correcting that came first, and it changed the
foundation of the feature.

**Method.** Side-by-side rig (built-in `#0` main at `(0,0)`, DELL G3223Q `#1`
at `(1728,0)`), separate Spaces ON, Dock at bottom. The owner moved the Dock by
hand, repeatedly, while three independent sensors and the cursor were logged at
50 ms. Ground truth was the owner's own eyes — and, at the end, the Dock
verifiably sitting on the Dell.

| Sensor | API | Permission | Live update in-process? | Correct on a cold read? |
|---|---|---|---|---|
| **A** `CoreDockGetRect` | private (dyld cache) | none | ✗ byte-identical `(354, 1039, 1019, 78)` throughout | ✓ fresh read returned `(3138, 2082, 1019, 78)` — on the Dell |
| **B** `NSScreen.visibleFrame` bottom inset | public | none | ✗ reported `#0` throughout | ✓ fresh read reported `#1` — on the Dell |
| **C** `CGWindowListCopyWindowInfo`, `ownerName == "Dock"`, largest window's bounds | **public** | **none** | ✓ **tracks every migration** | ✓ |

Extract — cursor reaches the Dell's bottom edge at 7.8 s, C migrates at 9.3 s,
A and B never move:

```
   7.8s  cursor=#1@BOTTOM  A=(354,1039,1019,78)  B=#0  C=(0,0,1728,1117)
   9.3s  cursor=#1@BOTTOM  A=(354,1039,1019,78)  B=#0  C=(1728,0,3840,2160)+(0,0,1728,1117)
   9.5s  cursor=#1@BOTTOM  A=(354,1039,1019,78)  B=#0  C=(1728,0,3840,2160)
  20.4s  cursor=#0@BOTTOM  A=(354,1039,1019,78)  B=#0  C=(1728,0,3840,2160)
  21.3s  cursor=#0@BOTTOM  A=(354,1039,1019,78)  B=#0  C=(0,0,1728,1117)
```

**CONFIRMED findings.**

1. **A and B go stale inside a running process.** Both were correct when the
   process started and neither moved again, across five migrations. Both were
   correct again when re-read from a *fresh* process. "Correct at launch" is
   not the property a long-running menu-bar app needs, so neither is safe as
   the G1 sensor as used here.
2. **C tracks migration live** — public, permission-free, validated against
   hand-driven migration and against independent ground truth (the owner's
   eyes, and the Dock verifiably resting on the Dell at the end). It reported
   `host: 1` when asked cold in that state.
3. **Summon latency ≈ 1.5 s** from cursor-at-edge to migration, with both Dock
   windows briefly present during the crossfade (9.3 s row). Any settle-and-poll
   loop must allow for it; the original probe's 2 s window was marginal.
4. **A real pointer summons reliably on this rig** — the mechanism exists here
   and this hardware can host the experiment.

**Deliberately still UNKNOWN — do not close this by assumption.** Whether A and
B update live inside a *properly running* `NSApplication` (DockKeeper itself,
with a real event loop) was **not** tested; these probes are bare CLIs whose
`RunLoop.current.run` may simply never deliver
`didChangeScreenParametersNotification`. The spike's own section (a) already
flagged that the notification "INFERRED fires on Dock migration — verify next",
and it is still unverified. So the honest statement is: **sensor C needs no
notification and is therefore the safe choice**, not that A and B are
unusable in principle.

**Process failure worth naming.** The first warp result was published as
CONFIRMED on the strength of a control proving the *cursor* landed where it was
asked. That control was real but insufficient: it validated the actuator and
never the sensor. A negative from an uncalibrated instrument is not evidence,
and it was merged as though it were.

A second, near-identical failure was caught before it shipped. The first draft
of *this* section declared A and B simply "BLIND" — on evidence that only ever
showed them stale *within a process*. A cold read of both, taken before
committing, showed both correct. The retraction would itself have needed
retracting. Same root cause both times: concluding from an instrument whose
behavior had not been characterized.

## Warp-only result — RE-RUN 2026-08-27 on sensor C — **NEGATIVE (now evidence)**

**Rig.** Dev MacBook Pro built-in Retina (1728×1117) + **DELL G3223Q**
(3840×2160, landscape), macOS 26.5 Apple Silicon, separate Spaces ON, Dock at
bottom, not auto-hidden. Native arrangement is Dell **flush above** the laptop
(CG origin `(-919, -2160)`) — the blocked geometry. Temporarily rearranged
side-by-side (`arrange sidebyside`: built-in main at `(0,0)`, Dell at
`(1728,0)`) so both bottom edges are free; `ssprobe` then reported
`TOPOLOGY: qualifies`.

| Probe | Result |
|---|---|
| Stage 1 — single warp to the Dell's bottom-centre | ✗ no summon |
| Stage 2 — repeated warps along the edge | ✗ no summon |
| Both stages, **5 consecutive runs** | ✗ no summon, 5/5 |
| **Control: does the warp actually land?** | ✓ **yes** — asked `(3648, 2159)`, cursor read back `(3648, 2159)` |
| Corroborating host detector `CoreDockGetRect` | ✓ `(354, 1039, 1019, 78)` — on the laptop, agreeing with the `visibleFrame` inset test |

**Re-run on sensor C (Dell → built-in, 6 s window, 5 consecutive runs): no
summon, 5/5.** The conclusion is unchanged, but for the first time it rests on
an instrument shown to register a positive. Sensor C reported `host: 1` before
each attempt and after it, while the same sensor had just tracked five
hand-driven migrations.

**CONFIRMED: `CGWarpMouseCursorPosition` alone does not summon the Dock**, on a
qualifying free-bottom-edge topology, with the warp independently verified to
place the cursor exactly on the target display's bottom row **and the sensor
independently verified to detect migration when it happens**. The control
matters — without it this would be indistinguishable from a warp that never
happened, which is the trap the first two sessions fell into for a different
reason.

**The gap that blocked this is now closed.** A real pointer *does* summon
reliably on this rig (sensor-validation section above), so the hardware can host
the experiment and the mechanism demonstrably exists here. The difference
between a hand and a warp is therefore real, not an artifact of the rig.

**Next rung is now justified — and it costs a permission.** The remaining
candidate is `CGEventPost`, which needs Accessibility (`AXIsProcessTrusted()`
= false here; not granted, and not to be granted casually). If synthesized
events summon where a warp does not, G1 becomes an **Accessibility-gated**
feature — DockKeeper at parity with DockLock on this axis rather than ahead of
it, exactly as their permission requirement always implied. That is a product
decision for ADR-009, not a spike outcome.

## `CGEventPost` rung — 2026-08-27, Accessibility GRANTED — **NEGATIVE**

Run from a purpose-built, ad-hoc-signed bundle (`dev.blamechris.dockkeeper.g1probe`)
so the TCC grant attached to one throwaway binary rather than to a terminal.
`AXIsProcessTrusted() == true` verified in-process for every run below. Rig and
sensor as in the previous section; measurement on **sensor C** throughout.

| Attempt | Result |
|---|---|
| `CGEventPost` mouseMoved, absolute position at the target's bottom-centre | ✗ no summon (repeated) |
| Same, with an approach glide and sustained `mouseEventDeltaY` pressure while clamped at the edge | ✗ no summon, 3× each direction |
| `hidSystemState` → `cgSessionEventTap` | ✗ |
| `combinedSessionState` → `cghidEventTap` | ✗ |
| `combinedSessionState` → `cgSessionEventTap` | ✗ |
| `privateState` → `cghidEventTap` | ✗ |
| **Control: do posted events move the cursor?** | ✓ **yes** — posted to `(3648, 2159)`, cursor read back `(3648, 2159)` |
| Direct AX manipulation: `AXPosition` / `AXSize` / `AXFrame` / `AXOrientation` on the Dock's `AXList` | ✗ **all `settable == false`** |
| Real hand, same rig, same position | ✓ summons reliably |

**CONFIRMED: synthesized events do not summon the Dock**, with Accessibility
granted, across four source/tap combinations, with and without motion deltas,
and with the actuator independently verified to move the cursor to the target.
The Dock's AX tree exposes geometry read-only, so there is no direct-set route
either.

**One anomalous positive, and why it is not evidence.** The first
`CGEventPost` run reported a summon after 3.13 s. It never reproduced — every
subsequent controlled attempt failed. Two candidate confounds were tested:
rearranging the displays alone does **not** move the Dock (watched 10 s, no
migration), which rules that out; the remaining and most likely explanation is
that the owner was still moving the mouse by hand at that moment, and the probe
attributed a hand-driven migration to its own events. A result that cannot be
reproduced under control is not a result.

**Consequence for G1.** Candidate 1 (pointer re-summon) is now **falsified for
every mechanism reachable from a normal app**, permission or no permission:
warp ✗, synthesized events ✗ (4 tap/source combos), AX direct-set ✗
(read-only), `killall` relocation ✗ (2026-07-23, though recorded on a stale
detector and still worth re-running). A real hand works, so macOS is
distinguishing genuine HID input from anything a userspace app can post.

This does **not** prove DockLock's mechanism is impossible — it proves it is not
any of the above. What Accessibility buys them therefore remains **UNKNOWN**,
and the working hypothesis that they summon via synthesized events is now
**doubtful** rather than "almost certainly". Candidate 3 (SkyLight/HIServices
export enumeration) is the only untried lead left.

**Corrected expectation.** Earlier framing in this spike — that a positive here
would put DockKeeper "at parity with DockLock, Accessibility-gated" — was
premature. There is no working mechanism to ship at any permission level.

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
- [x] ~~**Run `ssprobe` on that rig, 5× per stage.**~~ — **done 2026-08-27,
      NEGATIVE** (results above). Warp-only does not summon; warp landing
      verified by control.
- [x] ~~**Hand test (blocking)**~~ — **done 2026-08-27, POSITIVE.** A real
      pointer summons reliably on this rig. It also exposed that two of three
      sensors were blind; see "Sensor validation".
- [x] ~~Re-run warp-only on a validated sensor~~ — done, **still NEGATIVE 5/5**.
- [x] ~~**`CGEventPost` rung**~~ — **done 2026-08-27, NEGATIVE** under a real
      Accessibility grant, across four source/tap combinations, with actuator
      control. AX direct-set also ruled out (all geometry read-only).
- [ ] **Candidate 3 — SkyLight/HIServices export enumeration** (resolve-only):
      the last untried lead. Dump export tables for dock-display symbols beyond
      the guessed names rather than continuing to guess.
- [ ] Re-examine what DockLock's Accessibility grant is actually *for*. The
      summon hypothesis is now doubtful; their permission may serve hotkeys or
      window inspection rather than Dock relocation.
- [ ] **Propagate the sensor correction**: any design note that assumes the
      `visibleFrame` inset identifies the Dock's display *in a long-running
      process* must move to sensor C, or prove the notification path.
- [ ] **Verify the notification path** (the spike's oldest open question):
      does `didChangeScreenParametersNotification` actually fire on Dock
      migration inside a real `NSApplication`? If yes, B becomes viable and the
      choice is a design preference; if no, C is mandatory.
- [ ] Re-test `killall`-relocation on sensor C — it was falsified 2026-07-23
      using a blind detector, so that falsification is not safe either.
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
