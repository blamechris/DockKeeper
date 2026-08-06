# Contributing to DockKeeper

Thanks for wanting to help. This is a small, documentation-driven repo: the docs under [`docs/`](docs/) are the contract, and [AGENTS.md](AGENTS.md) lists the twenty rules that bind every contributor — human or agent. Read those before anything else; the rest of this file is mechanics.

## Build and test

macOS 14+ with a Swift 6 toolchain (Xcode 26 / Swift 6.3):

```sh
swift build                      # build everything
swift test                       # run the test suite
swift run DockKeeper             # run the menu-bar app
swift run dockkeeper-cli status  # run the CLI
Scripts/build-app.sh             # assemble dist/DockKeeper.app (ad-hoc signed)
```

## Pull requests

- Branch from `main`, open the PR against `main`, and use the PR template.
- **CI must pass** — build, tests, and the no-networking-symbols gate ([ci.yml](.github/workflows/ci.yml)). Anything that introduces a networking symbol, raw socket syscall, or networking framework fails the build by design.
- Write tests before or with the behavior they cover (AGENTS rule 9).
- Behavior changes update the matching doc under `docs/` (rule 13); consequential architecture changes get an ADR in [docs/decision-log.md](docs/decision-log.md) (rule 14).
- Use the evidence labels — **CONFIRMED / INFERRED / PROPOSED / UNKNOWN** — in docs and design discussion (rules 5–6).
- User-visible changes get a line in [CHANGELOG.md](CHANGELOG.md) under *Unreleased*.
- Commit subjects: short, imperative, capitalized, specific (`git log --oneline` shows the house style).

## Off the table

Some contributions can't be accepted regardless of quality, per [AGENTS.md](AGENTS.md): network services or telemetry (rule 10), payment gates or donation prompts (rule 11), new private-API use without a ratified ADR (rule 7), and new required permissions (project posture — see [PRIVACY.md](PRIVACY.md); rule 18 additionally requires any Accessibility use to be explained).

## Not sure?

Open an issue first — the issue templates cover bugs and feature requests. For security problems, use [SECURITY.md](SECURITY.md) instead of a public issue.
