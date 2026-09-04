# DockKeeper — Hardware Matrix Results (M6)

| | |
|---|---|
| **Status** | Living record — session 1 complete; session 2 (DK-NFR-001 spot check) and session 3 (DK-FR-014 guard, **G1 confirmed**) added 2026-09-02; **session 4** (DK-FR-014 **§3d row 9 confirmed** on the stacked-with-overhang rig) added 2026-09-03 |
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

## Session 2 — 2026-09-02 (DK-NFR-001 idle spot check, single display)

**First DK-NFR-001 measurement of any kind.** The budget has been UNKNOWN since v0.9.0 and is
recorded in three documents; this closes the memory half of it and leaves CPU open.

**Instrument.** Cumulative CPU-time delta over a wall interval, not `ps -o %cpu` — the latter
reports an average since process start, which for a long-lived menu-bar app is dominated by its
launch burst. Subject: `/Applications/DockKeeper.app` **v0.9.2**, pid 5419, ~13 h uptime, one
display connected, guard **not** armed.

| Metric | Target | Measured | Verdict |
|---|---|---|---|
| Memory (`phys_footprint`) | < 30 MB preferred; < 50 MB acceptable | **16 MB**, peak 17 MB | **CONFIRMED ✅ meets the *preferred* target** |
| Memory growth | flat | +16 KB over 300 s | CONFIRMED ✅ no leak signal |
| Idle CPU | ~0% under stable conditions | 0.60 % of one core (quiet); 0.80 % under load; **0.22 % lifetime average** | **INCONCLUSIVE** — see below |

**Which memory metric, and why it matters.** The budget is stated in
[behavior-specification](behavior-specification.md) DK-NFR-001, [technical-design](technical-design.md) §14
and [risk-register](risk-register.md) R-009, and **none of the three names a metric**. The same process
measures **16 MB** by `phys_footprint` and **64 MB** by RSS — pass or fail depending on an unstated
choice. `phys_footprint` is the normative one here: it is what Activity Monitor's *Memory* column
reports, and DK-NFR-001's own failure description is "Activity Monitor presence". RSS counts shared
framework pages that every SwiftUI/AppKit process maps and does not pay for. Recorded so nobody
re-derives the wrong conclusion from `ps` and reports a false budget miss — R-009's "commonly 25–50 MB"
is an RSS-shaped figure and is not comparable to the 16 MB above.

**Why CPU is inconclusive rather than a pass or a miss.** Both 300 s windows landed above the 13-hour
lifetime average (0.22 %), so neither is confidently "idle": the first was taken while sixteen review
agents saturated the machine, and the second is quieter but still a five-minute sample on a working
laptop. 0.6 % of one core is *small* — well under a tenth of a percent of total CPU on this machine —
but it is not the "~0%" the requirement asks for, and a spot check cannot settle it. **The 24 h idle
soak in [test strategy §4](test-strategy.md) remains the gate**, unchanged. This is a sanity check that
found nothing alarming, not a measurement that discharges DK-NFR-001.

**Not covered: the guard.** DK-FR-014's event tap was never armed — it needs two displays and only one
was connected. The tap is the first per-event cost in the app (R-015), so the number above is a
*floor*, not a result for the shipped 0.9.3 feature set. [Test strategy §3d](test-strategy.md) row 2
carries that cell.

## Session 3 — 2026-09-02 (DK-FR-014 bottom-Dock guard, two-display rig)

**ADR-015's open obligation is discharged.** The claim that a real pointer cannot complete the
summon while the guard is armed was INFERRED from 2026-08-27 until this session. It is now
**CONFIRMED with a control on real hardware.**

**Rig.** MacBook Pro built-in Retina `(0, 0, 1728, 1117)` — **MAIN and preferred** — plus **DELL
G3223Q** `(1728, -982, 3840, 2160)`, side-by-side, **both bottom edges free**. Separate Spaces ON,
Dock bottom, not auto-hidden. Guarded display: the G3223Q (the non-preferred one), `clampY = 1175`.
macOS 26.5, Apple Silicon. Build: `0.9.3-dev` from `8f722d0`, **Developer ID signed** (see the
tooling note below).

