# DockKeeper — Hardware Matrix Results (M6)

| | |
|---|---|
| **Status** | Living record — session 1 complete; session 2 (DK-NFR-001 spot check) and session 3 (DK-FR-014 guard, **G1 confirmed**) added 2026-09-02; **session 4** (DK-FR-014 **§3d row 9 confirmed** on the stacked-with-overhang rig) and **session 5** (DK-FR-011's standing capture-flip UNKNOWN closed, plus DK-FR-013 §3c rows 3 and 6) added 2026-09-03 |
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

The measured motion is a 1 pt synthetic walk posted with `CGEvent(…).post(tap: .cghidEventTap)` —
the HID tap sits below the app's `.cgSessionEventTap`, so the session tap sees it. The question
asked is not "did motion stop" but **"was the event's location rewritten"**.

**Each column is walked twice, to two different aims, and they answer different questions.** Reading
the table without this makes 9a and 9b look like one run contradicting itself:

| Aim | Lands | Asks | Armed answer on a free span |
|---|---|---|---|
| `y = −1` | the Dell's last row, **inside** the band `(−3, 0)` | *is this column clamped?* | rewritten to **`−3`** |
| `y = +60` | on the **built-in** for a shared column; on **no display at all** for an overhang column | *can the pointer get to the display beneath?* | **`60`** — outside the band, never clamped |

So `y = −1` is the discriminating cell and `y = +60` is the crossing cell; a column can legitimately
report "held at −3" for the first and "reached 60" for the second, because the band is only 3 pt
tall and bounded above by zero. The v1 fault below was using `+60` *as the clamp test*, where it
can only ever return "not held".

**`y = +60` is load-bearing only on the shared columns**, where it is the actual crossing — the
pointer arriving on the built-in. On an overhang there is no display at 60, and the reading of `60`
there says only that the posted event was not rewritten, since a posted move is not bounded by the
desktop union (below). It is reported for all eleven columns because a *uniform* result is what
shows the guard alters nothing outside its band, not because an overhang crossing means anything.

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

## Session 5 — 2026-09-03 (DK-FR-011 + DK-FR-013 release gates for 0.9.4)

**The standing ADR-011 UNKNOWN is closed, and with it the two crash-recovery cells that sat on top
of it.** Whether a real screen capture flips `CGSIsScreenWatcherPresent` had been the open M6/M12
question since the feature shipped on 2026-07-23 — *"the true capture-flip (does the flag fire,
latency, which apps) is UNKNOWN pending on-device verification"*. It fires.

**Rig.** Same as session 4 (built-in + DELL G3223Q stacked above, overhanging), macOS **26.6.2
(25G83)**, Apple Silicon, build **0.9.4-dev from `0bf6d5c`**, Developer ID signed. Capture driven
with `screencapture -V <n> -v` — a real recording that produced a real ~9.6 MB `.mov`, not a
simulated flag.

