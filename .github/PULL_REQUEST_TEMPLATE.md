## What

<!-- What changes and why. Link issues: "Closes #N" (fully resolves) / "Refs #N" (partial). -->

## Checklist

- [ ] `swift test` passes locally
- [ ] CI is green, including the no-networking-symbols gate
- [ ] Behavior changes are reflected in the matching `docs/` document (AGENTS rule 13) — or no behavior changed
- [ ] Consequential architecture decisions have an ADR in `docs/decision-log.md` (rule 14) — or none were made
- [ ] No new permissions, networking, telemetry, or private-API use (rules 7, 10, 18) — or a ratified ADR covers it
- [ ] User-visible changes have a line in `CHANGELOG.md` under *Unreleased*
