# DockKeeper — Decision Log (ADRs)

| | |
|---|---|
| **Status** | Living document |
| **Date** | 2026-07-22 |
| **Owner** | blamechris |
| **Inputs** | [Technical design](technical-design.md) §13/§16, [Preferred-display spike](spikes/preferred-display-spike.md) (owner Decisions 1–3, signed 2026-07-22), kickoff package §9 (ADR-001…005 slots) |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**. Record format per the kickoff package: Context / Options / Decision / Consequences / Evidence / Date / Status.

**Pre-ADR owner decisions.** The spike records three owner-ratified decisions (2026-07-22) that ADRs below build on: (1) pin via the public main-display route, menu-bar move accepted, no SkyLight; (2) "separate Spaces ON" is unsupported-and-explained, never fought; (3) v1.0 = always-reliable edge lock + best-effort pinning. These are treated as CONFIRMED inputs.

---

## ADR-001: Minimum supported macOS version — macOS 14+

**Context.** The kickoff assumed macOS 14+ as a starting point, to be validated. The v0.1 codebase already targets it.

**Options.** macOS 13 (wider reach; `MenuBarExtra`/`SMAppService` both exist there) · macOS 14 (current toolchain default, smaller test matrix) · macOS 15+ (needlessly narrow).

**Decision.** macOS 14 or later.

**Consequences.** Smaller OS test matrix; excludes pre-2018-era unsupported machines only; Intel remains supported where practical (universal binary — INFERRED unproblematic, verify at first release build). Lowering to 13 later would require re-testing `CoreDock` behavior there (UNKNOWN on 13).

**Evidence.** `Package.swift` declares `platforms: [.macOS(.v14)]` — CONFIRMED; v0.1 built and verified on-device against it.

**Date / Status.** 2026-07-22 · **Accepted** (de facto — ratified by the shipped scaffold).

---

## ADR-002: Distribution — Developer ID direct download + Homebrew cask; no Mac App Store for v1