| # | Case | Result | Evidence |
|---|---|---|---|
| 1 | **A real hand cannot summon the Dock** to the guarded display | **CONFIRMED ✅** | Owner pushed the pointer at the G3223Q's bottom edge with the tap armed: Dock did **not** move. With the tap released: the same push **did** move it. Tap state read from the unified log on both runs, not assumed. |
| 1s | Synthetic clamp, with control | **CONFIRMED ✅** | Aim `(3500, 1177)`: armed → **10/10 held at y=1175** (`maxY − 3`); released → **10/10 reached 1177**. |
| 4 | macOS disables a slow tap | **No occurrences** | Zero `tap re-enabled after …` lines across the whole session, including a 45 s burst at ~80 events/s. The callback is not slow enough to be disabled. |
| 2 | Idle cost with the guard armed | **INCONCLUSIVE** | See below. |

**Memory with the guard armed: 18 MB** `phys_footprint` (16 MB without it), still inside the
**< 30 MB preferred** budget.

### Why row 2 is still inconclusive, and one instrument that lied

Three numbers were taken and they do not cohere — idle measured *higher* than active use, which is
incoherent and means background activity dominated the samples on a machine in use:

| Condition | Measured |
|---|---|
| Real vigorous mouse use, guard armed | 2.0 % of one core |
| Pointer still, guard armed | 3.0 % of one core |
| v0.9.2, no guard, quiet | 0.22 – 0.60 % of one core |

**Do not quote any of these as the DK-NFR-001 result.** The 24 h soak remains the gate (R-015).

**The instrument that lied, recorded so nobody rebuilds it.** Driving synthetic motion with
`CGEvent(...).post(tap: .cghidEventTap)` at ~80 events/s measured **52 % of one core — an
artifact.** Posting at the HID tap forces the whole HID stack to process every synthetic event,
work that a real mouse does not incur the same way; the same activity performed by hand cost
**2 %**. A synthetic event stream is a valid instrument for *whether* the clamp fires and a
**wrong** one for *what it costs*.

### Tooling note: an AX-gated feature cannot be tested from the default dev loop

The first two attempts measured nothing because the tap never armed, and `--diagnostics` reported
`guarding 1 display(s)` throughout. Two causes, both filed:

- `Scripts/build-app.sh` ad-hoc signs by default, and it `rm -rf`s the bundle each build, so every
  rebuild is a **new code identity** and the Accessibility grant goes stale while System Settings
  still shows a row switched on. Rebuilding with `SIGNING_IDENTITY` set to the Developer ID fixed
  it immediately. **Any on-device AX test must use a real signing identity.**