Two instruments, both read directly rather than through the app: `CGSIsScreenWatcherPresent`
(SkyLight, `dlsym`'d exactly as `ScreenCaptureMonitor` does) and `CoreDockGetAutoHideEnabled`,
polled twice a second, alongside the app's own unified-log lines.

### §3c row 1 — a real capture flips the flag  · **CONFIRMED ✅**

| t | `watcherPresent` | Dock auto-hide | |
|---|---|---|---|
| 0.5 s | **TRUE** | off | capture starts — flag fires within ½ s |
| 3.0 s | TRUE | **ON** | app reacts: `Hid Dock for screen capture (auto-hide on)` |
| 10.5 s | false | ON | capture ends |
| 11.5 s | false | **off** | `Restored Dock auto-hide to off (restored)` |

**Latency, measured rather than estimated: ~2.5 s to hide, ~1 s to restore** — the poll cadence, not
the detector, which fires in under half a second. Afterwards `com.apple.dock autohide` read `0`, its
pre-test value, and `--diagnostics` reported `Screen-share: no record held`.

**Which apps** is answered only for `screencapture`. QuickTime, Zoom, Teams and Screen Sharing.app
remain unverified; the detector is a system-wide screen-watcher flag rather than a per-app one, so
they are *expected* to behave alike, and that expectation is INFERRED.

### The safety property — a pre-existing user auto-hide  · **CONFIRMED ✅**

With the user's *own* auto-hide already ON before the capture, a full capture cycle ran and the app
did **nothing**: no `Hid Dock` line, no `Restored` line, no record written, and auto-hide stayed ON
throughout and after. This is ADR-011's never-touch-the-user's-own-auto-hide rule, which the unit
suite proves as a decision and which had never been observed against the real Dock.

### §3c row 3 — `kill -9` mid-capture, then relaunch  · **CONFIRMED ✅**

The end-to-end proof of the [#29](https://github.com/blamechris/DockKeeper/issues/29) fix, and the
first time the whole chain has run against the real Dock. The defect condition was reproduced
first: with the Dock hidden for a capture, `SIGKILL` left auto-hide **stuck ON with no owner** and a
`screenShareHideRecord` on disk. The capture was then allowed to end — auto-hide still stuck ON —
and the app relaunched:

```
Restored Dock auto-hide to off (repaired)
```

Auto-hide **off**, and the record **removed from the domain** rather than merely ignored
(`defaults read com.dockkeeper.app screenShareHideRecord` → *does not exist*), which exercises the
guarded write in `AppState.init` end to end. `--diagnostics`: `Screen-share: no record held`.
Note the reason word: `(repaired)` is the launch path, distinct from `(restored)`.

### §3c row 6 — relaunch mid-capture adopts, with no Dock write  · **CONFIRMED ✅ (as far as this
instrument reaches)**

`SIGKILL` during a capture, then relaunch **while the capture was still running**:

```
Adopted a leftover screen-share Dock hide; a capture is still running
```

and **no `Hid Dock` line** — the adopt path issued no Dock write at all, which is the property the
unit tests assert as `writes == [true]` only. Auto-hide read ON continuously across the kill and the
relaunch, so there was no window in which it was off. When the capture ended the adopted hide
restored normally: `Restored Dock auto-hide to off (restored)`.

**What is still not observed is the far end.** Row 6's stated expectation is *"the far end never
sees the Dock appear"*, and there was no remote viewer — a local recording has no far end. What is
confirmed is the mechanism that expectation rests on (no write, no off-window). The visual claim
stays INFERRED.

### The whole sequence, from the unified log

Four different PIDs, which is what makes the process deaths legible:

```
17:47:19 DockKeeper[96515] Hid Dock for screen capture (auto-hide on)
17:47:28 DockKeeper[96515] Restored Dock auto-hide to off (restored)      <- row 1, clean cycle
17:49:07 DockKeeper[96515] Hid Dock for screen capture (auto-hide on)
                           ... SIGKILL 96515 ...
17:49:31 DockKeeper[99938] Restored Dock auto-hide to off (repaired)      <- row 3, launch repair
17:50:13 DockKeeper[99938] Hid Dock for screen capture (auto-hide on)
                           ... SIGKILL 99938, relaunched mid-capture ...
17:50:20 DockKeeper[ 1536] Adopted a leftover screen-share Dock hide; a capture is still running
17:50:38 DockKeeper[ 1536] Restored Dock auto-hide to off (restored)      <- row 6, adopt then restore
```

All three outcomes — `(restored)`, `(repaired)`, `Adopted` — are distinguishable in the log without
knowing which cell was being run, which is what makes this readable as evidence at all.

### Not run, and why

- **§3c row 4 (logout with a hide held)** — needs a real logout, which ends the session driving the
  test. Still the dominant real exit path and still INFERRED.
- **§3c rows 2 and 5** (menu Quit, `SIGTERM`) — not exercised here; a hide was never held across
  either path in this sitting.
- **§3c rows 7, 8, 9, 10** unchanged: the poisoned-population menu item, `CoreDock` durability
  across an immediate exit, panic durability (untestable), cross-user (argued, not measured).
- **§3d rows 3, 5, 6, 7, 8** unchanged from session 4 — all fail *open*.
- **DK-NFR-001 cost** unchanged — R-015, the 24 h soak.

**The app's settings were returned to their pre-test state**: `hideDockDuringScreenShare` is opt-in
and was *unset* before this session, so it was deleted rather than written `false`, and
`com.apple.dock autohide` is back to `0`. Verified after the last relaunch.

## Session 6 — 2026-09-04 (DK-FR-015's writer half, and §3d rows 5–8)

**#96 is closed, and the poll-cadence bound it called "an argued figure and not a measured one" is now
measured.** This session ran the new build as the real menu-bar app for the first time, which is the
only way the app's own lifecycle wiring can be reached.

**Rig.** Built-in + DELL G3223Q stacked with overhang, macOS **26.6.2 (25G83)**, Apple Silicon (M4 Max),
build from **`9eb3599`**, Developer ID signed (`PG8VP4PTGV`). Installed at `/Applications/DockKeeper.app`,
displacing 0.9.4. The bundle is stamped **0.1.0** — the repo default, left unstamped **on purpose**: it is
not a release, and an unmistakably different version string is what makes "the new build is the one
running" a one-glance check rather than an inference.

**Measured arrangement — measured, not quoted.** #83 recorded ~748/~1364 and session 4 measured 478/1634;
this session measured 478/1634 again. Only the total is invariant.

| | CG frame (top-left origin) | |
|---|---|---|
| Built-in Retina Display (id 1) | `(0, 0) 1728×1117` | main, **preferred** |
| DELL G3223Q (id 3) | `(−478, −2160) 3840×2160` | **guarded** (non-preferred) |

Left overhang 478 + right overhang 1634 = **2112**, the invariant (`3840 − 1728`). The guarded display's
`frame.maxY` is **0**, so `clampY = 0 − 3 = **−3**` and the clamp band is `y ∈ (−3, 0)` — negative, which
inverts every sanity rule carried from a positive-`y` rig.

**The aim point was derived from the predicate, not chosen.** `ClampZone.contains` accepts only
`point.y > clampY && point.y < frame.maxY`, so every probe below aims at `y = −1` — inside a 3 pt window.
The shared strip `x ∈ [0, 1728)` carries no zone and is therefore a **built-in control**: a probe there
must come back unrewritten in every configuration, armed or not.

### The Accessibility grant survived the rebuild, and that was checked before anything was run

The seed's load-bearing precondition. Verified by comparing designated requirements rather than by
trying it and hoping:

```
/Applications/DockKeeper.app (0.9.4)  designated => identifier "com.dockkeeper.app" and anchor apple generic
  and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13]
  and certificate leaf[subject.OU] = PG8VP4PTGV
dist/DockKeeper.app (new build)       designated => ...identical...
```

Identity-based, no hash and no path, so the grant transfers. Confirmed empirically at first launch:
`Accessibility: granted, as the running app sees it` — **the app's own answer**, not a shell's (#77).

### Step 0 / #96 — the writer half  · **CONFIRMED ✅, all seven steps**

Launched via `open`, i.e. through LaunchServices, never from the shell — a CLI launched from a terminal
inherits the terminal's TCC grants and would have poisoned the permission verdict.

| # | Step | Result |
|---|---|---|
| 1 | Quit installed 0.9.4, install signed build | `released` logged at 23:09:17.218 by pid 28571; exactly one bundle on disk |
| 2 | `status --live` reports it live | ✅ `Live: yes — pid 94433`, `Bundle: /Applications/DockKeeper.app`, `Divergence: none`, `Tap: armed … over 2 span(s)` |
| 3 | A real state change moves `stateChangedAt`, `Guard:`/`Tap:` follow | ✅ **with a control** — see below |
| 4 | Armed heartbeat refreshes `observedAt` while `unchanged for` climbs | ✅ **and the 30 s bound is measured** — see below |
| 5 | Menu Quit → retraction, exit 3 | ✅ `Live: no — no DockKeeper instance is running`, exit 3 |
| 6 | `kill -9` → "killed rather than quit", exit 4 | ✅ `Live: no — the record names pid 48748, which is not running`, exit 4 |
| 7 | Exactly one `com.dockkeeper.app` on disk | ✅ `dist/DockKeeper.app` deleted in the same sitting |

Step 5 used the Quit Apple Event. That is **not** a weaker substitute for the menu item: `MenuBarContent.swift:123`
is literally `Button("Quit DockKeeper") { NSApp.terminate(nil) }`, and the Quit Apple Event invokes
`terminate:`. Both reach `applicationWillTerminate` by the same call. No scoping caveat is owed.

**Step 3, with its control.** The control is the half that makes it a measurement rather than a coincidence:

| | `unchanged for` | `Guard:` / `Tap:` |
|---|---|---|
| baseline | 6 s | guarding 1 display over 2 spans / armed |
| **after 20 s idle** | **26 s** — did *not* reset | unchanged |
| after a real change (edge → Left) | **3 s** — reset | `idle — only a bottom Dock is pointer-summoned` / `not armed` |
| restored to Bottom | 3 s | guarding over 2 spans / armed |

`stateChangedAt` does not drift on a no-op and does move on a real change, and the guard and tap rows
follow it.

### The poll-cadence bound, measured

#96 recorded the `max(5, recoveryInterval)` freshness bound as argued. Sampling `status --live` every
10 s for 130 s with the guard armed and otherwise idle:

```
t=010  Observed: 18s ago; unchanged for   48s
t=020  Observed: 28s ago; unchanged for   58s
t=030  Observed:  8s ago; unchanged for 1m 8s     <- refresh
t=040  Observed: 18s ago; unchanged for 1m18s
t=050  Observed: 28s ago; unchanged for 1m28s
t=060  Observed:  8s ago; unchanged for 1m38s     <- refresh
...  (sawtooth continues to t=120)
```

A clean sawtooth: refreshes at t = 22, 52, 82, 112 s — **four consecutive 30 s intervals**, matching
`max(5, recoveryInterval)` with the 30 s default. `unchanged for` climbed monotonically 48 s → 2 m 38 s
with no reset across the whole window, which is the `stateChangedAt` carry-forward working. `0 clamp(s)`
throughout, so the window was also a clean zero baseline for the clamp probes.

### The clamp, with its control  · **CONFIRMED ✅**

Walked down into the band at five columns. `posted y = −1` in every case:

| column | settled CG `y` | AppKit readback → CG | verdict |
|---|---|---|---|
| left overhang `x = −240` | −3.0 | −3.0 | **CLAMPED** |
| **shared strip `x = 800`** | **−1.0** | **−1.0** | **free — the control** |
| right overhang `x = 2545` | −3.0 | −3.0 | **CLAMPED** |
| bottom-left corner `x = −477` | −3.0 | −3.0 | **CLAMPED** |
| bottom-right corner `x = 3360` | −3.0 | −3.0 | **CLAMPED** |

Two independent APIs agree in every row — `CGEvent(source: nil)!.location` and `NSEvent.mouseLocation`
converted through the main display's height. Agreement across two APIs is what makes this a property of
the pointer rather than one API echoing the caller.

**The counter check is exact, not merely non-zero.** The walk has two in-band steps (`y = −2, −1`) and four
guarded columns, so a working tap must record **exactly 8** clamps. `status --live` afterwards read
`8 clamp(s)`, and the shared strip contributed none. That also confirms the tap's vitals reach the
published record, and that a counter move forces an off-cadence write while `unchanged for` keeps climbing.

### §3d row 8 — `kill -9` while armed  · **CONFIRMED ✅**

| | probe at left overhang `x = −240`, `posted y = −1` |
|---|---|
| armed, before | `cg_y = −3.0` — **CLAMPED** |
| `kill -9` | 23:21:16.476 |
| immediately after | `cg_y = −1.0` — **FREE**, observation complete by 23:21:17.095 |

**619 ms** from kill to a confirmed free pointer, and nothing persisted. An event tap is process-owned and
dies with the process; there is no record and no launch repair, and this measures that claim rather than
restating it. The same kill answered #96 step 6.

### §3d row 6 — mirrored displays  · **CONFIRMED ✅, by a different code path than the row assumed**

Driven with `CGConfigureDisplayMirrorOfDisplay` (`.forSession`), which is the same configuration change
System Settings makes — the Arrange sheet on this macOS offers only an Option-drag, which is a canvas
gesture and a far less precise instrument.

The row's expectation holds: **the guard stands down and there is no band on the visible screen.** The
pointer reached the visible display's bottom edge (`CG y = 1116`, re-derived for the mirrored geometry —
the unmirrored aim of `y = −1` is off-screen once the DELL is gone) and came back unrewritten.

**But the reason is `singleDisplay`, not `mirrorsPreferredDisplay`,** and that distinction is worth
recording rather than smoothing over. Hardware mirroring collapses the mirror set to one active display:
`CGGetActiveDisplayList` returned only id 1 and `NSScreen.screens.count` went 2 → 1, so `decide` exits at
`snapshot.displays.count > 1` long before the mirror gate. The reported reason was
`idle — needs a second display`.

**`IdleReason.mirrorsPreferredDisplay` is therefore still unexercised on real hardware.** It defends the
case where two displays are reported with *identical frames* — plausibly Sidecar/AirPlay or a transient
reconfiguration — which this rig does not produce by mirroring. Recording row 6 as confirmed without this
sentence would leave a shipped branch looking tested when it is not.

Unmirroring restored the arrangement to exactly `(−478, −2160) 3840×2160` and the guard re-armed over 2 spans.

### §3d row 5 — the stacked refusal  · **CONFIRMED ✅**

This row had never been runnable, because the refusal needs the **guarded** display's bottom edge covered
along its whole length and the 4K is wider than the built-in, so no arrangement of the two can cover it.
The seed proposed putting the MacBook on top; that reaches the shape, but only if the *preferred* display
is also swapped to the DELL, since the guard only ever guards the non-preferred display.

Rather than rewrite the owner's stored preferred display, the rig was built the other way: the DELL was
narrowed to a 1280×720 mode and placed flush **on top of** the built-in and fully inside its horizontal
span — `CG (200, −720) 1280×720` against the built-in's `(0, 0) 1728×1117`. The DELL is then the
non-preferred display, its bottom edge (`y = 0`, `x ∈ [200, 1480]`) is covered along its whole length, and
the refusal is reachable **with DockKeeper's own settings untouched**.

```
Guard: idle — no guardable display (1 whose bottom edge is covered along its whole length by the
       display(s) below; clamping a shared span would trap the pointer)
Tap:   not armed
```

`--diagnostics`, re-deriving in a separate process, agreed. Re-derivation is not trustworthy for *tap
state* (rule 1), but it is a legitimate second opinion on **geometry**, which is what this row turns on.

**The sharp half.** If the refusal had failed, the DELL's band would have been `y ∈ (−3, 0)` — sitting
exactly on the crossing boundary, which is the trapped-cursor failure this row exists to catch. Probing
that precise point, and either side of it:

| posted CG | settled | |
|---|---|---|
| `(800, −1)` — **the point a failed refusal would clamp** | `(800, −1.0)` | not rewritten |
| `(800, −10)` — further into the upper display | `(800, −10.0)` | not rewritten |
| `(800, 40)` — back down into the lower display | `(800, 40.0)` | not rewritten |

The display is left unguarded entirely and the boundary is not held. The arrangement was then restored to
the measured baseline and the guard re-armed over 2 spans.

### §3d row 7 — bottom hot corners  · **reachability CONFIRMED ✅; the trigger half NOT run**

Both bottom corners of the guarded display — `x = −477` in the left overhang and `x = 3360` in the right —
are held at `clampY = −3`, so the pointer cannot reach the corner-most row. That is the mechanism the
shipped disclosure rests on, and it is measured.

**What is not measured is a hot corner configured there failing to fire.** Triggering a hot corner depends
on a real pointer arriving and dwelling, and a posted `CGEvent` is not bounded by the constraints a hand
obeys — the same limit that keeps synthetic input away from summon-by-dwell. The row is therefore recorded
as **half run**: unreachable is confirmed, "and therefore the hot corner never fires" is still INFERRED,
and no shipped disclosure may claim more than that until a hand has tried it.

### Two defects found on the way past

- **[#98](https://github.com/blamechris/DockKeeper/issues/98) — an unrelated CLI edit silently disarms the
  guard, and clears the divergence that would have shown it.** `lockBottomDockToDisplay` is deliberately not
  in `Settings.externallyObservedKeys`, so an external `defaults write` to it correctly diverges rather than
  taking effect — `Divergence: bottom-guard: app=on disk=off`, the DK-FR-015 motivating case, confirmed here
  against the **real running app** for the first time rather than a throwaway harness. But
  `AppState.syncFromSettings()` syncs that key anyway, and only ever runs on a `.settingsChanged` event
  raised by one of the three *observed* keys. So `dockkeeper lock left` swept it: `bottom-guard` went
  `on → off`, the tap released, and `Divergence:` reported agreement at the same moment. Confirmed twice —
  the mirror image (`app=off disk=on`, tap not armed, guard down while disk says on) held afterwards, and
  the state self-healed on relaunch, which was also measured.
- **[#87](https://github.com/blamechris/DockKeeper/issues/87) — first on-device reproduction.** The
  transition-only arm line went stale *within one arm*: the log's last line read `armed over 1 span(s)`
  while the live record read `armed 1m 16s ago over 2 span(s)`. `1m 16s` resolves to the same 23:27:05 arm
  event, so one tap is being described by two instruments that disagree about what it holds, and the log is
  the wrong one. The disagreement is only detectable because `status --live` exists; before #94 the log line
  was the only span-count instrument on the machine and would have been believed.

### Not run, and why

- **§3d row 3 (revoke Accessibility while armed)** — the revoke is an authenticated System Settings action.
  Entering the owner's credentials is not something this session may do, so the row needs the owner's own hand.
- **§3d row 7, trigger half** — see above; needs a real hand.
- **§3d row 2 / R-015 (24 h soak)** — needs the machine otherwise idle, so it is started last and read next
  session. **Never drive it with synthetic `CGEvent.post`**: that measured 52 % against 2 % by hand.
- **§3d row 4 (system disables the tap)** — unchanged; #61 tracks the unbounded re-enable.
- **`IdleReason.mirrorsPreferredDisplay`** — unexercised, see row 6.

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
| **Homebrew upgrade replaces a live copy cleanly** (the cask's `uninstall quit:` stanza, DK-FR-012 interaction) | ✅ CONFIRMED on the 0.9.3 → 0.9.4 upgrade — old copy logged `released` at 18:03:57.828 and the new copy `armed` at 18:03:58.258, so the single-instance guard never saw two live copies | 5 |
| **A real capture flips `CGSIsScreenWatcherPresent`** (ADR-011's standing M6/M12 UNKNOWN) | ✅ CONFIRMED — flag fires < 0.5 s; hide ~2.5 s, restore ~1 s; a pre-existing user auto-hide is left untouched | 5 |
| **Screen-capture hide: `kill -9` mid-capture → relaunch restores auto-hide** (DK-FR-013 S5, issue #29) | ✅ CONFIRMED — `(repaired)` on relaunch, record removed from the domain | — |
| **Screen-capture hide: relaunch *during* a live capture adopts, Dock does not flash** (DK-FR-013 S6) | ✅ CONFIRMED as *no Dock write* — adopt issued none and auto-hide never went off; the far-end visual is still unobserved | — |
| **Screen-capture hide: logout with a hide held → auto-hide off after login** (DK-FR-013 S4) | ⏳ | — |
| **`applicationWillTerminate` / `SIGTERM` restore in the signed bundle** (DK-FR-013 S3) | ⏳ | — |
| UUID stability across ports/adapters/reboot | ⏳ baseline recorded | — |
| Sleep/wake with external connected | ⏳ | — |
| **Mirroring** (§3d row 6) | ✅ CONFIRMED — guard stands down, no band on the visible screen. Reached via `singleDisplay` (the mirror set collapses to one active display), **not** via `mirrorsPreferredDisplay`, which stays unexercised | 6 |
| Clamshell | ⏳ UNKNOWN behavior (open question #6) | — |
| **DK-FR-015 writer half: publish, retract, armed heartbeat** (#96) | ✅ CONFIRMED — all seven steps, with a 20 s idle control; the `max(5, recoveryInterval)` bound **measured** at four consecutive 30 s refreshes | 6 |
| **Accessibility grant survives a Developer ID rebuild** | ✅ CONFIRMED — designated requirements identical across 0.9.4 and the new build; the app's own `AXIsProcessTrusted()` read `granted` at first launch | 6 |
| **Stacked refusal: a wholly-covered bottom edge is left unguarded** (§3d row 5) | ✅ CONFIRMED — first run of this row; the would-be band on the crossing boundary was not rewritten | 6 |
| **`kill -9` while armed releases the pointer** (§3d row 8) | ✅ CONFIRMED — free within 619 ms, nothing persisted | 6 |
| **Bottom hot corners on a guarded display** (§3d row 7) | ◐ HALF — unreachable CONFIRMED (both corners held at `clampY = −3`); the hot-corner *trigger* is INFERRED, needs a hand | 6 |
| **Revoke Accessibility while armed** (§3d row 3) | ⏳ needs the owner's own hand (authenticated action) | — |
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