**Context.** The sandbox question had to be settled before choosing distribution (kickoff §6.13: don't pick the App Store until sandbox feasibility is established).

**Options.** Mac App Store · Developer ID notarized direct download · Homebrew cask · source-only.

**Decision.** Primary: notarized Developer ID direct download (`.dmg`/`.zip`). Alongside: a Homebrew cask pointing at the same notarized artifact (also solving CLI install/symlink). Source builds remain supported for developers. Mac App Store: rejected for v1.

**Consequences.** No sandbox constraints on `dlsym`/`killall`; requires hardened runtime + notarization pipeline (release checklist); no App Store discovery; auto-update deferred (Sparkle would add a network call — needs its own ADR post-v1 to honor the no-unnecessary-network principle).

**Evidence.** Sandbox blocks signaling other processes (`killall Dock`) — CONFIRMED policy; private-API use fails App Store review — CONFIRMED policy; a sandboxed CoreDock-free build would have no working restore mechanism at all (TDD §13). No entitlement conflicts for notarization — **CONFIRMED 2026-07-23**, the verification this line originally deferred ("INFERRED, verify at first notarization run"). Three submissions, and it is worth naming them separately because the docs elsewhere cite only the middle one:

- `eb36ef6c` (`DockKeeper-0.1.0.dmg`) — **Invalid**, solely for the then-unsigned CLI inside the image. Fixed in `package-dmg.sh`.
- `b981d4de` (`DockKeeper-0.1.0.dmg`) — **Accepted**, mounted app assessed Gatekeeper `Notarized Developer ID`. A dry run on the version-0.1.0 artifact; this is the id quoted in TDD §13 and [release checklist](release-checklist.md) §5.
- `05a4dd99` (`DockKeeper-0.9.0.dmg`) — **Accepted**, and this is the one that actually shipped: the release asset was uploaded 109 seconds later.

The entitlement set passed on both Accepted submissions, so the claim holds regardless of which is cited. Scope it precisely: what is confirmed is the *entitlements*, not that the shipped app carried a ticket of its own — `05a4dd99`'s app did not, which is the v0.9.0 defect fixed for v1.0.0 (TDD §13, [release checklist](release-checklist.md) §4).

**Date / Status.** 2026-07-22 · **Accepted** · evidence updated 2026-07-25 with the first notarization result.

---

## ADR-003: Dock restoration mechanism — private CoreDock API with public fallback

**Context.** There is no public API to set the Dock's edge or display. Kickoff rule 7: *"Use public macOS APIs unless an ADR explicitly approves otherwise"* — this is that ADR. The spike's owner decisions implicitly approve the approach; this record formalizes it.

**Options.**
1. `defaults write com.apple.dock orientation` + `killall Dock` as primary — public-ish, but visibly restarts the Dock and destroys Dock state on every correction.
2. Accessibility-driven interaction (AX drag) — needs the heavyweight permission v1 otherwise avoids entirely; fragile against Dock UI changes.
3. Private `CoreDock` C API (`CoreDockSet/GetOrientationAndPinning`), resolved at runtime via `dlsym`, with option 1 as automatic fallback.
4. Private SkyLight/CGS — rejected by owner (Decision 1) for fragility.

**Decision.** Option 3 for edge lock. For display pinning: public `CGDisplayConfiguration` main-display relocation (owner Decision 1) — no private APIs in the pinning path.

**Consequences.** Deviates from "public APIs strongly preferred" on the edge path; accepted because the failure mode is graceful (unresolved symbol → fallback + `Degraded` state, not a crash) and the user experience of the primary path is categorically better (live, flicker-free — the fallback restarts the Dock visibly). Ongoing obligations: per-macOS-release smoke test (risk R-004), explicit `dlopen` of HIServices for non-AppKit processes (spike hardening), Mac App Store remains blocked (see ADR-002).

**Evidence.** Symbols resolve and work live, flicker-free, on-device — CONFIRMED (spike, macOS 26.5 Apple Silicon); fallback path works — CONFIRMED; symbol availability requires HIServices loaded — CONFIRMED (spike).

**Date / Status.** 2026-07-22 · **Accepted — ratified by the owner 2026-07-22.** This records the explicit rule-7 sign-off for private-API use on the edge path. Basis: the only alternative primary (defaults + `killall`) visibly restarts the Dock on every correction — strictly worse for a utility whose entire job is invisible reliability — while the private path fails gracefully (unresolved symbol → automatic fallback + `Degraded`, never a crash). Standing obligations: per-macOS-release CoreDock smoke test (R-004), `dlopen` HIServices hardening, and no further private-API use without a new ADR.

---

## ADR-004: Display identity — multi-identifier fingerprint with scored matching

**Context.** A preferred display must be recognized across reconnects, docks, adapters, and reboots. UUID stability across those paths is UNKNOWN (kickoff §6.6 explicitly forbids assuming it), and v0.1's bare-UUID storage — with an unstable `"cg-<id>"` pseudo-UUID fallback that can be persisted — is insufficient.

**Options.** Bare UUID (status quo) · display name only (collides on identical models) · multi-identifier fingerprint (UUID + vendor/model/serial + localized name + built-in flag) with scored matching, repair, and an ambiguity refusal.

**Decision.** Fingerprint + scored matching per TDD §7.2: accept the best candidate iff score ≥ 70 and it is the unique maximum; on fallback-evidence matches, rewrite the stored fingerprint with fresh values (stale-preference repair); on ties (e.g. identical twin externals with serial 0), never guess — ask the user to re-pick. When the preferred display is absent, no fallback display is ever selected (TDD §7.4).

**Consequences.** Migration required (`preferredDisplayUUID` → fingerprint with only `uuid` populated); score thresholds are PROPOSED and must be tuned on hardware (R-003); slightly more persistence complexity for materially better resilience.

**Evidence.** All constituent APIs CONFIRMED available (TDD §7.1); serial-number reliability INFERRED (frequently 0 on consumer panels); UUID stability UNKNOWN — the design assumes the worst case by construction.

**Date / Status.** 2026-07-22 · **Accepted — implemented 2026-07-23** (`DisplayFingerprint`/`FingerprintMatcher`/`DisplayIdentityResolver`, migration + legacy mirror, unit-tested); score thresholds remain PROPOSED until M6 hardware tuning.

---

## ADR-005: Monitoring — hybrid event-driven with a 30-second polling safety net

**Context.** Kickoff rule 19: avoid continuous polling unless evidence shows events are insufficient. v0.1 ships a 2 s poll — polling-first in spirit, inverting the burden of proof. Whether events ever miss in practice is UNKNOWN.

**Options.** Event-only (risks standing drift on gaps — UNKNOWN frequency) · polling-only (rejected outright, rule 19) · hybrid with a conservative interval.

**Decision.** Events are primary (catalog in TDD §8.1); the poll is a safety net only, default interval **30 s** (up from v0.1's 2 s). Every poll-caught drift (as opposed to event-caught) is counted locally; that evidence later justifies lengthening toward 60 s+/event-only — or shortening, if real gaps appear.

**Consequences.** A drift landing in an event gap can stand for up to 30 s — accepted (rare, and invisible correction beats constant wakeups); the interval stays user-tunable via the existing `recoveryInterval` setting so field-tuning needs no release.

**Evidence.** All event sources CONFIRMED wired in v0.1; poll work per tick is two C calls — INFERRED negligible either way (the objection to 2 s is principle, not measured cost); gap frequency UNKNOWN pending the drift-source counter.

**Date / Status.** 2026-07-22 · **Accepted** (supersedes the v0.1 de facto 2 s choice; implementation pending).

---

## ADR-006: Disabling pinning (or quitting) leaves the display arrangement as-is

**Context.** A pin changes which display is *main*, and `CGCompleteDisplayConfiguration(.permanently)` persists that change. TDD open question #5: should disable/quit snapshot and restore the pre-pin arrangement?

**Options.** Leave-as-is · snapshot-and-restore on disable/quit · prompt the user each time.

**Decision.** Leave-as-is for v1.0. Disabling means "stop correcting," never "make new changes." The Preferences/menu copy states this plainly.

**Consequences.** No hidden snapshot state that can rot — a stale arrangement restored after the display topology changed would be worse than no restore at all (INFERRED; the failure modes multiply with disconnected displays). If the user wants the old arrangement back, it is one drag in System Settings ▸ Displays. A restore-on-disable option can be revisited post-v1 if users ask (would need topology-validity checks).

**Evidence.** Consistent with owner Decision 3 ("reliable and honest") and AGENTS rule 20 (predictability first); no competitor-behavior data on this edge (UNKNOWN — DockLock's disable behavior not investigated).

**Date / Status.** 2026-07-22 · **Accepted** (owner-delegated call, 2026-07-22).

---

## ADR-007: `enabled` is the single switch; `autoRecover` is retired

**Context.** v0.1 has two overlapping switches: `enabled` and `autoRecover` (which gates only the poll, while events always reconcile) — TDD §11 and open question #9 flagged the confusion.

**Options.** Keep both with sharpened meanings ("watch but only fix when I click") · merge into a single `enabled` switch.

**Decision.** Single switch: `enabled` means DockKeeper corrects drift (events + poll); off means it touches nothing (DK-FR-004). `autoRecover` is removed from the UI and settings schema with the M4 recovery-engine work.

**Consequences.** Simpler, honest mental model; the hypothetical manual-approval mode is cut for v1 (no evidence of demand; reintroducible later as a distinct feature if ever wanted). No user-facing migration burden — there is no public release yet; the leftover defaults key is simply ignored, and `recoveryInterval` remains the poll-tuning knob (ADR-005).

**Evidence.** Two-switch confusion observed in design review (TDD §11 — CONFIRMED by inspection); everything else INFERRED/PROPOSED as a UX judgment.

**Date / Status.** 2026-07-22 · **Accepted** (owner-delegated call, 2026-07-22).

---

## ADR-008: Pursue separate-Spaces-mode pinning for full DockLock replacement

**Context.** Owner directive 2026-07-23: DockKeeper aims to **completely replace** DockLock. Phase-1 investigation established that DockLock Lite/Plus operate *only* with "Displays have separate Spaces" ON (the macOS default), while DockKeeper v1 declines pinning there (Decision 2A) — the two products cover opposite modes ([investigation §3](product-investigation.md)). Full replacement therefore requires covering the default mode.

**Options.** Stay v1-scoped (decline forever) · pursue separate-Spaces pinning spike-first · rush a mechanism without a spike.

**Decision.** Open the parity workstream (implementation-plan **M8**) now, spike-first per the kickoff discipline: [docs/spikes/separate-spaces-pinning.md](spikes/separate-spaces-pinning.md). **Decision 2A stands unchanged for v1.0** — it ships with honest declining; the parity feature targets the next minor release once (and only if) a mechanism meets the reliability bar.

**Consequences.** Early spike results: Dock-host *detection* is CONFIRMED possible with public API and zero permissions (visibleFrame insets); no direct private "set Dock display" call exists under known names, so recovery will be a re-summon mechanism — possibly requiring an **opt-in Accessibility permission for this mode only** (v1's zero-permission story is unaffected). Mechanism choice and permission posture will be **ADR-009** after the spike. The bar remains owner Decision 3: reliable and honest — no oscillation, no pointer fights; if no candidate meets it, the honest decline stays and the gap is documented.

**Evidence.** Investigation P-002 (CONFIRMED: competitor requires the mode); detection probe CONFIRMED; symbol sweep CONFIRMED-absent (spike doc).

**Date / Status.** 2026-07-23 · **Accepted** (owner-directed; mechanism for left/right resolved same day → ADR-009; bottom-mode mechanism still open).

---

## ADR-009: Separate-Spaces pinning ships for left/right Docks via main-display relocation; bottom stays declined

**Context.** ADR-008's spike produced a decisive on-rig result the same day ([spike](spikes/separate-spaces-pinning.md)): with "Displays have separate Spaces" ON, macOS treats Dock edges **asymmetrically** — a **bottom** Dock is per-display and pointer-summoned (and the summon demonstrably fails on shared edges, e.g. stacked portrait-above arrangements), while a **left/right** Dock homes to the **main display** and moved with it in both directions when we relocated main (CONFIRMED, 2-display rig). The pointer cannot summon a left/right Dock to another display (owner-observed), so there is no drift source to fight.

**Options.** Keep declining all pinning in this mode (Decision 2A as written) · ship left/right pinning now via the existing mechanism and keep declining bottom with guidance · build a pointer/AX summon mechanism for bottom first.

**Decision.** With separate Spaces ON: pin via `MainDisplayPinner` **when the lock edge is left or right**; decline **only bottom**, with copy that offers both remedies ("move the Dock to the left/right edge, or turn the setting off"). Shipped 2026-07-23 (`decide(snapshot:resolution:dockEdge:)` gate + tests).

**Consequences.** The macOS *default* mode is now covered for left/right users with zero new mechanisms, zero permissions — and in this mode the pin doesn't even move menu bars (each display keeps its own), making it *less* intrusive than Spaces-off pinning. Decision 2A is narrowed, not violated: we still never fight the OS — the OS itself homes left/right Docks to main. The uncovered cell shrinks to bottom-Dock-with-separate-Spaces (DockLock's niche); its candidates (pointer summon, AX) stay queued in the spike at reduced priority, and the honest decline remains its behavior until a mechanism meets the reliability bar.

**Evidence.** CONFIRMED on-rig 2026-07-23: left Dock followed main both directions; bottom Dock did not follow main; left-edge and shared-bottom-edge pointer summons failed; leftmost-arrangement hypothesis falsified (spike results table).

**Date / Status.** 2026-07-23 · **Accepted and shipped.**

---

## ADR-010: Opt-in window restore across a pin, via a feature-scoped Accessibility permission

**Context.** A pin makes the preferred display the macOS *main* display by re-basing every display's origin (ADR-003, `MainDisplayPinner`). Windows keep their global coordinates while the coordinate grid moves underneath them, so some land on the other screen — owner-observed 2026-07-23, identical to changing the primary display in System Settings ([DK-FR-002](behavior-specification.md#dk-fr-002-preferred-display-pinning-best-effort), TDD open question #11). *Reading* window geometry is public and permission-free (`CGWindowListCopyWindowInfo`); *moving another app's window back* is not — there is no public API to set a foreign window's position except the Accessibility (AX) API. This is the first permission the product would touch, against a design whose headline property is "no privacy-gated permission at all" (TDD §10).

**Options.**
1. Do nothing — document the shuffle as an inherent consequence (status quo; ADR-006 already leaves arrangement changes alone).
2. Restore automatically — take the permission for everyone; violates the zero-permission default and TDD §10's "no onboarding permission flow."
3. **Opt-in restore, feature-scoped Accessibility** — off by default; when the user enables it *and* grants AX, DockKeeper snapshots geometry before the pin and moves each window back; otherwise it silently no-ops.
4. Private window-move APIs (SkyLight/CGS) — rejected by the same reasoning as ADR-003 Decision 1 (fragility, App Store, owner's standing "no SkyLight").

**Decision.** Option 3. `preserveWindowLayout` (Bool, default **false**) gates the feature. The core `WindowLayoutPreserver` (@MainActor) snapshots layer-0 windows' owner-PID and global bounds via `CGWindowListCopyWindowInfo`, assigns each to its max-overlap display, and — only when `AXIsProcessTrusted()` — restores each window on the display it belonged to by the display's re-base delta, via `AXUIElementCreateApplication` → `kAXPositionAttribute`. The decision math (display assignment, delta, restore plan, frame-tolerance matching) is pure and unit-tested; the `CGWindowList`/AX reads and writes are thin wrappers. The preserver **never prompts** — the Advanced-tab toggle shows the contextual explanation *before* enabling (TDD §10), fires the system prompt once on enable when untrusted, and offers a deep link to the Accessibility pane. The toggle may stay ON while the grant is pending or after it is revoked; the preserver simply no-ops until trusted, and the caption says "waiting for permission." Privacy: window titles/names are never read or stored, and only a failure *count* is logged (TDD §12).

**Consequences.** The zero-permission default is preserved — AX is requested only if the user opts in, and only for this one job (moving windows back). Graceful degradation is the norm, not the exception: missing grant, revoked grant, AX-unreachable app, or a window that already moved all resolve to a silent per-window no-op, never a crash or a prompt storm. The full permission model TDD §10 reserved for a future follow-window feature (contextual explanation before prompting, denial UX, revocation detection) is now partially realized here, feature-scoped. Disabling the toggle stops future restores but never re-shuffles windows (consistent with ADR-006's leave-as-is stance). Standing obligations: verify the AX coordinate-system assumption on hardware (see Evidence); the `restoreDelay`/reconcile machinery already rate-limits pins, so no new retry-storm surface.

**Evidence.** `CGWindowListCopyWindowInfo` bounds are global CG top-left coordinates — CONFIRMED (API docs; same space as `CGDisplayBounds`, which `DisplayInfo.frame` already uses, so overlap assignment is direct). Re-base delta is uniform (`−target.originBefore` for every display) — CONFIRMED by construction from `MainDisplayPinner.liveApplyMain`, unit-tested on the owner's rig geometry. AX uses the same global CG top-left coordinate space as `CGWindowList`, so `kAXPositionAttribute` can be set to `oldOrigin + delta` directly — **INFERRED** (common AX behavior; not yet verified on hardware — the pure math is unit-tested, the AX write path is not). Reading geometry needs no permission; moving foreign windows needs AX — CONFIRMED (no public alternative exists).

**Date / Status.** 2026-07-23 · **Accepted (owner-directed 2026-07-23)** — implemented (`Settings.preserveWindowLayout`, `WindowLayoutPreserver`, `RecoveryCoordinator` wiring, Advanced-tab UI, pure-math unit tests); resolves open question #11. The AX write path stays INFERRED until hardware validation (M6).

---

## ADR-011: Hide the Dock during screen capture via a private screen-watcher flag + Dock auto-hide, opt-in

**Context.** DockLock Lite hides the Dock during screen sharing / meetings — parity gap **G5** ([parity assessment](parity-assessment.md), [screen-share-hide spike](spikes/screen-share-hide.md)). The spike settled feasibility and deferred the trade to this ADR. Two facts drive it: (1) true **screen-capture** detection has **no public API** — the reliable signal is the private SkyLight `CGSIsScreenWatcherPresent` (the public `CMIODevicePropertyDeviceIsRunningSomewhere` detects a **camera**, i.e. a *video call*, which is a different trigger, not a substitute); (2) hiding is done by toggling the Dock's own auto-hide via the already-CONFIRMED `CoreDockSetAutoHideEnabled`, so the "hide" side needs no new mechanism. This is the second private-API decision after ADR-003 (CoreDock) — the kickoff rule-7 bar.

**Options.**
1. Do nothing — leave G5 open (status quo).
2. Reframe as "hide during **video calls**" using the **public** camera signal — zero private APIs, but it detects the wrong event (camera on ≠ screen being captured) and would hide the Dock during every FaceTime call whether or not the screen is shared.
3. **Screen-capture detection via private `CGSIsScreenWatcherPresent` + Dock auto-hide toggle, opt-in, off by default** — the honest match to "hide while screen sharing," degrading safely when the symbol is absent.
4. Both signals (capture **and** camera) — more surface, more false positives, no clear user benefit for v1.

**Decision.** Option 3. A new pure `ScreenCapture` wrapper resolves `CGSIsScreenWatcherPresent` from SkyLight with the exact `dlsym` pattern as `CoreDock` (`isAvailable`, `isCapturing()` → `false` when unavailable). A dedicated 3 s poll (there is **no** capture-state event source — Principle 19 is satisfied by that absence, not bypassed) feeds a `ScreenShareHider` whose behavior is a **pure `decide(capturing:weHidIt:currentAutoHide:) -> {none, hide, restore}`** core, exhaustively unit-tested. The **mandatory** interaction rules:

- **Only hide** if capturing **and** the feature is on **and** we haven't already hidden **and** the user's current auto-hide is **off**. Never toggle if the user already runs auto-hide — and record that we did **not** hide, so we never later "restore" (turn off) something we didn't change.
- **On capture-stop, restore** (auto-hide → off) **only if we hid it**, then clear the flag. Because we only ever hide from a prior state of "off," the restore target is always "off" — a single `weHidIt` flag is sufficient; no prior value is stored.
- **Idempotent**: repeated same-state ticks produce `none`.
- **Never leave the Dock hidden**: turning the feature off, or disabling DockKeeper, restores if we hid it.

Settings: `hideDockDuringScreenShare` (Bool, default **false**, registered). The Advanced-tab toggle is disabled with a note when `ScreenCapture.isAvailable` is false. The poll runs only while the feature is on, DockKeeper is enabled, and the symbol resolved.

**Coordinator interaction (verified, no machine change).** The auto-hide toggle is a **direct** `CoreDock` call from `ScreenShareHider` — it does **not** go through `DockMonitor`/`RecoveryCoordinator`. It cannot cause a drift correction: auto-hide changes neither the Dock **orientation** (`CoreDockGetOrientationAndPinning`, which drives `currentEdge`) nor the **main display** (`CGMainDisplayID`) / display bounds (`CGDisplayBounds`) that the pin decision reads. A visibleFrame change from auto-hiding *could* fire `NSApplication.didChangeScreenParametersNotification` → `.screenParametersChanged`, but that reconcile is a guaranteed **no-op** (orientation unchanged → no `setEdge`; main display unchanged → terminal pin decision), so no effect is applied, no oscillation budget is consumed, and no `RecoveryMachine` change is needed. The spike's "auto-hide blinds the `visibleFrame` host sensor" gotcha applies only to the *unshipped* separate-Spaces bottom-Dock detection (G1); the shipped pinning path uses `CGDisplayBounds`/`CGMainDisplayID`, which auto-hide does not touch. A `CoreDock.getRect()` wrapper (over `CoreDockGetRect`, `@convention(c) (UnsafeMutablePointer<CGRect>) -> Void`) is added as the auto-hide-proof host sensor for that future work, but nothing calls it in v1.1.

**Consequences.** Deviates from "public APIs strongly preferred" on the detection path — accepted because the failure mode is graceful (unresolved symbol → feature unavailable, toggle disabled with a note, never a crash) and there is no public substitute for the screen-capture event. Standing obligations mirror ADR-003: per-macOS-release smoke test that the screen-watcher symbol resolves and the flag flips on a real capture (R-004, [release checklist](release-checklist.md)). Scope is deliberately narrow: **screen capture only**, not camera/video-call presence (that stays a possible separate future feature, not this one). The 3 s poll is two cheap C calls and runs only while the feature is on and a capture may be underway.

**Evidence.** `CGSIsScreenWatcherPresent` resolves and returns `false` at rest — CONFIRMED on-rig (spike, macOS 26.5, Apple Silicon). `CoreDockSetAutoHideEnabled` toggles auto-hide and read-back via `CoreDockGetAutoHideEnabled` confirms the write — CONFIRMED (spike). The **true case** — that the watcher flag actually flips when a real capture starts, its latency, and which apps trip it (QuickTime, Zoom, Teams, Screen Sharing.app) — is **UNKNOWN pending on-device verification** (folded into M6/M12; not started here to avoid a capture prompt interfering, and it is a documented hardware-matrix cell). The pure `decide` table is CONFIRMED by unit test (all 8 input combinations).

**Amendment 2026-08-17 (see [ADR-013](#adr-013-borrowed-system-state-is-persisted-before-the-borrowing-write-and-reconciled-at-launch-termination-hooks-are-an-optimization-not-the-mechanism)).** Two statements above are corrected; the invariant itself is unchanged and remains binding.

1. *"a single `weHidIt` flag is sufficient; no prior value is stored."* The sufficiency argument was about the restore **value** — still correct, it is always "off" — and silently carried with it the **fact that we hid at all**, which is a different quantity and is not derivable from anything observable once the process is gone.
2. *"Never leave the Dock hidden: turning the feature off, or disabling DockKeeper, restores if we hid it."* This enumerates two exits as if the set were complete. It is not: SIGKILL, Force Quit, a crash, and the logout kill are not in it, and on those paths the in-memory flag dies with the process — leaving auto-hide **on** with `weHidIt == false`, a state `decide` then reads, correctly per the rules above, as "the user runs auto-hide" forever (GitHub issue #29).

**The flag is now durable** (`Settings.screenShareHideRecord`, written before the hide and cleared after the restore) and a launch-time `ScreenShareHider.repair` reconciles it. `decide` and its 8-row table are **unchanged** — the repair runs once per process, before the steady state, and hands `decide` a `(weHidIt, auto-hide)` pair that already agrees. See ADR-013 and [DK-FR-013](behavior-specification.md#dk-fr-013-restore-borrowed-dock-auto-hide-across-process-death).

**Date / Status.** 2026-07-23 · **Accepted (owner-ratified 2026-07-23)** — implemented (`ScreenCapture`, `ScreenShareHider` with pure `decide`, `CoreDock` auto-hide + `getRect` wrappers, `Settings.hideDockDuringScreenShare`, AppState poll wiring, Advanced-tab UI, exhaustive `decide` unit tests). The true-case detection stays **UNKNOWN** until hardware validation (M6/M12). Standing obligation: per-macOS-release screen-watcher smoke test (R-004).

---

## ADR-012: Single-instance guard in-process at `App.init()`; `LSMultipleInstancesProhibited` withheld

**Context.** Nothing stops two DockKeeper processes running at once, and the product has no guard against it.

*The vector the owner actually hit — two bundles at two paths.* The login item is registered to `/Applications/DockKeeper.app` (v0.9.0) — **CONFIRMED** via `sfltool dumpbtm`, which lists that path as an enabled login item — while `~/Projects/DockKeeper/dist/DockKeeper.app` (v0.9.1) is launched separately from Finder. Two bundles, one bundle identifier, both registered with LaunchServices; opening the second while the first runs starts a second process.

*The rule underneath it, which is the part that generalizes.* **LaunchServices keys its "is this app already running?" test on the bundle's inode identity, not on its path and not on its bundle identifier** — **CONFIRMED** on this machine, two independent ways. (1) The running process's launchd job label is `application.com.dockkeeper.app.748253205.748253215`, and `748253205` / `748253215` are exactly the inodes of `dist/DockKeeper.app` and of its `Contents/MacOS/DockKeeper`. (2) Reproduced with a throwaway control bundle: rebuild at the **same path** → inode changed → `open` **LAUNCH**ed a second process; `open` again with the inode unchanged → **REOPEN**, no new process.

*The second vector, from that same rule — rebuild-in-place.* `Scripts/build-app.sh` does `rm -rf "$APP"` and then rebuilds, so every build mints a new inode pair. `Scripts/run-app.sh` therefore **adds** a process on every dev iteration while one is running instead of replacing it (CONFIRMED by the control above). Nothing in the script guarded against that — it built and `open`ed unconditionally — and the extra process went unnoticed because `LSUIElement` hides it; the investigation's own initial belief that the script harmlessly relaunched the stale binary was refuted by that control. End users meet the identical mechanism on **upgrade-in-place**: drag a new copy from the DMG over `/Applications` while the old one runs, then open it.

`LSUIElement` makes every form of this maximally confusing: no Dock tile, no ⌘-Tab entry, no Force Quit row. The only symptom is two identical menu-bar icons, and "Quit DockKeeper" terminates exactly one of them. Two live instances also mean two engines writing the Dock — two `RecoveryCoordinator`s, two poll timers, two `CoreDock` writers racing on the same edge — which is the invariant §9 of the [technical design](technical-design.md) states as fact for a single process: *"There is exactly one owner of reconciliation state (the coordinator)."*

**What is and is not established (rule 5).** The **mechanism** is CONFIRMED, as above. That it is what produced the two icons the owner reported is **not**: unified-log retention on this machine begins 2026-08-16 22:48 and does **not** cover the original observation, and inside the retained window the `/Applications` copy never launched at all (0 occurrences of its job label, 0 of its path). An **UNREFUTED alternative explanation** for one of the two icons is the competitor: `pro.docklock.lite` is still an **enabled** login item in both BTM and System Events although the bundle it points at is gone: `/Applications/DockLock Lite.app` was absent on 2026-08-17 (CONFIRMED — `ls`; it was recorded as installed-but-not-running on 2026-07-23 in R-012, so the owner removed it in the interim) — so one of the two Dock-managing menu-bar icons may have been DockLock Lite rather than a second DockKeeper. This ADR rests on the mechanism, which is reachable by both vectors regardless of which one produced that particular sighting; it does not rest on the causal story, and the causal story should not be quoted as settled.

**Options.**

1. **Do nothing** — document the duplicate as user error (install hygiene) and leave `run-app.sh` as is. Rejected: the end-user path (upgrade-in-place) needs no mistake at all, and the `LSUIElement` posture removes every affordance the user would normally use to notice or fix it.
2. **`LSMultipleInstancesProhibited` in `Resources/Info.plist`** — let LaunchServices refuse the second launch outright. **Rejected for this decision and deliberately withheld** (kept as a gated follow-on, not shipped here): Apple's *Launch Services Keys* reference gives the key a second meaning nobody wants — *"If a user in another session is running the app, Launch Services returns a `kLSMultipleSessionsNotSupportedErr` error."* Two fast-user-switched accounts each have their own Dock and each legitimately want their own DockKeeper, and because the app is `LSUIElement` a refused launch has **no window, no Dock bounce, no Force Quit row and no error surface whatsoever — it simply never appears**. Trading "two instances" for "zero instances, silently, for the second user" is a worse bug than the one being fixed. It would also do nothing on the owner's machine until the 0.9.0 copy is gone, since the key must be present on *every* registered copy to bite. Gated behind manual test 1 in [test-strategy.md](test-strategy.md) (second account, fast user switching).
3. **`flock` lockfile** in `~/Library/Application Support/DockKeeper/instance.lock`. Rejected for this PR: a lock keyed on a **recycled pid can brick launch permanently** — the app then refuses to start until the user finds and deletes a file they have no reason to know about — and a `probe()` that takes `LOCK_EX` can abort the very launch it was run to diagnose. It is the only mechanism that would also cover unbundled `swift run` builds, so it stays queued as a low-priority follow-on with those two failure modes designed out (read-only probe, holder verified by **identity** via `NSRunningApplication(processIdentifier:)?.bundleIdentifier` rather than by liveness).
4. **Apple-Event URL forwarding** — have the deflected instance catch its pending `dockkeeper://` URL and hand it to the incumbent before exiting. **EXPERIMENTALLY REFUTED**: Apple Event dispatch is gated on `NSApplication.run()`, not on the run loop, so a `kAEGetURL` handler installed before `NSApplicationMain` plus a 2.1 s run-loop spin caught **nothing**, twice. The URL loss is documented in DK-FR-012 rather than engineered around.
5. **Version-aware handoff** — the newer build displaces the older. Rejected: a launch that silently kills the app you were using is a worse surprise than the one being fixed. Registration hygiene (one canonical bundle) is the real answer.
6. **Pure in-process guard at `App.init()`, plus a fixed `run-app.sh`** — chosen.

**Decision.** Option 6.

- **Pure decision core.** `InstanceGuard.decide(selfPID:selfLaunchDate:peers:arguments:environment:)` in `DockKeeperCore` returns `.proceed` or `.yield(to:)`. Seniority is the single lexicographic tuple `(hasStartTime, startTime, pid)`, which is **a total order by construction** — every instance therefore independently agrees on the same incumbent, so exactly one survives. A predicate that compares some pairs by date and others by pid is cyclic the moment one date is absent, and a cycle means all instances yield and **none** survives. Date precedes pid because pids wrap near 99999, and a lowest-pid-wins rule would send a fresh pid 3 past an incumbent pid 99998. A process with **no obtainable start time sorts last**, so it can never rank itself at `.distantPast` and beat a real incumbent.
- **Every live process is given a start time, so the "no date" class is empty in practice.** `NSRunningApplication.launchDate` is `nil` for the entire lifetime of a directly-`exec`ed bundle binary — in its own view *and in every peer's view* (both measured) — and a dateless class cannot be ordered correctly in both directions at once: rank it first and a direct-`exec` newcomer outranks the registered incumbent; rank it last (as above) and a direct-`exec` **incumbent** is outranked by every later registered launch, and both run; make the comparison pairwise-conditional and it becomes the cyclic predicate with zero survivors. The trilemma is dissolved rather than picked from: `SingleInstance` substitutes the kernel process start time (`sysctl` `KERN_PROC_PID`, unprivileged and cross-process — the app is deliberately unsandboxed) whenever LaunchServices has no date, for peers and for self alike. That value is a pure function of the pid, so every process computes the same rank for the same peer and the order stays global. The `hasStartTime` component survives only as the fallback for the residual case where `sysctl` also fails.
- **System interaction behind an adapter** (rule 8). `SingleInstance.yieldIfDuplicate()` in the app target does the `NSRunningApplication.runningApplications(withBundleIdentifier:)` read and the `exit()`; nothing about LaunchServices leaks into the core. Self pid comes from `ProcessInfo.processInfo.processIdentifier`, never `NSRunningApplication.current.processIdentifier` — the latter is `-1` at `App.init()` for a directly-`exec`ed bundled binary (measured), and a `-1` self rank silently outranks every real peer.
- **Called from `DockKeeperApp.init()`**, strictly after `Diagnostics.runIfRequested()` and strictly before anything else. The ordering is load-bearing in both directions: after diagnostics because `--diagnostics` is a support flow run *while* an instance is live (`InstanceGuard.oneShotFlags` is the one shared set, so the guard and `Diagnostics` cannot drift apart); and here rather than in an `AppDelegate` hook because `@StateObject private var state = AppState()` stores an autoclosure that is evaluated when the scene graph is built — by `applicationWillFinishLaunching` the duplicate has already started the monitor and coordinator and moved the real Dock, and by `didFinishLaunching` it also owns a visible status item.
- **Exit is silent and successful.** `exit(EXIT_SUCCESS)` with a stderr notice and one unified-log line; no alert and no window, because an `LSUIElement` agent has nothing to show and a modal at launch would be worse than the silence. `EXIT_SUCCESS` matches `Diagnostics` — a login item that correctly deferred to the incumbent must not read as a failed launch. Never `NSApp.terminate(nil)`: there is no `NSApplication` yet, and merely reading `NSApplication.shared` would instantiate one.
- **Escape hatch:** `DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES=1`, checked before any side effect, so the override can never itself become the thing that blocks a real launch. Environment variable only, no CLI flag.
- **`Scripts/run-app.sh` quits the previous `dist/` build before rebuilding** — this is the fix for the second vector, not hygiene. Processes are matched by exact process name and then **verified by executable path**; never `pkill -f`, which regex-matches the whole argv: matched on the name it also kills `/Applications/DockKeeper.app` (the user's daily driver), and matched on the dist path it also kills any `codesign`, `lldb` or `strip` invocation naming that path. A survivor that ignores `SIGTERM` is escalated to `SIGKILL` and, failing that, the script **exits non-zero** rather than rebuilding — otherwise it would `rm -rf` the bundle under a live process and `open` a replacement the guard immediately deflects, which is precisely the "runs nothing at all" outcome the quit step exists to prevent. `SIGKILL` is safe only because the pid list is path-exact. No `osascript … to quit`, which would introduce a TCC Automation prompt into the dev loop of an app whose headline property is that it needs no permission.
- **`--diagnostics` gains an `Other instances:` line**, strictly read-only (it takes nothing and perturbs nothing the guard consults), because an `LSUIElement` app gives the user no Force Quit row in which to check for themselves.
- **Not shipped:** `LSMultipleInstancesProhibited` (option 2), any lockfile, any URL forwarding, any acknowledgement UI.

**Consequences.** Duplicates become unreachable **via LaunchServices** — not impossible. The honest residue:

- **Unbundled builds are neither blocked nor detected.** `swift run DockKeeper` and a bare `.build/debug/DockKeeper` have `bundleIdentifier == nil`, so such a process is invisible as a peer *and* skips the check as a caller, and will run a full engine beside the `.app`. Deliberate: it keeps the debugger loop working with zero flags, and the alternative is option 3's brick-the-launch risk.
- **~~Per-session scoping is INFERRED, not measured.~~** *Superseded 2026-08-18 — see Amendment below.* The guard is safe under fast user switching only if `NSRunningApplication.runningApplications(withBundleIdentifier:)` is session-scoped. If it is not, the second user's launch exits `EXIT_SUCCESS` with a stderr notice no Finder or login-item launch ever displays — the identical "zero instances, silently, for the second user" outcome option 2 was rejected for, shipped. Manual test 1 is therefore a gate on **this** decision, not only on the `LSMultipleInstancesProhibited` follow-on.
- **A deflection is indistinguishable from a launch to every caller.** `open` returns 0 either way (measured: rc 0 in 0.09 s while the child exited at t+0.003 s). `EXIT_SUCCESS` is correct — a login item that correctly deferred must not read as a failed launch to launchd/BTM — but nothing downstream, including `run-app.sh`, a Shortcut, or a script, can test for the guard by exit status. Anything that must know has to check *before* launching.
- **A wedged-but-alive instance makes the app unstartable from the GUI.** It keeps a valid start time, so it outranks every newcomer, and `LSUIElement` leaves no Force Quit row to kill it with. `pkill -9 -x DockKeeper` or the pid from `--diagnostics` is the recovery — plain SIGTERM is now ignored (ADR-013), so the kill must be uncatchable; the env-var escape hatch cannot be set for a Finder or login-item launch. Detecting unresponsiveness at `App.init()` is deliberately not attempted — it is not cheap, and a wrong answer would evict a healthy instance.
- **Detection is not atomic.** If B queries LaunchServices before A has registered, B sees no peer and both proceed. The total order guarantees one survivor only among instances that can see each other. Only a kernel primitive or a bootstrap name closes that window, and both were cut.
- **The guard yields to the most *senior* instance, not the newest version.** With 0.9.0 running, launching 0.9.1 exits 0.9.1 and leaves 0.9.0 in charge. Registration hygiene is the answer, not a smarter guard.
- **A pending `dockkeeper://` URL carried by a deflected launch is dropped silently** (option 4 is refuted). This needs the explicit `open -a <copy>.app dockkeeper://…` form; plain `open dockkeeper://…` and `open -b com.dockkeeper.app` route to the running instance without spawning anything.
- **Scope is `Sources/DockKeeper/` only.** `dockkeeper-cli` remains a legitimate third process — it runs its own engine and reaches the app only through KVO on the shared defaults suite — and `StatusSummary.live()` is documented to work with the app not running. The guard must never be applied to either; whoever adds a `dockkeeper daemon` subcommand will reach for it, so the code says so.
- **The guard does not repair the damage two instances cause**, it makes it far less reachable. Pause is still process-local, quitting mid-capture still leaves Dock auto-hide on (a *single-process* defect, and arguably higher user impact than this ADR), seven settings are still absent from `Settings.externallyObservedKeys`, and concurrent `FileDiagnostics` writers still lose lines. Those are separate issues.
- **`LSMultipleInstancesProhibited` remains open**, gated on manual test 1. If the second-account launch succeeds with the key present, ship it; if it is refused, close as WONTFIX and record the result here.

**Evidence.** Login item registered to `/Applications/DockKeeper.app` — **CONFIRMED** (`sfltool dumpbtm`). LaunchServices dedupes on bundle inode identity — **CONFIRMED** twice (launchd job label `application.com.dockkeeper.app.748253205.748253215` matches the two inodes exactly; control-bundle experiment: inode changed → LAUNCH, inode unchanged → REOPEN). `build-app.sh` `rm -rf`s and rebuilds, so every build changes the inode — **CONFIRMED** (script source). `application(_:open:)` fires *before* `applicationDidFinishLaunching` — **CONFIRMED** by measurement (`APP.INIT → STATEOBJECT → WILL_FINISH → OPEN_URL → DID_FINISH`, OPEN_URL at WILL_FINISH+27 ms); two earlier designs assumed the opposite. Apple Event dispatch is gated on `NSApplication.run()` — **CONFIRMED** by experiment (`kAEGetURL` handler + 2.1 s run-loop spin before `NSApplicationMain` caught nothing, twice). `kLSMultipleSessionsNotSupportedErr` semantics — **CONFIRMED** (Apple's archived *Launch Services Keys* reference); that a second fast-user-switched session is actually refused on macOS 14+ is **UNKNOWN pending manual test 1**. `NSRunningApplication.current` is empty (`pid == -1`, `launchDate == nil`) at `App.init()` for a directly-`exec`ed bundle binary — **CONFIRMED** by measurement; that such a process is nonetheless fully visible to its peers, with `launchDate == nil` in *their* view too and for its whole lifetime — **CONFIRMED** by measurement against probe bundles, and it is the reason the kernel start time is substituted. `sysctl` `KERN_PROC_PID` returns a start time for an unrelated process of the same user, unprivileged, agreeing with LaunchServices to ~11 ms — **CONFIRMED** by measurement. The total order and its "exactly one survivor" property — **CONFIRMED** by unit test over every start-time shape, and the sweep is non-vacuous (**CONFIRMED** by mutation: substituting the rejected cyclic predicate fails it, including a zero-survivor case). Which vector produced the owner's two icons — **UNKNOWN** (log retention gap; DockLock Lite alternative unrefuted). The assembled guard against a real double launch — **UNKNOWN**, the manual matrix has not been run.

**Amendment 2026-08-18 — session scoping is no longer inferred; the dependency was removed.**

The consequence struck through above asked an unanswerable question. It made the shipped guard's correctness depend on whether the LaunchServices-backed peer query is session-scoped, and planned to settle that by running manual test 1 once, on one machine. Two things say that was the wrong instrument.

**Apple does not define the behaviour.** The current SDK headers document no scoping for `NSWorkspace.runningApplications` or `runningApplicationsWithBundleIdentifier:` at all. Apple DTS states that macOS supports multiple GUI login sessions "via both Fast User Switching and remote access" and that it was **"undefined which one you'd get"** ([Apple Developer Forums thread 108849](https://developer.apple.com/forums/thread/108849)). Read fairly, that remark addresses a *daemon* calling AppKit, and an app inside a GUI session has a well-defined current session — but "probably fine, and Apple declines to say so" is not a foundation for a guard whose failure mode is a silent zero-instance launch. A single passing manual run would not have converted undefined into defined; it would have converted it into *observed once*.

**The dependency was avoidable at no cost.** `SingleInstance` already calls `sysctl(KERN_PROC_PID)` for every peer to obtain `launchDate`, and the `kinfo_proc` it gets back already carries `kp_eproc.e_ucred.cr_uid` (measured: self reports 501 on the dev machine, launchd reports 0). Carrying that uid onto `InstancePeer` and requiring a peer to share `getuid()` makes the guard session-scoped **by construction**, for zero extra syscalls and no new API.

**Decision.** `InstancePeer` gains `uid`; `InstanceGuard.decide` gains `selfUID` and yields only to a peer that satisfies `sameSession(as:)`. An unknown uid answers `false` — do not yield — chosen from this ADR's own cost asymmetry: two instances are visible and recoverable, a silent zero-instance launch is neither. That case is nearly unreachable, though not for the reason first recorded here: `sysctl(KERN_PROC_PID)` succeeds unprivileged for any **live** pid regardless of owner (measured — 868/868 live processes, 335 foreign-uid, zero failures; the app is unsandboxed, closing the other route), so an unknown uid means the peer is already **dead** — it died between the `!isTerminated` check and the lookup. Declining to yield to a corpse is actively correct rather than merely tolerable. The original argument — that uid and start time share one `sysctl`, so a dateless peer would rank last anyway — was wrong twice: `SingleInstance` falls back to the LaunchServices date, so the peer is still *dated*; and the rank never runs, because `sameSession(as:)` has already excluded it.

**Consequences of the amendment.**

- **Manual test 1 is no longer a gate on this decision.** The property it was to establish is now a unit-tested invariant of the pure core (`InstanceGuard session scoping`, 8 cases). The row keeps value as an end-to-end confirmation and still gates the `LSMultipleInstancesProhibited` follow-on, which is a *LaunchServices launch policy* this change does not touch.
- **`--diagnostics` and the guard now differ deliberately**, and the `Other instances:` doc comment is corrected to say so. The report still lists another user's instance, because support wants to know one is running, but marks it `(another user)`. Without the marker the report would invite the opposite error: each pid it prints is documented as the recovery handle, and support would tell a user to `kill -9` a process they can neither see nor signal.
- **Same-user, multi-session remains uncovered.** Some remote-access configurations can give one user two GUI sessions; uid cannot separate those, where the audit session ID could. Recorded rather than engineered around — it is a far narrower case than fast user switching, and both sessions would share one `com.apple.dock` domain anyway, so a single owner is arguably correct there.

**Evidence (amendment).** The uid discriminates and comes free from the existing lookup — **CONFIRMED (measured 2026-08-18)** by probe. The filter's behaviour across foreign-senior, own-senior, mixed, unknown-uid, third-user, root-owned and junior peers — **CONFIRMED** by unit test, and **CONFIRMED by mutation**: disabling the filter fails 6 of the new cases, and weakening it from equality to mere presence fails 5, so neither degradation can pass silently. That a real second logged-in user behaves as the model says remains **INFERRED** until §3b row 1 runs.

**Date / Status.** 2026-08-17 · **Accepted**; **amended 2026-08-18** (session scoping) — implemented in the same change (`InstanceGuard` pure core + unit tests, `SingleInstance` adapter, `DockKeeperApp.init()` wiring, `Diagnostics` shared flag set + `Other instances:`, `run-app.sh` quit-then-build-then-open). End-to-end verification of the remaining rows is **outstanding**: the [test-strategy](test-strategy.md) manual matrix for DK-FR-012 should still be run, though item 1 no longer gates this decision.

---

## ADR-013: Borrowed system state is persisted before the borrowing write and reconciled at launch; termination hooks are an optimization, not the mechanism

**Context.** DK-FR-011 **borrows** a global system preference: `ScreenShareHider` turns macOS Dock auto-hide **on** for the duration of a screen capture and turns it back **off** when the capture ends. ADR-011 held that a single in-memory `weHidIt` flag was sufficient because the invariant *"we only ever hide from a prior state of off"* makes the restore **value** always "off". That much is still true. What the argument silently carried with it is the **fact that we hid at all** — provenance — which is a different quantity, and which is not derivable from anything observable after the process is gone.

`weHidIt` is in-memory only, and until now nothing restored on the way out (GitHub issue [#29](https://github.com/blamechris/DockKeeper/issues/29)). Kill the process — SIGKILL, Force Quit, a crash, `Scripts/run-app.sh`'s SIGTERM→SIGKILL escalation, or the logout kill — and Dock auto-hide is left **on** with nothing recording that DockKeeper put it there. The next launch reads `weHidIt == false` with auto-hide on, and `decide` returns `.none` from then on: `.none` at capture-stop via `return weHidIt ? .restore : .none`, and `.none` at the next capture-*start* via the "the user runs auto-hide — never touch it" branch. Both are correct readings of ADR-011's rules given the information available; the information is what is missing. **Cite the trace precisely** — the capture-stop `.none` comes from the `weHidIt` ternary, **not** from the never-touch branch, and a fix written against the never-touch branch patches the wrong line.

The user is not literally without recourse: turning auto-hide off in System Settings makes the next read `false` and the feature works again. The accurate claim (rule 5) is that there is **no in-app recovery**, and nothing tells the user that DockKeeper is the cause.

The general shape is why this earns an ADR rather than a bug fix. `CoreDockSetAutoHideEnabled` writes through to the `com.apple.dock` domain (CONFIRMED — R-011, [coredock-defaults-persistence spike](spikes/coredock-defaults-persistence.md)), so this feature's side effect is *inherently* a persistent mutation of a global preference owned by another process. **Every future DockKeeper feature that borrows a system preference inherits the same non-atomic, two-store commit problem**, and the rule below is written for that class, not for auto-hide alone.

**Options.**

1. **Do nothing** — document it. Rejected: the state is unrecoverable through the app's own UI, and the dominant trigger (the logout kill) needs no user mistake at all.
2. **Restore blindly at launch whenever auto-hide is on.** Rejected: it would turn off the auto-hide of every user who legitimately runs it — precisely the thing ADR-011's central invariant exists to prevent.
3. **Store the prior auto-hide value instead of a flag.** Rejected as a non-answer: the ADR-011 invariant makes the prior value *always* "off". The missing information is provenance, not value.
4. **Durable record written before the borrowing write, a bounded attribution window, a capture-aware "adopt", and an unconditional manual floor — chosen.**
5. **Fold the repair into `decide`.** Rejected. `decide` answers a steady-state question every 3 s from three live booleans, and its exhaustive 8-row table is the documented contract of ADR-011 and DK-FR-011 Testability. The repair is a once-per-launch question about *provenance across a process boundary*, over inputs `decide` has no business seeing. Two total pure functions with a stated hand-off — `repair` establishes the initial `(weHidIt, record)` pair, `decide` then runs the steady state unchanged — and the untouched, still-green 8-row table is the proof the ADR-011 contract survived.
6. **Heartbeat (periodic record refresh), or an owner pid with a liveness check.** Rejected. A defaults write every 3 s spends the DK-NFR-001 quietness budget to tighten a bound the staleness rule does not need precisely; and pids recycle (the same reason ADR-012 ranks by start time before pid), so a liveness check that wrongly answered *"the owner is still alive"* would block the repair forever — reinstating exactly the unrecoverable state this record exists to remove.
7. **A separate `fsync`'d file in Application Support.** Rejected: it buys only the sub-millisecond `cfprefsd` hand-off window — whose failure mode is today's behavior — at the cost of a new directory, new failure modes, and leaving the shared CLI-visible store.
8. **`NSWorkspace.willPowerOffNotification`.** Rejected: it loses the same loginwindow race as `applicationWillTerminate`, and adds a second cleanup path that must stay in sync with the first.
9. **A watchdog helper process.** Rejected outright — a second process to clean up after the first is against principle 20 (reliability and predictability before power features) and against §13's no-helper-tools posture.
10. **The manual command alone.** Rejected as the *only* mechanism: it requires the user to know DockKeeper did it. Kept as the floor beneath the automatic path (see Decision), because it is the one recovery that needs no record.

**Decision.** Option 4, in four pieces, in descending order of load-bearing-ness.

- **A durable record is the mechanism.** `Settings.screenShareHideRecord` — one key, one JSON blob (the `preferredDisplayFingerprint` pattern: a single `set` is atomic, so it can never be read half-written, and an undecodable value degrades to `nil`, which is "no record", the safe answer in every branch). It carries a `hiddenAt` timestamp and nothing else — in particular **no owner pid**, per option 6. Deliberately **not** in `registrationDomain()` (absence is a real state and a registered default cannot be removed), deliberately **not** in `Settings.externallyObservedKeys` (observing it would turn every hide and every restore into a `.settingsChanged` reconcile and falsify ADR-011's verified "Coordinator interaction" claim), and **no `settingsVersion` bump** (that hook is for migrations that reinterpret *existing* keys; an optional absent-by-default key is compatible in both directions).

- **Ordering, because the two stores cannot be made atomic.** The record and the Dock live in two stores owned by two daemons. The invariant: *the record is set **no later than** the auto-hide-on write, and cleared **no earlier than** the auto-hide-off write.* The record is therefore always a **superset** of "this auto-hide may be ours", and the false positives are free — see clause 2 below.
  - **Hide → write-ahead.** Record first, then `writeAutoHide(true)`. Killed between the two: a record with auto-hide still off, which the next launch discards at no cost. The opposite order leaves auto-hide **on with no record** — the unrecoverable state.
  - **Restore → write-behind.** `writeAutoHide(false)` first; clear the record only if it succeeded. Killed between: the record outlives a Dock that is already correct, and is discarded free. A failed write keeps the record, so the claim outlives the failure instead of being dropped.
  - **Failed hide write** (symbol gone) clears the record again: never claim a hide we failed to make.
  - Cost: **one defaults write per hide and one per restore** — per *capture session*, a human-scale event, not per 3 s tick.

- **Launch repair, as a pure total function.** `ScreenShareHider.repair(record:currentAutoHide:capturing:featureActive:now:window:) -> {none, discard, adopt, restore}`, applied once per process by `AppState.init` **before** any enable/feature gating — a Dock left auto-hidden must be repaired even when the user has since turned the feature, or DockKeeper, off, which is exactly what a frustrated user does. The rule:

  > A repair fires only when **(1)** a record is present, **and (2)** `CoreDockGetAutoHideEnabled()` resolves and reads **true** right now, **and (3)** `0 ≤ now − hiddenAt ≤ 7 days`.
  > When they hold **and** a capture is running with the poll about to start → **`.adopt`** (take ownership; the normal capture-stop restore puts it back). When they hold otherwise → **`.restore`** (auto-hide off, record cleared, one menu note shown). (1) fails → `.none`. (2) reads `nil` → `.none`, record **kept**. (2) reads `false`, or (3) fails → `.discard`: record cleared, Dock never written.

  **Safety property, asserted directly by test:** `repair` never returns `.restore` or `.adopt` unless `currentAutoHide == true`. It therefore cannot turn off an auto-hide it did not observe as on, and never writes the Dock on the strength of the record alone.

- **A manual floor that needs no record.** "Turn Off Dock Auto-Hide" in the menu (shown only while the Dock is actually auto-hiding and the feature is on) and the same "Turn Off Dock Auto-Hide" permanently in Preferences ▸ Advanced — one wording, because "restore auto-hide" reads cold as restoring it *to on*. Unconditional by design: it is the only recovery available to a user already poisoned by a build that predates the record, or whose record was lost to a panic, a power loss, a wiped preferences domain, or a downgrade. It is user-initiated and plainly labelled, so it may bypass the attribution rules that guard the *automatic* path — and it is what makes a **finite** attribution window affordable at all.

- **Termination hooks are demoted to a latency optimization.** `AppState.prepareForTermination()`, `applicationWillTerminate`, and the `TerminationSignals` `SIGTERM`/`SIGINT` sources stay, and they make the common quit instant. They are **not** the mechanism: the design is required to be *correct with zero termination handling* and merely *faster* with it.

**Why the clauses are what they are.**

*Clause 2 kills a whole class for free.* If auto-hide already reads off, nothing of ours remains: discard with **zero** Dock writes. That alone removes every "the record outlived a Dock that is already correct" crash window.

*Clause 3's lower bound* (`age ≥ 0`) rejects a record stamped in the future — a clock moved back, or a restored backup. Never act on a nonsense stamp.

*Clause 3's upper bound is 7 days, and the principle is **acquiescence**:* a setting the user has lived with for a long time is the user's setting, whoever wrote it. The window is sized against the enumerated relaunch paths — the dev loop (seconds), a manual relaunch (minutes), and the dominant one, **the login item at the next login (hours to days; a long weekend or a week away is the realistic tail)** — so that it actually fixes the reported bug, while still expiring, so that a record which outlived an uninstall, a Time Machine restore, or a machine migration never fires an automatic Dock write. (`~/Library/Preferences/com.dockkeeper.app.plist` outlives deleting an unsandboxed `.app`.) A window measured in minutes would leave the headline bug unfixed for exactly the user who hits it; an unbounded window is the uninstall/restore hazard. It is a constant on `ScreenShareHider`, injectable into the pure function for tests — **not** a `Settings` key, same reasoning as `defaultCheckInterval` (rule 20: no knob the user must understand).

*`.adopt` is not a nicety.* Without it, a launch during a live capture returns `.restore`: auto-hide goes off, and the very next tick (`capturing: true, weHidIt: false, currentAutoHide: false`) returns `.hide` and turns it back on. Net effect: **the Dock appears for up to 3 seconds in the middle of a screen share** — precisely the defect DK-FR-011 exists to prevent. `featureActive` gates `.adopt` because adopting a hide that nothing will later restore leaves the Dock hidden with the record renewed — the bug re-armed.

*The cost asymmetry is why the default inside the window is to restore rather than to do nothing.* A **false restore** is visible within seconds, announced in the menu, reversible in one checkbox, fires at most once per crash, and self-clears. A **false non-restore** is the status quo: an unexplained auto-hiding Dock, no in-app recovery, and a feature that silently never fires again.

**Consequences.**

- **`applicationWillTerminate` is not a guarantee for this app class, and the design does not rely on it.** For background processes, loginwindow *sends* the Quit Apple Event but **does not wait for a reply** before proceeding to kill (Apple, *System Startup Programming Topics*, "Terminating Processes"). DockKeeper is `LSUIElement` + `.accessory` — exactly that class — and logout/restart/shutdown is the highest-frequency real exit path. The hook is a latency optimization; the record is the mechanism.
- **`NSSupportsSuddenTermination=false` does not buy the wait.** That key governs the sudden-termination refcount (`NSProcessInfo.disableSuddenTermination`), not loginwindow's willingness to wait for a background app. Do not repeat the contrary claim.
- **`TerminationSignals` trades one hang for another, knowingly.** `signal(_, SIG_IGN)` plus a `DispatchSourceSignal` is mandatory (without the ignore, the default terminate-now disposition wins the race), and its cost is that a **wedged main run loop no longer dies on `SIGTERM`**. Both senders that matter escalate — `Scripts/run-app.sh` sends `SIGKILL` 2 s later, and a session teardown does the same — so the degraded case is today's behavior, not a new hang. `SIGKILL` remains untrappable by design and is covered by the record, not from there.
- **The ambiguity is irreducible and is not papered over.** At launch, "nothing touched it since we died" is **not separable** from "the user turned it off and then deliberately on", "the user saw it on and decided they like it", or "a third party (DockLock Lite, a script) set it" — all present identically as *record present, auto-hide on, not capturing*. No intent signal exists: `com.apple.dock.plist` mtime cannot separate our write from a later user write even in principle (`cfprefsd` flushes lazily and the Dock rewrites that domain constantly), and an "awake clock" from `kern.boottime` is precision theatre around a quantity we are not running to observe. The one honest quantity is `now − hiddenAt`, an **upper bound** on exposure; over-estimating exposure errs toward *not* restoring, which is the safe direction. One consequence is recorded rather than engineered around: the stamp is taken at the hide and never refreshed, so a *single* capture running longer than the window — a permanently-connected Screen Sharing session on a headless Mac — repairs to `.discard` after a kill. Re-stamping would cost a `Settings` read on every 3 s tick against DK-NFR-001 (the same objection that rejected the heartbeat option), and the outcome is the pre-fix status quo plus the manual floor, so the bound is documented instead.
- **Durability is established against process death only.** Kernel panic and power loss are UNKNOWN and untestable without panicking the machine. The residual failure mode is exactly today's behavior — no regression — and the manual floor is its recovery.
- **Two instances are handled by argument, not by design.** `UserDefaults` and `com.apple.dock` are both per-user, so fast user switching shares nothing; DK-FR-012 blocks bundled duplicates and `SingleInstance.yieldIfDuplicate()` runs in `App.init()` before `AppState` exists, so a deflected duplicate never touches the record. The residual (unbundled `swift run`, or `DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES=1`) already shares one in-memory belief today, and both processes read the same global capture state — and the same `enabled` / `hideDockDuringScreenShare` from the same suite, so their `featureActive` cannot disagree — and reach the same conclusion. One genuinely new interleaving exists there and is accepted rather than designed against: instance B's launch repair can read the record after A's write-ahead but read auto-hide before A's Dock write, concluding `.discard` and dropping A's live claim. The window is microseconds inside an explicitly unsupported mode, and its outcome is today's behavior plus the manual floor.
- **The cross-launch repair is announced, never silent — on both acting branches.** It mutates a global system preference the user did not just ask for, so it writes a one-line note through the surface the menu already has (`AppState.screenShareRepairMessage`), superseded by the next real screen-share transition. `.adopt` is announced too, and its announcement is *deferred, not dropped*: adopting takes ownership now and the Dock write lands when the share ends, so `AppState.pendingRepairDisclosure` carries the disclosure to that restore rather than letting it pass silently. The note sits **below** `statusMessage` in the menu's precedence chain: it is sticky (in the S9 case no further screen-share transition ever fires to clear it) and must never occlude a live `Degraded` / `Not converging` message, which is the only health surface an `LSUIElement` app has. A silent mutation is the one thing that would make this fix worse than the bug.
- **`--diagnostics` gains a read-only `Screen-share:` line** (relative age, never a wall-clock stamp — state only, DK-PRIV-001 S2), following ADR-012's `Other instances:` precedent: an `LSUIElement` app gives the user nowhere else to look.
- **The rule generalizes and is binding:** *any system preference DockKeeper borrows is recorded durably **before** the borrowing write and cleared **after** the restoring write, and restoration never depends on a termination hook.*
- **Not fixed here, deliberately.** When the user genuinely runs auto-hide, the Advanced-tab toggle reads on while the feature is by-design inert, with no status surface saying so. That is a real defect and a separate requirement; expanding this change to cover it was rejected as scope.

**Evidence.**

- The `repair` rule table, its totality and one-step convergence, the 48-combination safety property, the write-ahead/write-behind ordering, and the end-to-end repair through injected ports — **CONFIRMED** by unit test. The *ordering* specifically is asserted from inside the injected Dock write (`recordLandsBeforeTheDockWrite`, `recordSurvivesUntilAfterTheDockWrite`), not inferred from an end state: both orderings finish in the same state, so a "Dock first, record second" mutant passes every other test in the file — **CONFIRMED by mutation** (reversing the two lines fails exactly that assertion and nothing else).
- The ADR-011 contract is preserved **iff** `ScreenShareDecideTests`' 8-row `decide` table is untouched and still passing. That it is **untouched** is **CONFIRMED** (verified by diff — the only edit anywhere in `ScreenShareDecideTests`/`ScreenShareLifecycleTests` is injecting a test `Settings` into a hider construction). That it still passes is the **standing proof obligation** this ADR records, re-checked at every `swift test` run.
- AppKit installs no `SIGTERM` handler: a bare `kill -TERM` on an `.accessory` `NSApplication` exits 143 with no delegate callback — **CONFIRMED (measured, macOS 26 / Darwin 25.6)**, probe and raw output in [spikes/termination-and-defaults-durability.md](spikes/termination-and-defaults-durability.md).
- `SIG_IGN` + `DispatchSourceSignal(queue: .main)` converts that into the ordinary quit: `SIGNAL 15` → `WILL_TERMINATE` → exit 0, which is also the measurement that `NSApp.terminate(nil)` reaches `applicationWillTerminate` (the ⌘Q path) — **CONFIRMED (measured)**, [same spike](spikes/termination-and-defaults-durability.md).
- `UserDefaults.set` survives an immediate in-process `SIGKILL` — **CONFIRMED (measured, 25/25, without `synchronize()`, named suite + JSON blob, read back from a fresh process)**, [same spike](spikes/termination-and-defaults-durability.md); `set` hands the value to `cfprefsd`, a surviving process, over XPC before returning. Scope: *process* death only.
- loginwindow does not wait for a background process's Quit reply — **INFERRED** from Apple, *System Startup Programming Topics*, "Terminating Processes" (archived, dated 2007-02-08). That it still describes macOS 14–26 verbatim is **UNKNOWN**; it is the only Apple statement on the question and is taken as the conservative assumption.
- The claim circulating that `.accessory`/`.prohibited` specifically skips `willTerminate` on shutdown, attributed to Apple Developer Forums threads 724067 and 131471 — **UNVERIFIED**: both threads were fetched and neither contains it. **Do not cite it.**
- Durability across kernel panic or power loss — **UNKNOWN**; residual, no regression versus today. An attempt to bound it by watching for the suite's `.plist` to appear on disk was **inconclusive** (the probe cannot separate a genuine flush from `cfprefsd` re-materialising the file from cache), so no flush-latency figure is claimed — see the spike.
- A real `SIGKILL` during a real capture followed by a real relaunch restoring the real Dock, the `.adopt` no-flash property on a real screen share, the hook firing in the signed bundle at menu-Quit and at logout, and the menu item's visibility and wording for the poisoned population — **INFERRED** until the on-device cells ([test strategy](test-strategy.md) §3c, [hardware matrix](hardware-matrix-results.md)).

**Date / Status.** 2026-08-17 · **Accepted** — implemented alongside the fix for issue #29 (`ScreenShareHideRecord`, `Settings.screenShareHideRecord`, pure `ScreenShareHider.repair` + `repairIfNeeded`, `restoreAutoHideByUserRequest`, write-ahead/write-behind ordering in `evaluate`/`performRestore`, `AppState.repairScreenShareHideIfNeeded` + `screenShareRepairMessage`, menu and Advanced-tab recovery, `--diagnostics` line; `AppState.prepareForTermination`, `applicationWillTerminate`, and `TerminationSignals` as the optimization half). The pure and port-driven halves are **CONFIRMED** by unit test; every on-device claim in Evidence stays **INFERRED** until [test strategy](test-strategy.md) §3c is run. Standing obligation: the DK-FR-011 screen-watcher smoke test on the [release checklist](release-checklist.md) now carries the kill-and-relaunch cells.


---

## ADR-014: Pause is persisted as a durable record, and a restart is an implicit resume

**Context.** Pause (DK-FR-009) suspends corrections. It lived entirely in `RecoveryCoordinator` as `machine.state == .paused` plus a `pausedUntil`, and **nothing DockKeeper could print said so** ([#36](https://github.com/blamechris/DockKeeper/issues/36)). `dockkeeper status` was byte-identical paused and unpaused (measured), and `--diagnostics` — the documented support command — is a *freshly spawned process* that cannot see another instance's in-memory state at all. The only observer was the menu-bar icon, which is visual-only.

That is the same support blind spot ADR-012's `Other instances:` and ADR-013's `Screen-share:` lines exist to close, and the reasoning transfers verbatim: an `LSUIElement` app has no window and no Force Quit row, so the report *is* the view. It is worse here than merely incomplete. `Enabled: yes` is **not** the same state as "correcting", so a user who paused via Shortcuts, Siri, or a URL and forgot sends a report indistinguishable from a working install — while DockKeeper is, correctly and by design, doing nothing.

**Options.**

1. **Report from the running process only**, via "the existing control path". **Rejected — there is no such path.** `dockkeeper://` URLs are one-way, fire-and-forget into `AppState.perform(_:)`; the CLI and the app share state *exclusively* through `UserDefaults`. Nothing in this app can ask a running instance a question. Taking this option means inventing an IPC surface (XPC service, Mach port, or a notification round-trip) on a background app, for one support line — and it still leaves `--diagnostics` blind whenever the app is not running, which is precisely when a support report is most confusing.
2. **Persist a record**, the DK-FR-013 shape. Chosen.
3. **Infer pause from something already persisted.** Rejected as a non-answer: nothing persisted distinguishes it. `enabled` is a different state and must stay so — conflating them is the misleading report this ADR removes.
4. **A diagnostics-file line only** (`FileDiagnostics` already notes `pause`). Rejected: opt-in, off by default, and a *log of transitions* rather than *current state* — it cannot answer "is it paused right now" without replaying the file.

**Decision.** `Settings.pauseRecord` — a `PauseRecord` (`pausedAt`, optional `pausedUntil`), one key, one JSON blob, following `screenShareHideRecord`'s contract exactly (ADR-013): a single `set` is atomic so it cannot be read half-written; an undecodable value degrades to `nil`, which is "not paused" and the safe answer everywhere; **not** in `registrationDomain()` (absence is a real state, and a registered default cannot be removed); **no `settingsVersion` bump** (an optional, absent-by-default key reads compatibly both directions).

Two decisions distinguish it from ADR-013, and both are deliberate:

- **A restart is an implicit resume.** ADR-013 persists *and reconciles at launch* because Dock auto-hide is **borrowed** — it belongs to the user and DockKeeper owes it back. Pause is DockKeeper's own runtime state; nothing is owed, so the record is **discarded at launch**, not honoured (`AppState.resumeStalePauseIfNeeded`). This also puts the failure direction on the safe side: an untimed `dockkeeper://pause` has *no timer at all*, so honouring it across a crash would leave DockKeeper silently not enforcing forever, recoverable only by a resume the user has no reason to think they need. The cost is accepted and small: a user who paused for eight hours and then rebooted gets enforcement back early, which is the benign surprise of the two.
- **The key is not in `externallyObservedKeys`.** Churn is not the argument here (unlike the hide record, this is written rarely). `resume()` is: it clears the record **and** already runs a full reconcile by design, so observing the key would fire a second, redundant reconcile off the same resume. The pause side would be harmless either way — `RecoveryMachine.shouldProcess` refuses every event while `.paused`. Letting an external writer *drive* pause by writing this key is a separate feature and would have to solve that double reconcile first.

**Consequences.**

- **The write hangs off `notifyState()`, the single funnel every state change already passes through** — not off the three pause-adjacent call sites. The record therefore cannot disagree with the state it describes, and a fourth path out of `.paused` added later inherits the write for free instead of silently leaking a stale "paused" into every support report. A change guard makes it write only on a real change: `notifyState()` also runs on every reconcile, and re-writing an unchanged key would spend the DK-NFR-001 quietness budget to say nothing new.
- **Persistence is injected** (`persistPause`), like `applyEdge`/`applyPin`, defaulting to a no-op — so a coordinator with no defaults domain keeps pause purely in memory, which is the pre-ADR-014 behaviour.
- **The explicit launch clear is load-bearing, not belt-and-braces.** A fresh coordinator starts unpaused with an empty shadow, so its own sync sees "not paused, nothing persisted", finds no change, and writes nothing — a stale record would otherwise survive forever. Nothing else clears it.
- **`--diagnostics` reports a relative age, never a wall clock** (DK-PRIV-001 S2, matching `Screen-share:`). The age is also what exposes the single stale case this design admits: because a restart resumes, a record older than the running instance means DockKeeper *died* while paused and the report is from a cold process — cross-check `Other instances:`. A `--diagnostics` run never destroys that evidence: `Diagnostics.runIfRequested()` prints and `exit()`s inside `App.init()`, before the `@StateObject` autoclosure that builds `AppState`.
- **Every interval the report derives from stored data is clamped before conversion** (`DisplayDuration.wholeSeconds`). The precision matters: `Diagnostics` also prints `Int(ScreenShareHider.repairWindow)`, which is *not* clamped and does not need to be — it is a compile-time constant (`7 * 24 * 3600`), not a decoded value, and cannot be anything else. `Int(_: Double)` traps, and the `Date`s are decoded from a defaults domain any process running as this user can write — so a decodable-but-absurd stamp crashed the one command support asks users to run. The guard covers the pre-existing `Screen-share:` age too, which had the same defect since ADR-013. A support command that crashes on a malformed record is strictly worse than one that prints "unreadable".
- **`status` prints `Paused:` whether or not a pause is in force.** A line that appears only when paused does not make a *pasted* report distinguishable, which was the defect.
- **The Siri/Shortcuts voice line leads with the pause and drops the mechanism tail.** Asked out loud whether DockKeeper is on, "enabled" alone is the wrong answer while it is deliberately correcting nothing. **This claim was false when first written**, and the reason is worth keeping: `StatusSummary.init` gained `pauseRecord` *with a default*, so a third hand-rolled construction in `AppState.statusSummary()` kept compiling while silently passing `nil`. `DockKeeperStatusIntent` prefers that copy over `StatusSummary.live()` whenever the app is running — which is exactly when a pause can be live — so the intent went on answering "enabled" on every real pause. Fixed by deleting the copy (it now calls `live(settings:)`, as the CLI does) **and by removing the default**, so the compiler rejects any future construction that omits the field rather than answering wrongly at runtime. The same defaulted-parameter shortcut that preserved source compatibility is what hid the bug.
- **The CLI stopped hand-rolling its own `StatusSummary`.** `runStatus()` re-spelled the construction that `StatusSummary.live` already performs, under a comment warning that the two must not drift — exactly the drift that would have shipped a CLI still unable to see a pause. It now calls the shared builder.
- **`status` reports configured state, not liveness** — it already prints `Enabled: yes` with no app running. Pause inherits that, and the diagnostics age is where staleness surfaces.

**Evidence.**

- `status` byte-identical paused vs unpaused before this change — **CONFIRMED (measured)**, [#36](https://github.com/blamechris/DockKeeper/issues/36).
- No query IPC exists between the CLI and the app — **CONFIRMED by inspection**: `dockkeeper://` routes one-way through `AppState.perform(_:)`, and `dockkeeper-cli` reaches the app only through the shared `UserDefaults` suite.
- The record tracks `machine.state` across pause, untimed pause, timed pause, auto-resume, manual resume, supersede, and disable; writes exactly once for an unchanged record; and writes **nothing at all** across repeated reconciles while unpaused — **CONFIRMED** by unit test (`RecoveryCoordinator pause record`, [RecoveryTests.swift](../Tests/DockKeeperTests/RecoveryTests.swift)).
- Round-trip, timed and untimed, corrupt-value degradation to `nil`, not-registered, and not-externally-observed — **CONFIRMED** by unit test (`Settings.pauseRecord`).
- A **cold process reads a pause it does not host** and renders it: a record written to the real suite by a third party is reported by `dockkeeper-cli status` as `Paused:     yes (until 7:35 PM)`, and `Paused:     no` once removed — **CONFIRMED (measured 2026-08-18)**. This is the cross-process seam the whole ADR exists for, and it is the one thing no unit test can establish.
- The `Int(_: Double)` trap and its guard — **CONFIRMED (measured 2026-08-18)**. `{"pausedAt": 1e300}` is valid JSON, decodes to a **finite** `Date`, and crashed `Int(_:)` with *"result would be less than Int.min"* (SIGTRAP, exit 133). The value being finite is the sharp edge: an `isFinite` guard alone does not fix it, and `Double(Int.max)` is not a usable clamp bound because it rounds *above* `Int.max` — the compiler constant-folds `Int(Double(Int.max))` into an overflow error. After the guard, the same input yields `Paused:          yes (timestamp unreadable — record may be corrupt)` and exit 0, measured through the real binary. The `status` formatter path was checked and does **not** trap (it renders nonsense rather than crashing), so the exposure was confined to `--diagnostics`.
- That a **real** pause taken by the running app produces that line end-to-end, and that a real relaunch discards a real record, remain **INFERRED** until [test strategy](test-strategy.md) §3b row 4 is run on-device.

**Date / Status.** 2026-08-18 · **Accepted** — implemented as `PauseRecord`, `Settings.pauseRecord`, `RecoveryCoordinator.syncPauseRecord` hung off `notifyState()` with an injected `persistPause`, `AppState.resumeStalePauseIfNeeded`, `StatusSummary.pauseRecord` + `Paused:` line + voice line, the `--diagnostics` `Paused:` line, and `DisplayDuration.wholeSeconds` guarding both of that report's age conversions. Answers the design question [#36](https://github.com/blamechris/DockKeeper/issues/36) recorded rather than resolving it by reflex, and unblocks §3b row 4.

---

## ADR-015: Hold a bottom Dock by blocking the summon, never by relocating it

**Context.** With "Displays have separate Spaces" ON, a **bottom** Dock is per-display and pointer-summoned — it goes to whichever display you hold the pointer at the bottom of. ADR-009 shipped left/right pinning (those home to the main display) and declined bottom honestly. Bottom is gap **G1**, DockLock's headline feature, and the last gap to every shipping DockLock capability.

The spike spent a month asking "how do we put the Dock back" and answered it definitively: **we cannot.** Every relocation family is falsified on hardware — pointer warp (`CGWarpMouseCursorPosition`), synthesized events (`CGEventPost`) under a *real* Accessibility grant, AX geometry (read-only), and `SLSSetDockRect{WithOrientation,WithReason}`, which accept a rect on another display without the Dock following. Placement is the Dock process's own decision and nothing in userspace reproduces what a real pointer does.

The owner's challenge is what reframed it: DockLock Lite ships this to real users, so "not viable" could not be right. It was not — because "lock" does not mean *relocate after the fact*, it means **prevent**. Prevention is a different mechanism and it is what Accessibility is actually for.

**Options.**
1. Keep declining bottom (ADR-009 status quo) — leaves G1 open forever on a false premise.
2. Keep hunting for a relocation call — every family is falsified; this is looking for a door that does not exist.
3. **Block the summon with a `CGEventTap`** — hold the pointer a few points clear of the bottom trigger row on every display the Dock should not go to.
4. Clamp unconditionally whenever the feature is on — simplest, and dangerous: on stacked arrangements the bottom edge is the *crossing boundary* between displays, so clamping it traps the cursor.

**Decision.** Option 3, with option 4's hazard as a hard refusal. `lockBottomDockToDisplay` (Bool, default **false**) gates it. `BottomDockGuard.decide` is pure and disqualifies in order — feature off, edge not bottom, separate Spaces off, one display, no preferred display, preferred display absent, Accessibility not granted — and only then evaluates geometry, so a refusal always names the real cause. It emits a `ClampZone` for each **non-preferred** display whose bottom edge is **free**, and the `BottomDockGuardTap` adapter pulls a pointer inside that band back to `maxY − 3`, altering `y` only.

**A blocked bottom edge is both unguardable and not in need of guarding**, which is what makes the safety gate free of cost: clamping a crossing boundary would trap the pointer, *and* a summon cannot fire on a blocked edge anyway (CONFIRMED 2026-07-23 on the stacked portrait rig — not even a real hand could summon there). So the guard skips it on both counts rather than trading safety against coverage.

**Consequences.** The zero-permission default survives: Accessibility is requested only on opt-in, and only for this one job, exactly as ADR-010 established for window restore. The feature fails **open** in every degraded state — no grant, refused tap, revoked grant, system-disabled tap — because the failure that matters here is a trapped cursor, not an unguarded Dock. An event tap is process-owned, so unlike ADR-013's borrowed auto-hide there is **no persistent state and no launch repair**: kill the process by any route and the pointer moves normally.

The real cost, stated plainly in the UI: a guarded display's **bottom hot corners and its own Dock summon become unreachable** while the guard is active. That is the mechanism, not a defect. DockKeeper matches DockLock's envelope here — Accessibility, bottom-only, ≥2 displays, separate Spaces on, and a refusal on incompatible arrangements — for the same reasons, arrived at independently.

Framing is binding: **"stop the Dock leaving this display", never "put the Dock back".** The latter is impossible and every relocation candidate is falsified; a future contributor who reads this as relocation will waste the month the spike already spent.

**Evidence.** Prevention works — **CONFIRMED with a control** (2026-08-27): a tap clamping the bottom edge of `(1728, 0, 3840, 2160)` held the cursor at `y = 2157` when aimed at `y = 2159`, ten clamps applied, while the same aim with the tap disabled reached `y = 2159`. The instrument was validated separately first (20/20 synthetic moves seen), so a zero count is distinguishable from a broken tap — the failure that wasted two earlier runs. Relocation is impossible — **CONFIRMED** across four mechanism families (spike results tables). DockLock's constraint set fits prevention and not summoning — **INFERRED**, strong constraint-fit, not reverse-engineered; their `warn_incompatible_display` fits suppression-on-a-crossing-edge far better than failed summoning, which is how it was read backwards for a month. The pure decision, the geometry gate and the clamp are **CONFIRMED by unit test**, non-vacuous by mutation (inverted coordinate orientation fails 13; dropped safety gate fails 7; clamping `x` fails 7). **That a real hand cannot complete the summon while the tap is live is INFERRED and not yet observed** — every hand-driven migration logged was preceded by the pointer reaching the bottom row, so removing that row should remove the trigger, but the human-in-the-loop observation needs a two-display rig and has not been run.

**Date / Status.** 2026-08-29 · **Accepted** — implemented behind an opt-in flag (`BottomDockGuard`, `BottomDockGuardTap`, Preferences toggle, `--diagnostics` line, 30 unit tests). Narrows ADR-009's bottom-Dock decline to *"declined unless the guard is on and the arrangement permits it"*. On-device confirmation is an open obligation, not a shipped claim.
