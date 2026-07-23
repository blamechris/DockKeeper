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
| R-002 | N | **Multi-monitor pinning behavior is unverified.** Main-display relocation is CONFIRMED available, but whether it actually moves the Dock — and how drift presents on unplug/replug — has never been observed on real hardware (single-display dev rig). The entire DK-FR-002 feature is INFERRED. | High | High | 2-monitor rig session before calling pinning "done" (M6 gate; TDD open question #1). Feature is already scoped best-effort (Decision 3), so a partial result narrows copy, not architecture. | Open — **top project risk** |
| R-004 | N | **CoreDock private-API fragility.** A future macOS could remove or change the `CoreDockGet/SetOrientationAndPinning` symbols or their semantics, breaking the primary edge-lock path. | Medium | High | Runtime `dlsym` (a missing symbol is a fallback, not a crash — CONFIRMED design); `DefaultsAdapter` fallback + visible `Degraded` state; per-macOS-release smoke test on the [release checklist](release-checklist.md); ADR-003 documents the accepted trade. | Open |
| R-003 | K | **Display identifiers change across hardware paths** (docks, adapters, reconnects, reboots). UUID stability is explicitly UNKNOWN; the unstable `"cg-<id>"` pseudo-UUID fallback in v0.1 can currently be persisted as a preference. | Medium | High | Store multiple identifiers and use scored matching with stale-preference repair (ADR-004, TDD §7); never persist pseudo-UUIDs; ambiguity → ask, never guess. UUID-stability spike on hardware (open question #2). | Open — mitigation designed, not yet implemented |
| R-005 | K | **Recovery causes visible Dock oscillation** or a silent infinite fight with another agent. v0.1 has no debounce, no cooldown, and would fight forever every 2 s. | Medium | High | Debounce + generation coalescing, retry ladder, cooldown budget (max 6 corrections/60 s → `Error` + tell the user), echo suppression for self-caused events (TDD §8.3–8.4). | Open — mitigation designed (PROPOSED), not yet implemented |
| R-011 | N | **A live CoreDock set may not survive a Dock restart** (`killall Dock`, crash, macOS). If it does not write through to defaults, a restart silently reverts the edge until the poll catches it. UNKNOWN. | Medium | Medium | Small spike (TDD §8.5); if writes don't persist, mirror every successful CoreDock set into the defaults key (cheap, safe); add Dock-restart detection to the event model. | Open — spike required |
| R-006 | K | **Event gaps require limited polling.** Notifications may miss cases (unobserved causes, failed registrations); pure event-driven could leave drift standing. | Medium | Medium | Hybrid monitoring: events primary, 30 s poll as safety net (ADR-005); count poll-caught drift locally to tune the interval with evidence. | Open — ADR-005 accepted; 30 s default not yet shipped (v0.1 polls at 2 s) |
| R-009 | N | **MenuBarExtra memory ceiling.** SwiftUI `MenuBarExtra` apps commonly land at 25–50 MB, against the kickoff's < 30 MB preferred budget. | Medium | Medium | Measure at M6; treat < 50 MB as acceptable, < 30 MB as stretch (TDD §14, owner-visible budget change); fall back to an AppKit `NSStatusItem` shell only if measurement demands it. | Open — unmeasured |
| R-010 | K | **"DockKeeper" may conflict with an existing product name or trademark.** | Medium | Medium | Name and trademark review before first public release (release-checklist gate; TDD open question #10). | Open |

## Retired / closed risks

| ID | Lineage | Risk | Outcome |
|---|---|---|---|
| R-001 | K | **No supported API can reliably move the Dock** (was: High/Critical — the project's founding uncertainty). | **Retired 2026-07-22 for edge lock**: the feasibility spike CONFIRMED on-device that `CoreDock` sets the edge live and flicker-free, with `defaults`+`killall` as a public-path fallback. The *display* dimension of the risk lives on as R-002 (no direct API exists; main-display relocation is the accepted best-effort route, owner Decision 1). |
| R-007 | K | **App Sandbox blocks required behavior.** | **Materialized and accepted 2026-07-22**: the sandbox blocks both `killall` and private-API use (CONFIRMED policy), so Mac App Store distribution is off the table for v1. Mitigation applied as designed — Developer ID direct download + Homebrew cask (ADR-002). Revisit only if a supported mechanism appears. |
| R-008 | K | **Accessibility behavior changes between macOS releases.** | **Closed for v1 (not applicable)**: the chosen mechanisms require no Accessibility permission at all (TDD §10, CONFIRMED on-device). Reopens automatically if a follow-focused-window feature ships post-v1. |

## Review cadence

Re-review at each milestone boundary ([implementation plan](implementation-plan.md)) and at every macOS point release while R-004 is open. Additions require an ID, lineage, likelihood/impact, and a named mitigation; closures record the evidence (kickoff rule 15: record risks instead of silently assuming them away).
