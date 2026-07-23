# DockKeeper — Behavior Specification

| | |
|---|---|
| **Status** | Draft for review |
| **Date** | 2026-07-22 |
| **Owner** | blamechris |
| **Scope** | v1.0 externally observable behavior |
| **Inputs** | [Technical design](technical-design.md) (Appendix B seed IDs), [Preferred-display spike](../Documentation/spikes/preferred-display-spike.md) (owner Decisions 1–3, 2026-07-22), kickoff package Phase-3 template |

Evidence labels: **CONFIRMED** (verified on-device / Apple docs / reproducible experiment) · **INFERRED** (reasoned from confirmed facts) · **PROPOSED** (a choice this document makes) · **UNKNOWN** (needs investigation).

This document describes externally observable behavior only; mechanisms live in the [technical design](technical-design.md). Risk IDs (R-xxx) refer to the [risk register](risk-register.md); ADRs to the [decision log](decision-log.md).

## Conventions

- **IDs are stable.** `DK-FR-xxx` functional, `DK-NFR-xxx` non-functional, `DK-PRIV-xxx` privacy. (`DK-UX-xxx` is reserved; no UX-only requirements exist yet.) Never renumber; retire with a strikethrough and a note.
- **Priority**: **P0** — v1.0 cannot ship without it. **P1** — planned for v1.0; may individually degrade or slip with owner sign-off. **P2** — post-v1.
- Scenarios use Given/When/Then. Scenario IDs (`-S1` …) are referenced from [test-strategy.md](test-strategy.md).

### Requirements index