- `--diagnostics` invoked from a terminal inherits the *terminal's* Accessibility grant through TCC
  responsible-process attribution, so it reported the permission as present while the GUI app
  reported *"Waiting for Accessibility permission"* ([#77](https://github.com/blamechris/DockKeeper/issues/77)).

The only trustworthy signal was the unified log, because `start()` logs on all three paths.
[#78](https://github.com/blamechris/DockKeeper/issues/78) proposes the live-state readout that
would have answered this in one command.

## Session 4 — 2026-09-03 (DK-FR-014 §3d row 9, stacked-with-overhang rig)

**§3d row 9 is CONFIRMED with a control.** The crossing under per-span zones — the last open
on-device obligation of ADR-015, and the only one whose failure direction is a *trapped cursor*
rather than an unguarded Dock — is now observed on hardware. With the guard armed the pointer
crosses the shared strip untouched, and is held 3 pt clear on both overhangs; releasing the guard
moves every overhang column back and leaves the shared strip unchanged.

**Two instruments, and the row needed both.** A synthetic probe answers the *geometry* half
exactly — which columns are clamped and to what value — and cannot answer the Dock-migration half
at all, because a summon needs dwell. That half was closed by hand, by the owner, with its own
control (row 9f). Neither instrument alone closes row 9; the split is recorded per cell below
rather than averaged into one verdict.

**Rig.** MacBook Pro built-in Retina `(0, 0, 1728, 1117)` — **MAIN and preferred** — with the
**DELL G3223Q** `(-478, -2160, 3840, 2160)` **stacked above it and overhanging on both sides**:
the owner's own arrangement, and the shape [#83](https://github.com/blamechris/DockKeeper/issues/83)
was written for. Separate Spaces ON, Dock bottom, not auto-hidden, `lockEdge = 2`, Accessibility
granted. macOS **26.6.2 (25G83)**, Apple Silicon — note session 3 ran on **26.5**, so this is a
fresh OS as row 1 asks for. Build: **0.9.4-dev from `3257335`**, Developer ID signed.

The edge divides as ADR-015 predicts, and the free total is the invariant 3840 − 1728 = **2112 px**:

| Span of the Dell's bottom edge | x-range | Width | Zone |
|---|---|---|---|
| Left overhang | `[-478, 0)` | 478 px | **clamped**, `clampY = -3` |
| Shared with the built-in | `[0, 1728)` | 1728 px | **open — the crossing route** |
| Right overhang | `[1728, 3362)` | 1634 px | **clamped**, `clampY = -3` |

`clampY = frame.maxY − 3` and the Dell's `maxY` is **0**, so the guard band on this rig is the
open interval `y ∈ (−3, 0)` and the clamp target is a **negative** number. Every threshold below
is stated as a number for that reason: a sanity rule carried over from session 3's positive-`y`
rig (`clampY = 1175`) inverts here.

### What was run

Two instruments, both read in **CG global top-left** — the space `ClampZone` uses — so no Cocoa
conversion sits between the measurement and the assertion:

- **Decision**, re-derived on the real geometry: `--diagnostics` →
  `Bottom guard: guarding 1 display(s) over 2 span(s); 1 partly covered`.
- **Live tap state**, emitted by the running process and never re-derived: the unified log, filtered
  by `subsystem == "com.dockkeeper.app" AND process == "DockKeeper"` and recorded with its PID —
  `Bottom-Dock guard: armed over 2 span(s) on 1 display(s)` (PID 6239), and
  `Bottom-Dock guard: released` on quit.

The measured motion is a 1 pt synthetic walk **ending at `y = −1`**, i.e. *inside* the band, posted
with `CGEvent(…).post(tap: .cghidEventTap)` — the HID tap sits below the app's `.cgSessionEventTap`,
so the session tap sees it. The question asked is not "did motion stop" but **"was the event's
location rewritten"**: armed, the tap rewrites `y` to `−3`; released, the posted `−1` passes
through. That is why this row does not suffer the confound it was expected to.

| # | Cell | Armed | Released (control) | Result |
|---|---|---|---|---|
| 9a | **Shared strip crosses** — `x ∈ {0, 200, 864, 1500, 1727}`, aim `y = +60` on the built-in | reaches **60** at all five | reaches **60** at all five | **CONFIRMED ✅** the crossing route is open with per-span zones armed |
| 9b | **Shared strip is never clamped** — same five columns, aim `y = −1` | **10/10 at −1** at `x = 864`; −1 at all five in the sweep | 10/10 at −1 | **CONFIRMED ✅** at the five columns sampled. That *no* zone covers `[0, 1728)` is not generalised from them — it is true by construction (the sweep clips the blocker interval out) and asserted as a unit invariant over whole arrangements |
| 9c | **Left overhang is held** — `x ∈ {−478, −200, −1}`, aim `y = −1` | **10/10 held at −3** at `x = −200`; −3 at all three in the sweep | **10/10 at −1** | **CONFIRMED ✅** held exactly 3 pt clear |
| 9d | **Right overhang is held** — `x ∈ {1728, 2500, 3361}`, aim `y = −1` | **10/10 held at −3** at `x = 2500`; −3 at all three in the sweep | **10/10 at −1** | **CONFIRMED ✅** |
| 9e | **The seam** — `x = 1727` (last shared column) vs `x = 1728` (first overhang column) | 1727 → **−1**, 1728 → **−3** | both −1 | **CONFIRMED ✅** the boundary column goes entirely to the overhang; no gap, no double coverage |
| 9f | **Dock does not migrate** — real hand, by the owner | pushed at an overhang with the tap armed: **Dock did not migrate** | same push after quitting the app: **Dock migrates** | **CONFIRMED ✅** with a control, 95 s apart (see below) |

**The armed and released runs are the same instrument minutes apart, and the only thing that
changed is the guard.** Six overhang columns moved `−3 → −1`; five shared columns did not move.

**The run is self-validating, which is what makes 9a/9b trustworthy.** A null result ("the shared
strip was not clamped") is worthless if the instrument cannot see a clamp at all. In *the same run*
the overhang columns read `−3` — a value only the guard produces — so the instrument demonstrably
saw clamping at the moment the shared strip read `−1`. Positive and negative in one pass, per
instrument-discipline rule 5.

### Row 9f — the Dock-migration clause, by hand, with a control

**The synthetic instrument cannot reach this clause and did not try.** It walks the pointer to the
trigger row and reads back within ~100 ms, while a summon needs sustained dwell; `CoreDockGetRect`
read `(354, 1039, 1019, 78)` on the built-in before and after every synthetic run, which is
consistent with the guard working and equally consistent with never having attempted a summon. It
is not evidence.

**It was closed by hand instead, by the owner, and the unified log timestamps both halves:**

```
17:12:08.531  Bottom-Dock guard: armed over 2 span(s) on 1 display(s)   DockKeeper[6393]
              -> pushed the pointer at an overhang: the Dock did NOT migrate
17:13:43.002  Bottom-Dock guard: released                               DockKeeper[6393]
              (the owner quitting from the menu bar - this IS the control)
              -> the same push now moves the Dock as expected
```

Armed and released are **95 seconds apart** on the same rig, same sitting, and the only thing that
changed is the guard.

**The control also validates the aim, which is what makes this more than an anecdote.** A push on
the *shared* strip could not migrate the Dock in either state — the pointer simply crosses down to
the built-in — so "it moved once the guard was released" is itself proof that the span being pushed
was a free, summon-capable one, i.e. an overhang. The positive result and its discriminator come
from the same pair of observations, exactly as rule 6 asks. **Which** overhang, left or right, was
not recorded.

An earlier reading of this session's log concluded the owner's push happened while nothing was
armed, because a `released` line sat at the tail and no process remained. That was wrong: the arm
line preceding it is the window the push happened in, and the release is the control, not a
disqualification. Recorded because "the instrument was not running" and "the instrument was running
and then deliberately stopped" produce identical tails in this log, and #87 — the arm line being
written only on the transition — is what makes the difference invisible without reading the pair.

### The defect #85 fixes, caught in the wild on the way past

The unified log carries both wordings from the same machine on the same day, which is a cleaner
before/after than the test could have staged. Verbatim lines, one from each end
(`log show --predicate 'subsystem == "com.dockkeeper.app" AND process == "DockKeeper"'`):

```
2026-09-02 15:54:44.593 Df DockKeeper[4778:15d076e] [com.dockkeeper.app:app] Bottom-Dock guard: armed over 1 display(s)
2026-09-02 18:06:27.163 Df DockKeeper[4778:15d076e] [com.dockkeeper.app:app] Bottom-Dock guard: released
2026-09-02 23:53:01.579 Df DockKeeper[6060:16ca072] [com.dockkeeper.app:app] Bottom-Dock guard: armed over 2 span(s) on 1 display(s)
```

Those three are quoted exactly. Summarising the rest rather than pasting it: the pre-#85 wording
`armed over 1 display(s)` appears seven times on 2026-09-02 (13:55:00, 13:55:54, 13:58:19, 14:00:15,
14:04:57, 15:54:44, 18:03:49) across PIDs 83396, 83528, 83732, 83987, 84268 and 4778, and the
post-#85 wording `armed over 2 span(s) on 1 display(s)` appears at 23:53:01, 23:56:10 and 23:58:07
across PIDs 6060, 6239 and 6393, plus 96042 the following day.

0.9.3's last arm was **over a whole display**, it released at **18:06:27**, and it never re-armed —
through nearly six hours in which the app kept running. By 23:52 the arrangement was
stacked-with-overhang, and 0.9.3's own `--diagnostics`, run on that desk minutes before the swap,
answers `idle — no guardable display (1 with a blocked bottom edge; clamping one would trap the
pointer)`. So the shipped release stood down over all 2112 px of free edge on the owner's actual
desk, which is exactly the abandonment [#83](https://github.com/blamechris/DockKeeper/issues/83)
was filed about, observed rather than argued.

**That the 18:06 release was *caused* by the rearrangement is INFERRED, not measured.** The app
logs no display-reconfiguration line, so the coincidence in time is all there is; the rearrangement
itself was not observed. What is measured is the pair of endpoint states — armed over a whole
display before, `idle — no guardable display` on the stacked rig after.

### Three instruments, and the two that lied

**A probe that aimed outside the band would have recorded a false FAIL, and its own control caught
it.** The first harness walked to `y = +60` and read the endpoint. But `ClampZone.contains` accepts
only `clampY < y < frame.maxY` — here `(−3, 0)` — so an event at `y = 60` is **never** clamped, by
a perfectly working guard or a broken one. Run as a baseline against the then-installed
0.9.3 — which its own `--diagnostics` reports idle on this desk — it printed "crossed" at every
column including both overhangs. That is what *flagged* it, since a column with no display beneath
it cannot be "crossed" to anything; re-reading `contains` is what *explained* it. The baseline was
run to validate the instrument, and validating the instrument is the only reason the fault was
found before the result was published rather than after. Aiming inside the band is what session 3 did too
(aim 1177, `maxY` 1178, clamp 1175); the lesson is that **the aim point is part of the instrument**,
and on this rig the band is 3 pt wide and bounded *above* by zero.

**Posted synthetic events are not constrained by the desktop union, so "the OS stops it at the
edge" is a false model.** The expected confound for row 9 was that on an overhang there is no
display beneath, so macOS's own pointer bound would stop downward motion regardless of the guard —
making armed and released indistinguishable. It does not: a posted move to `(−5000, 5000)` reads
back as `(−5000, 5000)` from **both** `CGEvent(source: nil)!.location` **and** `NSEvent.mouseLocation`
converted to CG. Two independent APIs agree, so the reading is not one API echoing the caller. The
consequence is that the released control reads the aim (`−1`) rather than a desktop bound, the
armed run reads the clamp (`−3`), and the discriminator is a rewritten value rather than an
absence of motion — the confound is structurally absent from this design rather than merely
survived. **This says nothing about a real hand**, which is bounded by the desktop; it is a
property of synthetic posts, and it is why row 9f is scoped as it is.

**`--diagnostics` reported the guard OFF while the guard was actively clamping** — a fresh instance
of [#77](https://github.com/blamechris/DockKeeper/issues/77)/[#78](https://github.com/blamechris/DockKeeper/issues/78),
in the *opposite* direction from session 3's. An external `defaults write com.dockkeeper.app
lockBottomDockToDisplay -bool false` was not observed by the running app: no `released` line was emitted and the tap kept
clamping overhangs to `−3`, while `--diagnostics`, re-reading the domain in a fresh process,
printed `Bottom guard: off — not enabled in Preferences`. Both halves behaved as built — the app
holds live state, the report re-derives from disk — and that is precisely the point. Session 3's
case was a false *positive* ("guarding" while nothing armed); this one is a false **negative**, and
it is worse for support, because the user is told the feature is off while their pointer is still
being held. It is the case #78's live-state readout exists to remove. The release control was
therefore taken by **quitting the app** — the tap is process-owned and dies with it — and confirmed
from the log line, never from the toggle.

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
| **Crossing a shared span with per-span zones armed** (§3d row 9) | ✅ CONFIRMED with a control — shared strip open, both overhangs held at `clampY = −3`, 10/10 each way | 4 |
| **Per-span zone emission on a stacked-with-overhang rig** | ✅ CONFIRMED — 2 spans on 1 display, `partiallyGuarded`; 0.9.3 refused the same desk outright | 4 |
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
