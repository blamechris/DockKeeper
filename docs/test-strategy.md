# DockKeeper — Test Strategy

| | |
|---|---|
| **Status** | Draft for review |
| **Date** | 2026-07-22 |
| **Owner** | blamechris |
| **Scope** | v1.0 verification: unit, integration, manual hardware matrix, reliability |
| **Inputs** | [Behavior specification](behavior-specification.md), [Technical design](technical-design.md) (Appendix B, §4.3 test seams), kickoff package §7 |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

## Principles

- **Every behavioral requirement maps to one or more tests** (traceability table below). A requirement without a named test is a gap, listed as such.
- **macOS side effects live behind adapters; decision logic is pure.** We do not force unit tests around untestable side effects (moving the real Dock, `SMAppService`) — we wrap them and test the decisions (kickoff §7 rule). `MainDisplayPinner.decide` already follows this pattern (CONFIRMED); `DockAdapter` is the priority missing seam (TDD §4.3).
- **Behavior-focused test names**, e.g. `testDuplicateDisplayEventsProduceSingleRecoveryAttempt()`.
- **TDD development rule** for implementation work: (1) add/update the requirement → (2) write the failing test → (3) smallest passing change → (4) refactor → (5) run the relevant suite → (6) update docs when behavior or architecture changed.
- Framework: Swift Testing (`import Testing`, `@Suite`/`@Test`) — CONFIRMED in use.

## Test levels

### 1. Unit tests (fast, no system effects)

Targets: state reconciliation (`RecoveryCoordinator.decide` with synthetic events + simulated clock), display fingerprint matching/scoring/tie-handling/repair/migration, retry ladder and backoff, debounce/coalescing (generation counter), cooldown/oscillation budget, echo suppression, failure classification, orientation model mapping, settings persistence and migration, CLI argument parsing, `LoginItemManager.message(for:)` mapping.

Required seams (TDD §4.3): `DockAdapter` protocol with a recording fake (**missing in v0.1 — build first**); injected `applyMain` closure (exists — CONFIRMED); typed `DockEvent` values (post-M3 refactor); injectable clock for ladder/cooldown tests (PROPOSED).

### 2. Integration tests (real frameworks, isolated state)

Preferences persistence against isolated `UserDefaults` suites (pattern exists in `SettingsTests` — CONFIRMED); UUID→fingerprint migration on a populated suite; coordinator + monitor with mocked adapters driven by synthetic event sequences; CLI end-to-end against an isolated defaults domain; external-defaults-change observation (DK-FR-007-S3).

### 3. Manual system tests (hardware matrix)

**Blocked on a 2-monitor rig — the M6 gate and top project risk (R-002).** Adapted from kickoff §7; Accessibility rows dropped (no permission in v1 — TDD §10).

| Dimension | Cases |
|---|---|
| Topology | 1 display · 2 displays · 3+ · built-in + external · two identical externals (identity tie → must ask, never guess) |
| Connection | DisplayPort · HDMI · USB-C · docking station (UUID stability across each — R-003) |
| Events | disconnect · reconnect · sleep/wake · rapid replug · resolution change · arrangement change · Dock process restart (`killall Dock`) · reboot · logout/login |
| Modes | separate Spaces ON (pin declined + explained) and OFF · mirroring (UNKNOWN correct behavior — spike) · clamshell · fullscreen apps · Stage Manager · Dock autohide |
| Edges | bottom · left · right, each surviving every event above |
| Pinning | pin moves Dock + menu bar (verify the INFERRED core claim!) · preferred display absent → no fallback pin · reconnect → re-pin |
| Login item | approval flow, `.requiresApproval` deep link, packaged-app vs `swift run` |

Each cell records: pass/fail, macOS version, hardware path, and any drift latency observed. Results feed the risk register and ADR-005's poll-interval evidence.

### 3b. Manual instance tests (no hardware gate)

