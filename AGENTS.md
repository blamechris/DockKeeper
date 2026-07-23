# DockKeeper Agent Rules

Source: DockKeeper Agent Kickoff Package §14, quoted verbatim (CONFIRMED — recovered from the kickoff session record, 2026-07-22). These rules bind any agent (or human) working in this repository.

1. Read docs/product-scope.md before making product decisions.
2. Read docs/technical-design.md before changing architecture.
3. Do not copy proprietary source code, assets, branding, or product text.
4. Do not decompile or bypass another application's licensing.
5. Distinguish CONFIRMED, INFERRED, PROPOSED, and UNKNOWN claims.
6. Cite evidence for product and API claims.
7. Use public macOS APIs unless an ADR explicitly approves otherwise.
8. Keep system interactions behind protocols or adapters.
9. Write tests before production behavior when practical.
10. Do not use network services, telemetry, or analytics.
11. Do not add payment gates, subscriptions, or automatic donation prompts.
12. Do not perform broad refactors unrelated to the current milestone.
13. Update requirements and design documents when behavior changes.
14. Add an ADR for consequential architectural decisions.
15. Record important unresolved risks instead of silently assuming them away.
16. Keep experimental code under spikes/ until approved for production use.
17. Do not claim feature parity without an evidence-backed comparison.
18. Never require Accessibility permission without explaining its purpose.
19. Avoid continuous polling unless evidence shows event-driven monitoring is
    insufficient.
20. Optimize for reliability and predictability before adding power features.

## Repository notes (state as of 2026-07-22)

- **Rule 1:** `docs/product-scope.md` is not yet committed (the kickoff package itself is the interim scope source). Until it lands, treat [docs/technical-design.md](docs/technical-design.md) §2 (Goals/Non-Goals) as the scope boundary.
- **Rule 7:** the one approved deviation is the private `CoreDock` edge-lock path — ADR-003 in [docs/decision-log.md](docs/decision-log.md), **ratified by the owner 2026-07-22**. Do not add further private-API use without a new ADR.
- **Rule 16:** spikes currently live under `Documentation/spikes/` (to be consolidated into `docs/`-adjacent `spikes/` later — TDD Appendix A.1).
- **Rule 5/6:** the evidence labels and their definitions are stated at the top of every doc in `docs/`; use them in commit-facing docs and design discussion alike.
- The full doc suite: [behavior-specification](docs/behavior-specification.md) · [technical-design](docs/technical-design.md) · [test-strategy](docs/test-strategy.md) · [implementation-plan](docs/implementation-plan.md) · [risk-register](docs/risk-register.md) · [decision-log](docs/decision-log.md) · [release-checklist](docs/release-checklist.md).
