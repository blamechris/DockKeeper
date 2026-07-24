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

### 4. Reliability tests

100 consecutive restorations (no oscillation, no leak); repeated sleep/wake cycles; rapid display connect/disconnect storms; resolution change during an in-flight restoration; preference change during restoration; app relaunch during pending recovery; 24 h idle (CPU ~0%, memory flat, log growth bounded) — the DK-NFR-001 measurement gate (M6).

### 5. CI gates (PROPOSED)

`swift build && swift test` on a macOS 14 runner; release builds additionally: `Scripts/build-app.sh` succeeds, `codesign --verify` passes, and a **no-networking-symbols check** (scan the binaries for `NSURLSession`/`Network.framework` references) enforcing DK-NFR-002 by construction.

## Requirements → tests traceability

Existing suites (39 tests — CONFIRMED 2026-07-22): `DockOrientationTests` (5), `SettingsTests` (2), `DisplayPinnerTests` (6 — every `decide` branch) in [DockOrientationTests.swift](../Tests/DockKeeperTests/DockOrientationTests.swift); `RecoveryMachine`/`RecoveryCoordinator` suites (31 — decide, ladder, echo, cooldown, coalescing, poll counter, disable teardown, plus DK-FR-009 pause/resume transitions and orchestration) in [RecoveryTests.swift](../Tests/DockKeeperTests/RecoveryTests.swift); `DockControllerTests` (6 — adapter seam, fallback, degraded) in [DockControllerTests.swift](../Tests/DockKeeperTests/DockControllerTests.swift).

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
| DK-NFR-001 (budget) | — | Reliability suite measurements (M6 gate) |
| DK-NFR-002 / DK-PRIV-001 | CONFIRMED by construction (no networking code) | CI symbol check; release network-monitor pass; log-content review |
| Display identity (ADR-004) | ✅ `DisplayIdentityTests` (score table, tie→ambiguous, repair rewrite, migration incl. `cg-` discard, legacy mirror) | Threshold tuning against real hardware (M6) |

## Gaps and sequencing

~~The recovery coordinator and `DockAdapter` seam~~ — landed with tests 2026-07-22 (M3/M4). ~~Fingerprint identity~~ — landed with tests 2026-07-23 (M2). Every P0/P1 decision path now has unit coverage (61 tests); what remains is integration-level polish (CLI argument table, `status` snapshot, poll tick with a real timer) and the manual matrix (M6), the only level gated on hardware.