**Single-instance guard (DK-FR-012 / [ADR-012](decision-log.md#adr-012-single-instance-guard-in-process-at-appinit-lsmultipleinstancesprohibited-withheld)), in risk order.** Deliberately **not** part of §3: none of these needs a second monitor, so they are runnable today on one Mac plus one extra user account and must not sit behind the R-002 hardware gate. **Not yet run**: the pure decision is exhaustively unit-tested and the LaunchServices behaviors are probe-CONFIRMED, yet the assembled guard has never been exercised against a real double launch.

| # | Case | Expected | Why it ranks here |
|---|---|---|---|
| 1 | **Second user account, fast user switching.** With DockKeeper running in session 1, log in as a second user and launch it there | Both sessions get their own instance — the guard is per-session (`NSRunningApplication` is session-scoped, INFERRED) | Highest blast radius, and it gates the **shipped** guard, not just a follow-on: if the peer read is not session-scoped, user 2's launch exits silently with no error surface at all — the "zero instances, silently" outcome `LSMultipleInstancesProhibited` was rejected for, already shipped. Secondarily it decides that follow-on: refused here → WONTFIX, recorded in ADR-012 |
| 2 | **Login-item path.** Log out and back in with the login item registered | Exactly one instance; no stderr notice in the log from a self-deflection | The one launch path no developer exercises by hand; also whether an `SMAppService.mainApp` launch routes through LaunchServices at all is UNKNOWN (untestable without logging out) |
| 3 | **`Scripts/run-app.sh` twice in a row** while the app is running | Exactly **one** process afterwards, running the **newly built** binary. If the previous build ignores `SIGTERM`, the script escalates to `SIGKILL` and, failing that, **exits non-zero** instead of rebuilding | This is the second duplicate vector and the primary script fix. New row — §3 previously had no `run-app.sh` case at all; the investigation's initial belief that the script harmlessly relaunched the stale binary was refuted by the control experiment in ADR-012 |
| 4 | **`open "dockkeeper://pause"`** while running | The pause takes effect on the running instance; nothing is spawned or deflected | Regression guard on DK-FR-010: a plain URL open is a Path-B open LaunchServices routes to the running app (`allowsRunningApplicationSubstitution` defaults true) — the guard must not break automation |
| 5 | **`open /Applications/DockKeeper.app`** while `dist/` runs | One icon survives, and it is the **first** one — even though it may be the older version | The observed duplicate vector, and the explicit test of "senior, not newest" (DK-FR-012 Failure behavior) |
| 6 | **`dist/DockKeeper.app/Contents/MacOS/DockKeeper --diagnostics`** while running | The report still prints, and `Other instances:` names the running copy and its bundle path | `--diagnostics` is the documented support flow and is run *while* an instance is live; if the guard pre-empts it, support loses its only view of the duplicate |
| 7 | **Direct exec of the inner binary** (no `--diagnostics`) while a registered copy runs | Exits with the stderr notice, no second icon | The no-LaunchServices-date case as a **newcomer** |
| 7b | **The mirror of 7: direct exec FIRST**, then `open /Applications/DockKeeper.app` | The `open`ed copy exits — the direct exec is senior and keeps the Dock | The direction the ordering used to get wrong: with a dateless class, a direct-`exec`ed incumbent was outranked by every registered newcomer and **both** ran. Verifies the kernel start-time substitution end-to-end (ADR-012 Decision) |
| 8 | **`dockkeeper lock left`** from the CLI while the app runs | Unchanged — the command applies, nothing is deflected | `dockkeeper-cli` is a legitimate third process; the guard must never reach it (ADR-012 Consequences) |
| 9 | **`swift run DockKeeper`** while the `.app` runs | **Two instances, by design** — confirm no crash and that the behavior matches DK-FR-012 S7 | Documents a known, deliberate hole rather than discovering it later as a defect |

Each row records: pass/fail, macOS version, which bundle paths were registered at the time, and the exit path observed (stderr notice / log line / neither). Note that **`open`'s exit status is not evidence** — it returns 0 whether the launch survived or was deflected (measured), so every row must be checked by counting menu-bar icons or live pids.

### 4. Reliability tests

100 consecutive restorations (no oscillation, no leak); repeated sleep/wake cycles; rapid display connect/disconnect storms; resolution change during an in-flight restoration; preference change during restoration; app relaunch during pending recovery; 24 h idle (CPU ~0%, memory flat, log growth bounded) — the DK-NFR-001 measurement gate (M6).

### 5. CI gates (PROPOSED)

`swift build && swift test` on a macOS 14 runner; release builds additionally: `Scripts/build-app.sh` succeeds, `codesign --verify` passes, and a **no-networking-symbols check** (scan the binaries for `NSURLSession`/`Network.framework` references) enforcing DK-NFR-002 by construction.

## Requirements → tests traceability

Existing suites (39 tests — CONFIRMED 2026-07-22): `DockOrientationTests` (5), `SettingsTests` (2), `DisplayPinnerTests` (6 — every `decide` branch) in [DockOrientationTests.swift](../Tests/DockKeeperTests/DockOrientationTests.swift); `RecoveryMachine`/`RecoveryCoordinator` suites (31 — decide, ladder, echo, cooldown, coalescing, poll counter, disable teardown, plus DK-FR-009 pause/resume transitions and orchestration) in [RecoveryTests.swift](../Tests/DockKeeperTests/RecoveryTests.swift); `DockControllerTests` (6 — adapter seam, fallback, degraded) in [DockControllerTests.swift](../Tests/DockKeeperTests/DockControllerTests.swift). Automation (DK-FR-010) added `ControlCommandParseTests` (16) + `StatusSummaryTests` (3) in [ControlCommandTests.swift](../Tests/DockKeeperTests/ControlCommandTests.swift). Screen-share hide (DK-FR-011) added `ScreenShareHider.decide` + lifecycle/settings suites (8) in [ScreenShareTests.swift](../Tests/DockKeeperTests/ScreenShareTests.swift); the suite total was **115 tests — CONFIRMED 2026-07-25** (the newest at that point was the `Settings` shared-domain guard, DK-FR-007). The single-instance guard (DK-FR-012) adds an `InstanceGuard.decide` suite — 12 `@Test` cases, one of them a 27-combination survivor sweep — in [InstanceGuardTests.swift](../Tests/DockKeeperTests/InstanceGuardTests.swift), bringing the suite total to **127 tests — CONFIRMED 2026-08-17** (`swift test`: 127 tests in 24 suites).

| Requirement / scenario | Existing coverage | Needed |
|---|---|---|
| DK-FR-001 S1–S3 (restore, idempotence, fallback) | ✅ `DockControllerTests` (fake adapters) + `RecoveryMachineTests` (Degraded transition) | — |
| DK-FR-001 S4 (no top edge) | ✅ `userSelectableExcludesTop`, raw-value mapping | — |
| DK-FR-002 S1, S5 (pin decisions) | ✅ `DisplayPinnerTests` all six branches | Arrangement-preserving origin math; hardware verification (matrix) |
| DK-FR-002 S2/S2b (separate-Spaces gate: bottom declines, left/right pins — ADR-009) | ✅ `unsupportedSeparateSpacesBottom` + `separateSpacesLeftRightPins` | Manual: UI copy shown; matrix cells for left/right-in-mode under wake/replug |
| DK-FR-002 S3–S4 (absent / re-pin on return) | ✅ `displayNotConnected` (decision only) | Event-sequence test: reconnect → re-pin; `PreferredDisplayMissing` state transitions |
| DK-FR-003 S1 (wake ladder) | ✅ `RecoveryTests` (machine + coordinator, simulated clock) | — |
| DK-FR-003 S2 (burst → single attempt) | ✅ `duplicateEventsProduceSingleAttempt` | — |
| DK-FR-003 S3 (echo suppression) | ✅ machine + coordinator echo tests | — |
| DK-FR-003 S4 (oscillation guard) | ✅ `oscillationGuard` / `oscillationStops` | — |
| DK-FR-003 S5 (poll safety net) | ✅ `pollCountsDrift` (unit) | Integration tick test with a real timer |
| DK-FR-004 (enable/disable) | ✅ `SettingsTests` (persistence) + `disableStrandsPasses` (no residual corrections) | Observer-teardown integration test |
| DK-FR-005 (login item) | — | Unit: `message(for:)` mapping; manual: approval matrix row |
| DK-FR-006 (menu bar) | — | Manual; state→copy mapping unit tests where pure |
| DK-FR-007 (CLI) | — | Argument-parsing table test; `status` snapshot; external-change observation (S3) |
| DK-FR-009 S1–S5 (pause / temporary move) | ✅ `RecoveryCoordinatorPauseTests` (strand-on-pause, ignore-events, auto-resume via fake scheduler, manual-resume strands stale timer, second-pause supersedes) + `RecoveryMachineTests` pause/resume transitions incl. from-disabled rejection | Manual: menu items shown/hidden by enabled state; hotkey registration + system-wide toggle (out of unit scope) |
| DK-FR-010 S1–S4 (Shortcuts + URL scheme) | ✅ `ControlCommandParseTests` (16 — full parse table: four commands, edge case-insensitivity, top rejected, minutes present/absent/zero/negative/garbage/non-finite/over-cap, unknown host, foreign scheme, extras ignored) + `StatusSummaryTests` (3 — CLI-line + voice-line parity with `dockkeeper status`) in [ControlCommandTests.swift](../Tests/DockKeeperTests/ControlCommandTests.swift) | Manual (INFERRED, not run on-device): S5 Shortcuts/Siri discovery + URL-open dispatch; App Intents metadata extraction in packaging (out of unit scope) |
| DK-FR-011 S1–S6 (hide Dock during screen capture — ADR-011) | ✅ `ScreenShareHider.decide` truth table (all 8 `capturing × weHidIt × currentAutoHide` combos, incl. never-touch-user-auto-hide, idempotence, teardown-safe) + settings default-false / persist / fresh-hider-no-op / poll-cadence in [ScreenShareTests.swift](../Tests/DockKeeperTests/ScreenShareTests.swift) | Manual / **UNKNOWN pending on-device** (M6/M12): does the `CGSIsScreenWatcherPresent` flag flip on a real capture, latency, which apps (QuickTime/Zoom/Teams/Screen Sharing.app); private-API reads/writes never unit-tested (would move the real Dock) |
| DK-FR-012 S1–S9 (single-instance guard — ADR-012) | ✅ `InstanceGuard.decide` suite in [InstanceGuardTests.swift](../Tests/DockKeeperTests/InstanceGuardTests.swift): sole instance, self-in-peer-list, newcomer yields, junior ignored, path is never consulted so both duplicate vectors reduce to one decision, pid wrap-around vs start time, dateless newcomer yields, dated beats dateless, **newcomer yields to a settled incumbent in either pid order** (the sequential-incumbency invariant the sweep does not model), `--diagnostics` never pre-empted, exact-match escape hatch, and a 27-case sweep asserting **exactly one survivor** over every start-time shape | Manual matrix §3b, **not yet run** — item 1 (second account / fast user switching) gates the shipped guard itself as well as the `LSMultipleInstancesProhibited` follow-on; item 7b covers the direct-exec-incumbent direction. The `NSRunningApplication` read, the `sysctl` start-time substitution and the `exit()` in `SingleInstance` are never unit-tested (the last ends the process); unbundled `swift run` builds are deliberately unguarded |
| DK-NFR-001 (budget) | — | Reliability suite measurements (M6 gate) |
| DK-NFR-002 / DK-PRIV-001 | CONFIRMED by construction (no networking code) | CI symbol check; release network-monitor pass; log-content review |
| Display identity (ADR-004) | ✅ `DisplayIdentityTests` (score table, tie→ambiguous, repair rewrite, migration incl. `cg-` discard, legacy mirror) | Threshold tuning against real hardware (M6) |

## Gaps and sequencing

~~The recovery coordinator and `DockAdapter` seam~~ — landed with tests 2026-07-22 (M3/M4). ~~Fingerprint identity~~ — landed with tests 2026-07-23 (M2). Every P0/P1 decision path now has unit coverage (61 tests); what remains is integration-level polish (CLI argument table, `status` snapshot, poll tick with a real timer) and the manual matrix (M6), the only level gated on hardware.
