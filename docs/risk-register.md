# DockKeeper — Risk Register

| | |
|---|---|
| **Status** | Living document |
| **Date** | 2026-07-22 |
| **Owner** | blamechris |
| **Inputs** | Kickoff package §10 (seed rows, recovered verbatim), [Technical design](technical-design.md) §1/§15/§17, [Preferred-display spike](../Documentation/spikes/preferred-display-spike.md) |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

Lineage: **K** = carried from the kickoff package's seed register; **N** = added during design review (2026-07-22). Risk IDs are stable and referenced from the [behavior specification](behavior-specification.md) and [decision log](decision-log.md).

## Active risks

Ordered by current severity.

| ID | Lineage | Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---|---|---|---|---|
| R-002 | N | **Multi-monitor pinning behavior is partially unverified.** The relocation *mechanism* is now CONFIRMED on real hardware — transaction succeeds with portrait geometry, arrangement preserved, cleanly reversible ([session 1](hardware-matrix-results.md), 2026-07-23). Still INFERRED: that the Dock itself homes to the new main display (observable only with separate Spaces OFF), and drift presentation on unplug/replug. | Medium | High | Finish the M6 matrix: separate-Spaces-OFF session (logout required), replug/sleep-wake cells. Feature is scoped best-effort (Decision 3), so a partial result narrows copy, not architecture. | Open — mechanism half retired 2026-07-23 |
| R-004 | N | **CoreDock private-API fragility.** A future macOS could remove or change the `CoreDockGet/SetOrientationAndPinning` symbols or their semantics, breaking the primary edge-lock path. | Medium | High | Runtime `dlsym` (a missing symbol is a fallback, not a crash — CONFIRMED design); `DefaultsAdapter` fallback + visible `Degraded` state; per-macOS-release smoke test on the [release checklist](release-checklist.md); ADR-003 documents the accepted trade. | Open |
| R-003 | K | **Display identifiers change across hardware paths** (docks, adapters, reconnects, reboots). UUID stability is explicitly UNKNOWN. | Medium | High | Store multiple identifiers and use scored matching with stale-preference repair (ADR-004, TDD §7); pseudo-UUIDs never persisted; ambiguity → ask, never guess. | Open — **mitigations implemented 2026-07-23** (fingerprint/matcher/repair/migration, unit-tested); UUID-stability spike + threshold tuning still need M6 hardware (open question #2) |
| R-005 | K | **Recovery causes visible Dock oscillation** or a silent infinite fight with another agent. | Medium | High | Debounce + generation coalescing, retry ladder, cooldown budget (max 6 corrections/60 s → `Error` + tell the user), echo suppression for self-caused events (TDD §8.3–8.4). | Open — **mitigations implemented 2026-07-22** (`RecoveryCoordinator`/`RecoveryMachine`, unit-tested); 100-restore reliability verification remains at M6 |
| R-006 | K | **Event gaps require limited polling.** Notifications may miss cases (unobserved causes, failed registrations); pure event-driven could leave drift standing. | Medium | Medium | Hybrid monitoring: events primary, 30 s poll as safety net (ADR-005); count poll-caught drift locally to tune the interval with evidence. | Open — **implemented 2026-07-22** (30 s default + `pollCaughtDriftCount`); needs field data before re-tuning |
| R-009 | N | **MenuBarExtra memory ceiling.** SwiftUI `MenuBarExtra` apps commonly land at 25–50 MB, against the kickoff's < 30 MB preferred budget. | Medium | Medium | Measure at M6; treat < 50 MB as acceptable, < 30 MB as stretch (TDD §14, owner-visible budget change); fall back to an AppKit `NSStatusItem` shell only if measurement demands it. | Open — unmeasured |
| R-010 | K | **"DockKeeper" may conflict with an existing product name or trademark.** The competitor being replaced is the **DockLock family** (DockLock Lite / DockLock Plus / DockLock Pro — CONFIRMED, public App Store listings and docklockpro.com), so the shared "Dock" prefix and Lock/Keeper near-synonymy make this a substantive check, not pro forma. | Medium | Medium | Name and trademark review before first public release (release-checklist gate; TDD open question #10). Rules 3/17 apply: independent implementation, no branding proximity beyond the name question, no parity claims without evidence. | Open |

## Retired / closed risks

| ID | Lineage | Risk | Outcome |
|---|---|---|---|
| R-001 | K | **No supported API can reliably move the Dock** (was: High/Critical — the project's founding uncertainty). | **Retired 2026-07-22 for edge lock**: the feasibility spike CONFIRMED on-device that `CoreDock` sets the edge live and flicker-free, with `defaults`+`killall` as a public-path fallback. The *display* dimension of the risk lives on as R-002 (no direct API exists; main-display relocation is the accepted best-effort route, owner Decision 1). |
| R-007 | K | **App Sandbox blocks required behavior.** | **Materialized and accepted 2026-07-22**: the sandbox blocks both `killall` and private-API use (CONFIRMED policy), so Mac App Store distribution is off the table for v1. Mitigation applied as designed — Developer ID direct download + Homebrew cask (ADR-002). Revisit only if a supported mechanism appears. |
| R-008 | K | **Accessibility behavior changes between macOS releases.** | **Closed for v1 (not applicable)**: the chosen mechanisms require no Accessibility permission at all (TDD §10, CONFIRMED on-device). Reopens automatically if a follow-focused-window feature ships post-v1. |
| R-011 | N | **A live CoreDock set may not survive a Dock restart.** | **Closed 2026-07-22**: on-device spike CONFIRMED `CoreDockSet` writes through to `com.apple.dock` defaults ([findings](../Documentation/spikes/coredock-defaults-persistence.md)) — restarts re-read the edge we set. No mirroring, no Dock-restart detection needed; the release-checklist CoreDock smoke test re-verifies per macOS release. |

## Review cadence

Re-review at each milestone boundary ([implementation plan](implementation-plan.md)) and at every macOS point release while R-004 is open. Additions require an ID, lineage, likelihood/impact, and a named mitigation; closures record the evidence (kickoff rule 15: record risks instead of silently assuming them away).
