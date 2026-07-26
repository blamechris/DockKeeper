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

**Date / Status.** 2026-07-23 · **Accepted (owner-ratified 2026-07-23)** — implemented (`ScreenCapture`, `ScreenShareHider` with pure `decide`, `CoreDock` auto-hide + `getRect` wrappers, `Settings.hideDockDuringScreenShare`, AppState poll wiring, Advanced-tab UI, exhaustive `decide` unit tests). The true-case detection stays **UNKNOWN** until hardware validation (M6/M12). Standing obligation: per-macOS-release screen-watcher smoke test (R-004).
