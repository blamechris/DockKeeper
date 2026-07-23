# DockKeeper — Release Checklist

| | |
|---|---|
| **Status** | Draft for review (no release has run through this yet) |
| **Date** | 2026-07-22 |
| **Owner** | blamechris |
| **Scope** | Every public release (v1.0 onward), Developer ID direct download + Homebrew cask per ADR-002 |
| **Inputs** | [Technical design](technical-design.md) §13, [decision log](decision-log.md), [risk register](risk-register.md), [test strategy](test-strategy.md) |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

Current tooling state (at 72fbcc2): `Scripts/build-app.sh` assembles and **ad-hoc**-signs `DockKeeper.app` with `LSUIElement` and entitlements — CONFIRMED. Developer ID signing, notarization, `.dmg` packaging, cask, and app icon do **not** exist yet (M7). Items marked ⚙️ need one-time setup before the first release.

## 1. Gates (before cutting anything)

- [ ] All unit + integration tests green (`swift test`).
- [ ] Manual hardware matrix executed for this release's macOS versions; results recorded ([test strategy §3](test-strategy.md)). First release: full matrix (M6); later releases: regression subset + new-macOS rows.
- [ ] Reliability suite run; DK-NFR-001 budgets met (idle CPU ~0%, memory, cold launch) or an owner-ratified budget change is logged.
- [ ] CoreDock smoke test on the newest macOS point release (R-004: symbols resolve, live set works, fallback still engages when forced).
- [ ] Docs current: behavior spec, TDD, risk register, decision log reflect shipped behavior (AGENTS rule 13).
- [ ] Open `Error`/`Degraded`-class bugs triaged; none release-blocking.
- [ ] **First release only:** name/trademark review done (R-010 — competitor family is DockLock Lite/Plus/Pro; see the risk register) · privacy statement + issue templates published (M7). ADR-003 owner ratification: ✅ recorded 2026-07-22.

## 2. Version & changelog

- [ ] Choose version; tag plan (`vX.Y.Z`).
- [ ] Changelog written (user-facing behavior, not commit list).
- [ ] README screenshots/instructions still accurate (incl. `swift run` vs packaged-app login-item caveat).

## 3. Build & sign

- [ ] Clean release build: `swift build -c release` for **both** products (`DockKeeper`, `dockkeeper-cli`).
- [ ] Assemble bundle: `Scripts/build-app.sh release`.
- [ ] ⚙️ Sign with **Developer ID Application** identity (replaces the script's ad-hoc `-`), hardened runtime enabled.
- [ ] Entitlements reviewed — no sandbox entitlement (would break `killall`/`dlsym` — ADR-002); nothing unexpected added.
- [ ] `codesign --verify --strict --verbose=2` passes on app and CLI.
- [ ] Universal binary confirmed if shipping Intel support (INFERRED unproblematic — verify first time, ADR-001).

## 4. Notarize & staple

- [ ] ⚙️ `notarytool` credentials configured (keychain profile).
- [ ] Submit app (and CLI artifact) for notarization; wait for `Accepted`. First run validates the TDD's INFERRED "no entitlement conflicts" claim — record the result in the decision log.
- [ ] `stapler staple` the app; `stapler validate` passes.
- [ ] Gatekeeper check on a clean machine/VM: `spctl --assess --type execute` passes; app launches from `~/Downloads` without warnings beyond the standard first-open dialog.

## 5. Package

- [ ] Produce `.dmg` (or `.zip`) containing `DockKeeper.app`; CLI delivered via the cask/`.zip` (⚙️ decide layout first release).
- [ ] Checksums (`shasum -a 256`) generated for release notes and cask.

## 6. Verify the artifact (fresh user pass, clean machine)

- [ ] Download → open → menu-bar item appears; no Dock icon (`LSUIElement` honored in the *shipped* plist).
- [ ] Edge lock works; forced fallback shows `Degraded` honestly.
- [ ] Launch at Login registers from the packaged app; `.requiresApproval` deep link works.
- [ ] `dockkeeper status` reports correctly; CLI and app share settings.
- [ ] **Zero network**: network monitor shows no connections during a full exercise of the app (DK-NFR-002); CI no-networking-symbols check green (PROPOSED gate).
- [ ] Logs contain no sensitive names (DK-PRIV-001 spot check).

## 7. Publish

- [ ] Git tag pushed; GitHub release created with changelog, artifacts, checksums.
- [ ] ⚙️ Homebrew cask created (first release) / version+sha bumped (later releases); `brew install --cask` verified end-to-end including the CLI symlink.
- [ ] README install instructions point at the new release.

## 8. Post-release

- [ ] Monitor GitHub issues for the first days; drift/oscillation reports get a diagnostics-file ask (once M1 file diagnostics ship).
- [ ] Update [risk register](risk-register.md) with anything the release taught (R-004 smoke result, notarization findings).
- [ ] File follow-ups for deferred items (Sparkle ADR, App Store re-evaluation only if mechanisms change).
