# DockKeeper skill profile

## Project Context
- Tech: Swift 6 (strict concurrency), SwiftUI `MenuBarExtra` accessory app (`LSUIElement`), macOS 14+. Products: `DockKeeper` (the .app), `dockkeeper-cli` (the `dockkeeper` CLI), `DockKeeperCore` (shared library, the only thing the test target links).
- Build system: SwiftPM (`Package.swift`). There is no Xcode project — the `.app` bundle is assembled by `Scripts/build-app.sh`, not by Xcode. This is why App Intents metadata extraction does not run (documented gap, v1.1).
- Repo: blamechris/DockKeeper (public)
- Main branch: main
- CI: `.github/workflows/ci.yml`, job `build-test` on `macos-15` — `swift build -c release`, `swift test`, ad-hoc bundle assembly, and the **no-networking-symbols gate** (`nm -u` must not hit `NSURLSession|CFNetwork|NWConnection|NWListener|CFSocket`). No branch protection; no required checks configured.
- Status: v0.9.0 public beta shipped 2026-07-24. Next milestone v1.0.0 (M6 hardware matrix outstanding).
- Hard requirements (never regress): the 20 rules in [AGENTS.md](../AGENTS.md), quoted verbatim from the kickoff package. The ones that bite most often: **no network, telemetry, or analytics of any kind** (DK-NFR-002, enforced in CI); **no App Sandbox entitlement** (breaks `killall` and `dlsym` — ADR-002); public macOS APIs only unless an ADR approves otherwise (the sole approved deviation is CoreDock, ADR-003); every claim carries an evidence label — **CONFIRMED / INFERRED / PROPOSED / UNKNOWN** — and unverified things stay UNKNOWN rather than being upgraded by optimism; update `docs/` when behavior changes (rule 13); add an ADR for consequential architecture (rule 14); no payment gates or donation prompts (rule 11); **zero attribution** in commits, PRs, issues, and docs.

## Build / Test Commands
- Build (the gate): `swift build -c release`
- Test: `swift test`
- Lint/typecheck: no separate linter — the Swift 6 compiler under strict concurrency is the gate. Shell scripts in `Scripts/` are checked with `bash -n`.
- Packaging (release only, needs the Developer ID): `Scripts/build-app.sh` → `Scripts/notarize.sh dist/DockKeeper.app` → `Scripts/package-dmg.sh` → `Scripts/notarize.sh dist/DockKeeper-<v>.dmg`. Order is load-bearing; see [release-checklist](../docs/release-checklist.md) §3–§5.

## Conventions
- Branch prefix / naming: `claude/<slug>` for agent sessions; worktrees live under `.claude/worktrees/<name>`.
- Commit style + scopes: plain imperative subject, **not** conventional commits. An optional area prefix with a colon is common (`Cask: drop deprecated depends_on comparison`). Body explains the why and cites evidence labels where a claim is made. No attribution footer of any kind.
- Source file patterns: `Sources/**/*.swift`, `Tests/DockKeeperTests/*.swift`, `Scripts/*.sh`, `docs/*.md`, `Casks/dockkeeper.rb`, `Resources/Info.plist`, `Resources/DockKeeper.entitlements`.
- Docs are part of the change, not follow-up: behavior spec, technical design, decision log, risk register, release checklist all live in `docs/` and rule 13 makes updating them mandatory when behavior moves.

## Skill Targets
targets: claude, gemini, codex

