# DockKeeper — Implementation Plan (v0.1 → v1.0)

| | |
|---|---|
| **Status** | Draft for review |
| **Date** | 2026-07-22 |
| **Owner** | blamechris |
| **Scope** | Delta plan from the current scaffold (72fbcc2) to v1.0, structured on the kickoff milestones (TDD Appendix A.3 status) |
| **Inputs** | [Technical design](technical-design.md) (A.3 milestone status, A.4 debt, §17 open questions), [test strategy](test-strategy.md), [risk register](risk-register.md) |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

This is a **backfill/delta plan**: the repo went implementation-first, so several milestones are partially done. Each milestone lists only the *remaining* work. Status keys: ✅ done · 🟡 partial · ❌ not started. Rollback strategy is uniform unless noted: work lands in small reviewable commits behind existing settings where possible; revert the commit(s) to roll back — no data migrations except where called out (M2).

**Sequencing.** M0 spikes unblock design certainty but don't block M1–M4 code. Critical path to v1.0: **M4 (recovery engine) → M6 (hardware validation) → M7 (release)**. M6 is the schedule risk — it needs a 2-monitor rig (R-002).

---

## M0 — Research & feasibility 🟡

Central spike done (mechanism + pinning + Spaces gating, owner decisions recorded — CONFIRMED). Remaining spikes, from TDD §17:

| Deliverable | Answers open question | Risk |
|---|---|---|
| UUID-stability spike (reconnect/dock/adapter/reboot table) | #2 | R-003 |
| ~~CoreDock-persistence spike~~ ✅ Done 2026-07-22 — write-through to defaults CONFIRMED ([findings](../Documentation/spikes/coredock-defaults-persistence.md)); restarts are benign, no mirroring needed, R-011 closed | #3 | R-011 |
| Event-burst instrumentation session (real burst profile → debounce width) | #4 | R-005 |
| Mirroring/clamshell behavior notes | #6 | R-002 |

**Acceptance.** Each spike has a Findings write-up in `Documentation/spikes/` with evidence labels and a recommendation. **Dependencies.** #2/#6 need the M6 rig; #3/#4 run on the single-display dev machine now.

## M1 — Application shell 🟡