| ID | Title | Priority | Target |
|---|---|---|---|
| [DK-FR-001](#dk-fr-001-edge-lock-and-restore) | Edge lock and restore | P0 | v1.0 |
| [DK-FR-002](#dk-fr-002-preferred-display-pinning-best-effort) | Preferred-display pinning (best-effort) | P1 | v1.0 |
| [DK-FR-003](#dk-fr-003-recovery-after-system-events) | Recovery after system events | P0 | v1.0 |
| [DK-FR-004](#dk-fr-004-enable--disable) | Enable / disable | P0 | v1.0 |
| [DK-FR-005](#dk-fr-005-launch-at-login) | Launch at Login | P1 | v1.0 |
| [DK-FR-006](#dk-fr-006-menu-bar-controls-and-preferences) | Menu-bar controls and Preferences | P0 | v1.0 |
| [DK-FR-007](#dk-fr-007-command-line-interface) | Command-line interface | P1 | v1.0 |
| [DK-NFR-001](#dk-nfr-001-quietness-and-resource-budget) | Quietness and resource budget | P0 | v1.0 |
| [DK-NFR-002](#dk-nfr-002-zero-network-communication) | Zero network communication | P0 | v1.0 |
| [DK-PRIV-001](#dk-priv-001-no-telemetry-accounts-or-data-collection) | No telemetry, accounts, or data collection | P0 | v1.0 |

---

## DK-FR-001: Edge lock and restore

**Description.** DockKeeper keeps the Dock on the user-chosen edge (bottom, left, or right) and restores it whenever macOS or anything else moves it. This is the headline, always-reliable feature (spike TL;DR, owner Decision 3).

**Rationale.** macOS relocates the Dock after sleep/wake, display plug/unplug, and resolution/arrangement changes, and offers no built-in "keep the Dock here." CONFIRMED (problem statement, TDD §1).

**Preconditions.** DockKeeper enabled (`DK-FR-004`); a lock edge is configured (default: bottom). Primary path additionally requires the private `CoreDock` symbols to resolve at runtime (CONFIRMED working on-device); otherwise the fallback path applies (S3).

**Trigger.** Drift detected by any monitored event or the polling safety net (`DK-FR-003`).

**Expected result.**

```text
S1 — Restore on drift (primary path)
Given DockKeeper is enabled with lock edge = left
And the CoreDock symbols resolve
When the observed Dock orientation is not left
Then DockKeeper sets the Dock orientation to left via the live CoreDock call
And the Dock is not restarted and does not flicker          [CONFIRMED on-device]
And the correction is logged locally when verbose logging is on

S2 — Idempotence (no oscillation)
Given the Dock is already on the locked edge
When a reconcile pass runs (event or poll)
Then no set call is issued and nothing visible happens

S3 — Fallback when CoreDock is unavailable
Given the CoreDock symbols fail to resolve
When a restore is needed
Then DockKeeper writes com.apple.dock orientation and restarts the Dock
And the app enters the Degraded state, surfaced in the menu and in CLI status
And the Dock restart is visible (accepted cost of the fallback)

S4 — Top edge is never offered
Given any configuration surface (menu, Preferences, CLI)
Then the selectable edges are exactly bottom, left, right   [CONFIRMED — existing test]
```

**Failure behavior.** If both the live read and the defaults read fail, the orientation is treated as unknown drift and the desired edge is applied (applying is idempotent and safe — TDD §5.3, PROPOSED). Retry ladder applies (`DK-FR-003`); if exhausted, state → `Error` with the last error surfaced.

**User-visible behavior.** Primary path: instant, flicker-free edge change. Fallback: visible Dock restart plus a "running degraded" menu note.

**Testability.** Decision logic unit-testable once the `DockAdapter` seam exists (v0.1 gap — TDD §4.3); model mapping already covered by `DockOrientationTests` (CONFIRMED). See [test-strategy.md](test-strategy.md).

**Priority / target.** P0 / v1.0. **Related risks:** R-004 (CoreDock fragility), R-005 (oscillation), R-011 (Dock-restart persistence UNKNOWN).

---

## DK-FR-002: Preferred-display pinning (best-effort)

**Description.** The user may choose a preferred display; DockKeeper makes that display the macOS *main* display via public `CGDisplayConfiguration` APIs, which is where the Dock lives. Explicitly **best-effort** (owner Decisions 1–3): the menu bar moves with the Dock (accepted, documented), and pinning is declined with an explanation when it cannot work honestly.

**Rationale.** There is no API — public or private within accepted risk — to place the Dock on a display directly; relocating the main display is the only public route. CONFIRMED (spike).

**Preconditions.** Enabled; a preferred display is stored (v0.1: UUID; v1: fingerprint per ADR-004); at least two displays connected; "Displays have separate Spaces" is OFF.

**Trigger.** Reconcile pass (event, poll, enable, or the user picking a display).

**Expected result.**

```text
S1 — Pin (happy path)
Given separate Spaces is OFF and the preferred display is connected and not main
When a reconcile pass runs
Then DockKeeper reconfigures display origins so the preferred display becomes main
And the menu bar moves to that display (documented consequence)
And the outcome is surfaced in the menu
[Mechanism CONFIRMED available; end-to-end behavior on real multi-monitor
 hardware INFERRED — R-002, the top open risk]

S2 — Separate Spaces ON (macOS default)
Given "Displays have separate Spaces" is ON
When a pin would otherwise apply
Then DockKeeper declines (unsupportedSeparateSpaces), explains why in the UI,
And edge locking continues to work                          [Decision 2A]

S3 — Preferred display absent
Given the preferred display is not connected
Then no fallback display is ever pinned                     [TDD §7.4]
And state = PreferredDisplayMissing with a menu note
And the edge lock remains enforced on whatever display macOS uses

S4 — Preferred display returns
Given state is PreferredDisplayMissing
When the display reconnects (reconfiguration event)
Then the pin is re-applied per S1

S5 — Already main / single display
Given the preferred display is already main, or only one display is connected
Then the pass is a no-op with a typed outcome (alreadyOnTarget / singleDisplay)
```

**Failure behavior.** A failed `CGDisplayConfiguration` transaction is cancelled cleanly, reported as a typed `.failed` outcome with user-facing copy (CONFIRMED — implemented); the cooldown budget (`DK-FR-003`-S4) prevents retry storms. Ambiguous identity (two indistinguishable candidates) must never guess — the user is asked to re-pick (PROPOSED, TDD §7.2).

**User-visible behavior.** A pin visibly re-arranges displays (menu bar moves) — inherent, not a defect; honest copy explains "on macOS, the Dock lives on your main display."

**Testability.** `MainDisplayPinner.decide` is pure; all six decision branches covered today (CONFIRMED — `DisplayPinnerTests`). Needed: echo suppression, re-pin-on-return, fingerprint matching (see test strategy).

**Priority / target.** P1 / v1.0 (best-effort by decision). **Related risks:** R-002, R-003 (display identity), R-005.

---

## DK-FR-003: Recovery after system events

**Description.** DockKeeper detects and corrects Dock drift after sleep/wake, display connect/disconnect, resolution and arrangement changes, Space changes, and session reactivation — event-driven, with a low-frequency polling safety net (ADR-005).

**Rationale.** These are exactly the moments macOS moves the Dock; recovery is the product. Event catalog: TDD §8.1.

**Preconditions.** Enabled. (`autoRecover` gates the poll only; events always reconcile — v0.1 semantics, flagged for cleanup in TDD §11.)

**Trigger.** Any event in TDD §8.1, or a poll tick (default 30 s per ADR-005; v0.1 ships 2 s — change pending).

**Expected result.**

```text
S1 — Wake with slow displays
Given the Mac wakes and displays are not yet ready
When the first reconcile attempt finds the topology incomplete
Then the retry ladder re-attempts (0 s, +1.5 s, +4 s)        [PROPOSED §8.4]
And the Dock converges to the locked edge / pin without user action

S2 — Event-burst coalescing
Given a display reconfiguration fires several events within milliseconds
When they arrive inside the debounce window (~400 ms)
Then exactly one reconcile attempt runs                      [PROPOSED §8.3]

S3 — Echo suppression
Given DockKeeper itself just performed a pin (which emits a reconfiguration event)
When that event arrives within the echo window (~2 s)
Then it is swallowed and does not trigger another pass       [PROPOSED §8.3]

S4 — Oscillation guard
Given some external agent keeps moving the Dock back
When more than 6 corrections occur within 60 s
Then DockKeeper stops correcting, enters Error, and tells the user
    (never a silent infinite fight)                          [PROPOSED §8.4]

S5 — Poll safety net
Given an event was missed (gap, unobserved cause)
When the poll tick finds drift
Then the drift is corrected and the poll-caught occurrence is counted locally
    (evidence for tuning the interval — ADR-005)
```

**Failure behavior.** Ladder exhausted → `Error`; recovery resumes on the next event or manual retry. Registration failure of any observer is covered by the poll.

**User-visible behavior.** None when healthy — recovery must be invisible (no oscillation). `Error` state surfaces the last error in the menu.

**Testability.** Pure `decide(state, event, now)` core with synthetic event sequences and a simulated clock (none of S1–S5 is implemented or tested in v0.1 — this is the core M3/M4 work).

**Priority / target.** P0 / v1.0. **Related risks:** R-005, R-006, R-011.

---

## DK-FR-004: Enable / disable

**Description.** The user can disable DockKeeper at any time; disabled means DockKeeper touches nothing and consumes nothing.

**Rationale.** Kickoff principle: the app must be trustworthy and predictable; rule 20 (reliability before power features).

**Preconditions.** None.

**Trigger.** Menu toggle, Preferences, or `dockkeeper unlock` / settings edit via CLI.

**Expected result.**

```text
S1 — Disable is total
Given DockKeeper is enabled and monitoring
When the user disables it
Then all observers and timers are torn down
And no further corrections occur (zero footprint)
And the current Dock position is left exactly as-is

S2 — Enable reconciles
Given DockKeeper is disabled
When the user enables it
Then a full reconcile (edge + pin) runs after the settle delay
And the state machine proceeds Disabled → Starting → Monitoring
```

**Failure behavior.** None specific; enable failures surface as `DK-FR-001`/`DK-FR-002` outcomes.

**User-visible behavior.** Menu toggle state; icon should distinguish enabled/disabled (v0.1 uses one symbol — known debt, TDD A.4).

**Testability.** "Disable tears down observers/timers with no residual corrections" — needed test (Appendix B). Settings persistence covered (CONFIRMED — `SettingsTests`).

**Priority / target.** P0 / v1.0. **Related risks:** — .

---

## DK-FR-005: Launch at Login

**Description.** Optional launch-at-login via `SMAppService.mainApp`, with the system as the source of truth.

**Rationale.** A recovery utility only helps if it is running when the drift happens.

**Preconditions.** Running from a packaged `.app` bundle (CONFIRMED: `SMAppService` reports `.notFound` under `swift run`; documented in-code and in README).

**Trigger.** Toggle in Preferences / menu.

**Expected result.**

```text
S1 — Register / unregister
Given the app runs from a bundle
When the user toggles Launch at Login
Then SMAppService registers/unregisters the login item
And the UI reflects SMAppService.status, never a cached flag

S2 — Approval required
Given macOS reports .requiresApproval
Then the app explains why, and deep-links the user to the
    System Settings ▸ Login Items pane                       [CONFIRMED built]
And changes nothing on the user's behalf

S3 — Not packaged
Given the app runs via swift run
Then the toggle reverts and the UI explains that a packaged .app is required
```

**Failure behavior.** Registration throws → toggle reverts to system truth plus guidance (CONFIRMED built).

**User-visible behavior.** Toggle plus contextual guidance; a System Settings approval dialog may appear (system-owned).

**Testability.** `LoginItemManager.message(for:)` mapping unit-testable; approval flow is manual-matrix only (`SMAppService` untestable in unit scope — Appendix B).

**Priority / target.** P1 / v1.0. **Related risks:** — .

---

## DK-FR-006: Menu-bar controls and Preferences

**Description.** DockKeeper is a menu-bar accessory app (no Dock icon): a dropdown with the enable toggle, edge picker, display picker, status notes, and access to a Preferences window.

**Rationale.** The only always-available control surface; kickoff v1 boundary.

**Preconditions.** App running. `LSUIElement = true` in the bundle plist (CONFIRMED — `Resources/Info.plist`, packaged by `Scripts/build-app.sh`).

**Trigger.** User interaction.

**Expected result.**

```text
S1 — Accessory presentation
Given the app is running
Then no Dock icon or app switcher entry appears (accessory activation policy)
And a menu-bar item is present

S2 — Honest status
Given the app is Degraded, or the preferred display is missing
Then the dropdown states it in plain language                [copy exists in v0.1]

S3 — State-distinct icon
Given the app is enabled / disabled / degraded / paused
Then the menu-bar icon is visually distinct per state
[PROPOSED — v0.1 renders one symbol for all; open question #8]
```

**Failure behavior.** n/a (UI surface).

**User-visible behavior.** As above. The unused `showMenuBarIcon` setting must be wired or removed before v1 (TDD §11 — a menu-bar-less mode without it is a trap).

**Testability.** Mostly manual; state-to-copy mappings unit-testable where pure.

**Priority / target.** P0 / v1.0. **Related risks:** R-009 (MenuBarExtra memory).

---

## DK-FR-007: Command-line interface

**Description.** `dockkeeper lock <edge> | unlock | status`, sharing `DockKeeperCore` and the same `UserDefaults`-backed settings as the app.

**Rationale.** Shipped early (kickoff deferred it post-v1 — harmless, keep; TDD A.3). Useful for scripting and headless fixes.

**Preconditions.** Same-user session (settings shared via standard defaults domain — CONFIRMED working). The build product is `dockkeeper-cli` to avoid the case-insensitive product-name collision with the app (CONFIRMED — git history).

**Trigger.** User invocation.

**Expected result.**

```text
S1 — Lock / unlock
When the user runs `dockkeeper lock left`
Then the desired edge is persisted and applied immediately

S2 — Status is honest
When the user runs `dockkeeper status`
Then output includes current/desired edge, enablement, and Degraded state
                                                              [CONFIRMED built]

S3 — Running app follows CLI edits
Given the menu-bar app is running
When settings change via the CLI
Then the app's published state refreshes and reconciles if needed
[PROPOSED — v0.1 gap: the app does not observe external defaults changes
 and shows stale state until relaunch; TDD A.4]
```

**Failure behavior.** Unknown arguments → usage text, non-zero exit. CoreDock unavailable in a non-AppKit process → explicit `dlopen` of HIServices hardening (PROPOSED, spike-validated).

**User-visible behavior.** Terminal output only.

**Testability.** Argument-parsing table test; `status` output snapshot (Appendix B — none exist yet).

**Priority / target.** P1 / v1.0. **Related risks:** R-004.

---

## DK-NFR-001: Quietness and resource budget

**Description.** DockKeeper must be effectively free at idle and invisible when healthy.

**Rationale.** Kickoff §6.14 budgets; a background utility that costs noticeable CPU, memory, or visual churn is worse than the problem it fixes.

**Preconditions.** None (applies in every state). **Trigger.** Continuous constraint, verified at the M6 measurement gate.

**Requirements** (targets requiring measurement — none measured yet; M6 gate):

| Metric | Target | Evidence status |
|---|---|---|
| Idle CPU | ~0% under stable conditions | INFERRED achievable (event-driven + 30 s poll of two C calls) |
| Memory | < 30 MB preferred; < 50 MB acceptable | UNKNOWN — MenuBarExtra apps commonly 25–50 MB (R-009) |
| Cold launch | < 1 s on supported hardware | INFERRED |
| Visible behavior | No Dock oscillation ever; no flicker on the primary edge path | Flicker-free CONFIRMED on-device; oscillation guard PROPOSED |

**Failure behavior.** Budget misses at M6 are release blockers or require an owner-ratified budget change.

**Testability.** 24 h idle measurement, launch timing, memory growth over repeated event storms ([test-strategy.md](test-strategy.md) reliability suite).

**Priority / target.** P0 / v1.0. **Related risks:** R-005, R-006, R-009.

---

## DK-NFR-002: Zero network communication

**Description.** DockKeeper performs no network communication during normal operation. The only outbound anything is the user-initiated "Support Development" link opening GitHub in the browser.

**Rationale.** Kickoff non-negotiables 9 and 14: no unnecessary network communication; fully useful offline.

**Preconditions.** None (applies in every state). **Trigger.** Continuous constraint on all code paths.

**Evidence.** CONFIRMED by construction — no networking code exists (TDD §3, code inspection).

**Expected result.**

```text
S1 — No requests
Given any normal operation (monitoring, restoring, preferences, CLI)
Then zero network requests are made

S2 — Donation link is passive
Given the user clicks "Support Development"
Then the system browser opens the GitHub page; nothing else fires
```

**Failure behavior.** Any regression is a release blocker.

**Testability.** CI check that no networking symbols are referenced (PROPOSED, TDD §14); manual verification with a network monitor at release.

**Priority / target.** P0 / v1.0. **Related risks:** — .

---

## DK-PRIV-001: No telemetry, accounts, or data collection

**Description.** No telemetry, analytics, accounts, advertisements, or remote backend — ever. Diagnostics are local, opt-in, and bounded.

**Rationale.** Kickoff non-negotiables 1–9: the product's entire premise is a trustworthy free alternative; privacy is not a feature tier.

**Preconditions.** None (applies in every state). **Trigger.** Continuous constraint on all code paths and all stored data.

**Expected result.**

```text
S1 — Nothing leaves the machine
Then no usage data, identifiers, or logs are transmitted anywhere   [CONFIRMED
    by construction — no networking code]

S2 — Local logs are opt-in and bounded
Given verbose logging is off (default)
Then only default os_log lines exist (system-managed retention)
Given the (proposed) diagnostics file is enabled
Then it is a ring buffer capped ~1 MB / 7 days and contains no sensitive
    names (edge names, event names, numeric display IDs only)      [PROPOSED]

S3 — No prompts
Then no donation prompt, upgrade prompt, or nag ever interrupts use
    (the kickoff allows a passive link only; v0.1 exceeds this — no
    automatic prompt exists at all)                                 [CONFIRMED]
```

**Failure behavior.** Any violation is a release blocker; no exceptions.

**Testability.** Code inspection + the DK-NFR-002 CI check; log-content review at release.

**Priority / target.** P0 / v1.0. **Related risks:** — .

---

## State transitions

The authoritative state machine (diagram and semantics) is TDD §5.1. States: `Disabled`, `Starting`, `Monitoring`, `Restoring`, `PreferredDisplayMissing`, `Degraded`, `Paused` (planned), `Error`.

**Documented deviation from the kickoff template:** `Awaiting Permission` is dropped for v1 because no privacy-gated permission exists to await (TDD §10 — CONFIRMED that all v1 mechanisms need none). It returns if a follow-window feature ever ships.

| Transition | Trigger | Requirement |
|---|---|---|
| Disabled → Starting → Monitoring | User enables; initial reconcile completes | DK-FR-004 S2 |
| Monitoring → Restoring → Monitoring | Drift/event; convergence | DK-FR-001 S1, DK-FR-003 |
| Restoring/Monitoring → PreferredDisplayMissing | Preferred display absent | DK-FR-002 S3 |
| PreferredDisplayMissing → Restoring | Display reconnects | DK-FR-002 S4 |
| Restoring → Degraded | CoreDock unavailable | DK-FR-001 S3 |
| Restoring → Error | Retry ladder exhausted / oscillation budget | DK-FR-003 S4 |
| Error → Monitoring | Next event or manual retry | DK-FR-003 |
| any → Disabled | User disables | DK-FR-004 S1 |
