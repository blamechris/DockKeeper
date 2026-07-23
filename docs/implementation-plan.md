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
| CoreDock-persistence spike (does a live set survive `killall Dock`?) | #3 | R-011 |
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

## M2 — Display registry 🟡

Built: enumeration + UUID mapping. Remaining (ADR-004):

- `DisplayFingerprint` (Codable) + scored matching + unique-max acceptance rule.
- Stale-preference repair (rewrite on fallback-evidence match).
- Migration: `preferredDisplayUUID` → fingerprint with only `uuid` set. **Rollback note:** migration must be one-way-safe — keep the old key until v1.1 so a reverted build still works.
- Stop persisting `"cg-<id>"` pseudo-UUIDs (A.4); real names via `NSScreen.localizedName`.
- Ambiguity surface: "pick your preferred display again" flow.

**Acceptance.** Score table, tie→ambiguous, repair, and migration all unit-tested (traceability rows in the test strategy). **Dependencies.** None (thresholds tuned later on the M6 rig).

## M3 — Dock observation 🟡

Built: all event sources + poll. Remaining:

- Split observation from recovery: `DockMonitor` emits typed `DockEvent` values only.
- Debounce + generation-counter coalescing (TDD §8.3).
- Dock-restart detection (mechanism UNKNOWN — candidates in §8.1; pick via M0 spike #3).
- Observe external `UserDefaults` changes (CLI edits reflect live — DK-FR-007-S3).
- Fix `DockMonitor.stop()` indiscriminate observer removal; drop the unused `DistributedNotificationCenter` registration (A.4).

**Acceptance.** Synthetic burst → exactly one reconcile (S2 test green). **Dependencies.** Coordinator skeleton (M4) for the event sink; land together.

## M4 — Dock restoration (the recovery engine) 🟡 — **critical path**

Built: basic restore works end-to-end. Remaining — this is the largest single work item:

- `RecoveryCoordinator` with pure `decide(state, event, now)` core: retry ladder (0/+1.5/+4 s), cooldown budget (6/60 s → `Error`), echo suppression, single-owner state machine per TDD §5.1/§8.3.
- `DockAdapter` protocol seam (`CoreDockAdapter`/`DefaultsAdapter`) — **build first**; it unblocks most unit tests (test-strategy priority).
- Explicit `dlopen` of HIServices in `CoreDock` (spike-validated hardening for non-AppKit processes).
- Poll default 2 s → 30 s + poll-caught-drift counter (ADR-005).
- Mirror CoreDock sets into defaults **iff** M0 spike #3 shows non-persistence (R-011).

**Acceptance.** All DK-FR-003 scenarios S1–S5 unit-green; no oscillation over the reliability suite's 100-restore run. **Risks.** R-005, R-011. **Rollback.** Coordinator sits behind the existing enable flag; the legacy path stays until M4 acceptance passes, then is deleted in its own commit.

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

From TDD A.4, tracked here so it isn't lost: observer-removal fix + dead `DistributedNotificationCenter` (M3) · icon ternary + `showMenuBarIcon` (M1) · pseudo-UUID persistence (M2) · external-defaults observation (M3) · `Log.verbose` static folded into diagnostics rework (M1) · `autoRecover` vs `enabled` semantics decision (open question #9 — owner UX call, needed before M4 copy is final).

**Out of scope for v1.0** (kickoff/TDD non-goals): follow-mouse/window/app modes, Shortcuts/Raycast/AppleScript, per-app rules and profiles, App Store, auto-update (Sparkle needs a post-v1 ADR), restoring display arrangement on disable (open question #5 — owner call pending).