Built: menu bar, Preferences, login item, os_log, ad-hoc-signed `.app` packaging (`Scripts/build-app.sh`, `LSUIElement` plist — CONFIRMED at 72fbcc2, superseding the TDD's "packaging absent"). Remaining:

- Opt-in bounded file diagnostics + export action (ring buffer ~1 MB/7 days — PROPOSED, TDD §12) with `diagnosticsFileEnabled` key.
- State-distinct menu-bar icons (enabled/disabled/degraded/paused — open question #8).
- Wire up or delete the dead `showMenuBarIcon` setting.
- `settingsVersion` key (migration hook for M2).

**Acceptance.** Diagnostics file caps verified by test; icon states visible in manual pass. **Tests.** Log-growth bound (reliability suite). **Risks.** R-009 (measure at M6).

## M2 — Display registry ✅ (2026-07-23)

- ✅ `DisplayFingerprint` (Codable) + `FingerprintMatcher` scored matching with the unique-max ≥ 70 acceptance rule.
- ✅ Stale-preference repair (`DisplayIdentityResolver` returns a refreshed fingerprint on fallback-evidence matches; `Settings.repairPreferredDisplay` persists it).
- ✅ Migration: legacy `preferredDisplayUUID` → fingerprint (write-once); legacy key mirrored until v1.1 for rollback; `"cg-<id>"` pseudo-UUIDs discarded, never persisted.
- ✅ Real display names via `NSScreen.localizedName` (menu + fingerprint evidence).
- ✅ Ambiguity surfaced: `PinOutcome.ambiguousIdentity` — "pick your preferred display again", never guess.

**Acceptance met:** score table, tie→ambiguous, repair, migration, and mirror-key behavior all unit-tested ([DisplayIdentityTests.swift](../Tests/DockKeeperTests/DisplayIdentityTests.swift); 61 tests total passing). Score thresholds remain PROPOSED pending M6 hardware tuning.

## M3 — Dock observation ✅ (2026-07-22)

- ✅ `DockMonitor` emits typed `DockEvent` values only; all decisions moved to the coordinator.
- ✅ Debounce + generation-counter coalescing (in `RecoveryCoordinator`, TDD §8.3).
- ✅ External `UserDefaults` observation via KVO (cross-process; CLI edits reflect live — DK-FR-007-S3).
- ✅ `stop()` observer removal fixed (per-center lists); unused `DistributedNotificationCenter` dropped (A.4).
- ~~Dock-restart detection~~ **Dropped**: spike #3 proved restarts benign (CoreDock writes through to defaults); the poll covers the residual gap.

**Acceptance met:** synthetic burst → exactly one reconcile (S2 test green in `RecoveryTests.swift`).

## M4 — Dock restoration (the recovery engine) ✅ code complete (2026-07-22)

- ✅ `RecoveryCoordinator` + pure `RecoveryMachine` core: retry ladder (0/+1.5/+4 s), cooldown budget (6/60 s → `Error`), echo suppression, generation coalescing, single-owner state machine per TDD §5.1/§8.3.
- ✅ `DockAdapter` protocol seam (`CoreDockAdapter`/`DefaultsDockAdapter`); `DockController` refactored onto it with `isDegraded` reporting.
- ✅ Explicit `dlopen` of the ApplicationServices umbrella in `CoreDock` (spike-validated hardening; CLI verified on-device).
- ✅ Poll default 30 s + poll-caught-drift counter (ADR-005); `autoRecover` removed (ADR-007).
- ~~Mirror CoreDock sets into defaults~~ **Not needed**: spike #3 confirmed CoreDock writes through (R-011 closed).

**Acceptance:** all DK-FR-003 scenarios S1–S5 unit-green (`RecoveryTests.swift`, 26 new tests; 39 total passing). The 100-restore no-oscillation run belongs to the reliability suite → verified at **M6**. Legacy restore path deleted in the same change (the coordinator is the only reconciler).

## M5 — Permission & onboarding ✅ (by elimination)

No privacy-gated permission exists in v1 (TDD §10 — CONFIRMED); Login Items approval UX is built. No work. Reopens only if follow-window ships (post-v1).

## M6 — Reliability (hardware validation) ❌ — **gate for v1.0**

- Acquire/borrow a 2-monitor rig; execute the full [manual matrix](test-strategy.md#3-manual-system-tests-hardware-matrix).
- **Verify the INFERRED core claim: main-display relocation moves the Dock** (R-002 — top risk; if false, DK-FR-002 copy narrows, architecture stands per Decision 3).
- Measure DK-NFR-001 budgets (24 h idle CPU, memory, cold launch); tune fingerprint thresholds and debounce width with real data.
- Run reliability suite (sleep/wake cycles, replug storms, long-run).

**Acceptance.** Matrix results recorded per cell; budgets met or owner-ratified adjustments logged as ADR amendments; risk register updated with evidence. **Dependencies.** M2–M4 complete; rig available (schedule risk).

## M7 — Release ❌

Developer ID signing + notarization pipeline, `.dmg`/`.zip` artifacts, Homebrew cask, app icon, README/privacy statement, issue templates — executed via the [release checklist](release-checklist.md). **Dependencies.** M6 green; ADR-003 ratified; R-010 trademark check done.

---

## Cross-cutting debt (fold into the touching milestone)

From TDD A.4, tracked here so it isn't lost: ~~observer-removal fix + dead `DistributedNotificationCenter`~~ ✅ · icon ternary + `showMenuBarIcon` (M1) · pseudo-UUID persistence (M2) · ~~external-defaults observation~~ ✅ · `Log.verbose` static folded into diagnostics rework (M1) · ~~`autoRecover` removal per ADR-007~~ ✅ (all ✅ 2026-07-22 with M3/M4).

**Out of scope for v1.0** (kickoff/TDD non-goals): follow-mouse/window/app modes, Shortcuts/Raycast/AppleScript, per-app rules and profiles, per-display Dock allow/disallow, App Store, auto-update (Sparkle needs a post-v1 ADR), restoring display arrangement on disable (resolved leave-as-is — ADR-006). These deferred modes are exactly the **DockLock Plus/Pro** premium differentiators (follow mouse/active app/active window, per-display allow, automation, Shortcuts/Raycast — CONFIRMED from public product pages); staged parity is intentional per kickoff §17, and parity claims stay evidence-gated (AGENTS rule 17) until `docs/product-investigation.md` exists.