## agent-review Customizations
- **Persona:** a macOS systems engineer who ships signed, notarized menu-bar utilities — fluent in Swift 6 concurrency, SwiftPM packaging, codesign/notarization, and the private-vs-public API line. Skeptical of unverified claims: the repo's evidence labels are a review criterion, not decoration.
- **Code quality criteria:** Swift 6 strict-concurrency correctness (actor isolation, `@MainActor` boundaries, no unstructured `Task` leaks); private-API use confined to the CoreDock adapter behind `dlsym` with a working public fallback and an honest `Degraded` state; no polling added without evidence that event-driven monitoring is insufficient (rule 19); no force-unwraps on system-provided optionals.
- **Architecture criteria:** system interactions stay behind protocols/adapters (rule 8) so the test target can link `DockKeeperCore` alone; no new private-API surface without an ADR (rule 7/14); nothing that would require the sandbox or Accessibility permission without an ADR and a user-facing explanation (rule 18); no networking symbols anywhere (DK-NFR-002 — CI fails the build, but catch it in review first).
- **Test criteria:** pure logic (parse tables, matchers, state machines) belongs in `DockKeeperCore` with unit tests; anything touching the live Dock is manual-matrix territory and must be labeled UNKNOWN until run on hardware, never asserted as CONFIRMED from a passing unit test.
- **Labels:** only the default GitHub set exists (`bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`). There is no custom taxonomy — use `bug` / `enhancement` / `documentation` and do not invent label families.
- **Evidence discipline:** flag any doc or comment that upgrades an INFERRED claim to CONFIRMED without a recorded verification. This repo has been bitten by exactly that (see the App Intents metadata and hardware-matrix entries).

## check-pr Customizations
- **Labels:** as above — default GitHub set only.
- CI is `build-test` on `macos-15`; there are no required checks and no branch protection, so "conversations resolved" is not enforced by the platform. Resolve threads anyway — the skill's GraphQL step is the only thing that closes them.
- Packaging scripts cannot be verified in CI beyond the ad-hoc path; a fix touching `Scripts/*.sh` should at minimum pass `bash -n` and an ad-hoc `build-app.sh` + `package-dmg.sh` run locally.

## create-issue Customizations
- **Labels:** default GitHub set only (`bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`). No complexity or priority scheme exists — do not add one.
- Traceability: link the requirement ID where one applies (`DK-FR-0NN`, `DK-NFR-0NN`, `DK-PRIV-001`) and the risk register entry (`R-0NN`) rather than inventing new identifiers.

## release Customizations
- The release process is [docs/release-checklist.md](../docs/release-checklist.md) — it is authoritative and supersedes any generic release steps. Sections 1–8, gates first.
- **Footgun (cost the project a broken `brew install` on v0.9.0):** stapling rewrites the DMG. The cask/release-notes sha256 must come from `Scripts/notarize.sh`'s final line, never from `package-dmg.sh`'s.
- **Footgun:** the `.app` must be notarized and stapled *before* `package-dmg.sh` runs, or cask-installed copies carry no ticket. `package-dmg.sh` enforces this; `ALLOW_UNSTAPLED_APP=1` exists for test builds only and must never be used for a shipped artifact.
- Notarization needs the `dockkeeper-notary` keychain profile and the Developer ID; both are owner-local, so a release cannot run unattended or in CI.
- Version is stamped via `VERSION=x.y.z Scripts/build-app.sh` into `CFBundleShortVersionString`/`CFBundleVersion`; `Casks/dockkeeper.rb` carries version + sha separately and must be updated in the same change.

## changelog Customizations
- User-facing behavior, not a commit list (release checklist §2). Anchor entries to requirement IDs (`DK-FR-0NN`) where one applies.

## fix-ci Customizations
- The only workflow is `.github/workflows/ci.yml` (job `build-test`, `macos-15`). Failures are almost always one of: a Swift 6 strict-concurrency error, a test failure, or the **no-networking-symbols gate** tripping because a dependency or new API pulled in a networking symbol. The last one is a real DK-NFR-002 violation — never silence the gate to make CI green.

## catchup Customizations
- The durable state of this project lives in `docs/` — [implementation-plan](../docs/implementation-plan.md) (milestones), [decision-log](../docs/decision-log.md) (ADRs), [risk-register](../docs/risk-register.md) (open risks with owners), [release-checklist](../docs/release-checklist.md). Read those before git log; they are maintained deliberately and carry the *why*.
