# DockKeeper — Release Checklist

| | |
|---|---|
| **Status** | In use — v0.9.0 ran through it (2026-07-24); §3–§5 reordered for v1.0.0 |
| **Date** | 2026-07-22 · last revised 2026-07-25 |
| **Owner** | blamechris |
| **Scope** | Every public release (v0.9.0 onward), Developer ID direct download + Homebrew cask per ADR-002 |
| **Inputs** | [Technical design](technical-design.md) §13, [decision log](decision-log.md), [risk register](risk-register.md), [test strategy](test-strategy.md) |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

Current tooling state (2026-07-23): the pipeline is **built and locally verified end-to-end** — `Scripts/build-app.sh` (icon + version stamping + `SIGNING_IDENTITY` env for Developer ID with hardened runtime, ad-hoc fallback), `Scripts/package-dmg.sh` (app + CLI + /Applications symlink, sha256 output, staple gate), `Scripts/notarize.sh` (notarytool submit/staple/validate for **both** the `.app` and the `.dmg`, graceful without credentials), `Scripts/gen-icon.swift` (regenerable `AppIcon.icns`), `.github/workflows/ci.yml` (build + tests + the DK-NFR-002 no-networking-symbols gate), `Casks/dockkeeper.rb` (template). Items marked ⚙️ still need the owner's one-time setup (Apple Developer account artifacts).

Update 2026-07-24 (targeting v1.0.0): §3–§5 were **reordered** so the `.app` is notarized and stapled *before* it is packaged — v0.9.0 stapled only the DMG, leaving cask-installed copies without a ticket of their own (§4). The scripts enforce the new order themselves; the sequence is build → notarize app → package → notarize DMG. Not yet exercised end-to-end against the notary service — the local gates are CONFIRMED (a real-Developer-ID-signed, unstapled app is refused by `package-dmg.sh`), the submission halves are INFERRED until the first v1.0.0 run.

## 1. Gates (before cutting anything)

- [ ] All unit + integration tests green (`swift test`).
- [ ] Manual hardware matrix executed for this release's macOS versions; results recorded ([test strategy §3](test-strategy.md)). First release: full matrix (M6); later releases: regression subset + new-macOS rows.
- [ ] Reliability suite run; DK-NFR-001 budgets met (idle CPU ~0%, memory, cold launch) or an owner-ratified budget change is logged.
- [ ] CoreDock smoke test on the newest macOS point release (R-004: symbols resolve, live set works, fallback still engages when forced).
- [ ] Screen-watcher smoke test on the newest macOS point release (R-004, ADR-011 / DK-FR-011): `CGSIsScreenWatcherPresent` resolves (else the toggle is disabled with a note); with the feature on, starting a real screen capture (QuickTime / Zoom / Screen Sharing.app) flips the flag and the Dock auto-hides, and stopping restores it — and a pre-existing user auto-hide is left untouched. This is the DK-FR-011 true-case, **UNKNOWN until run here** (do not claim CONFIRMED before this passes).
- [ ] Docs current: behavior spec, TDD, risk register, decision log reflect shipped behavior (AGENTS rule 13).
- [ ] Open `Error`/`Degraded`-class bugs triaged; none release-blocking.
- [x] **First-release gates all met:** name/trademark review ✅ (R-010 closed 2026-07-24 — no conflicting product or filing; see register) · ADR-003 ratification ✅ · privacy statement + issue templates ✅ · public repo + Sponsors/FUNDING verified ✅. Owner decision 2026-07-24: first public tag is a **v0.9.0 pre-release beta** (hardware matrix completes before v1.0.0).

## 2. Version & changelog

- [ ] Choose version; tag plan (`vX.Y.Z`).
- [ ] Changelog written (user-facing behavior, not commit list).
- [ ] README screenshots/instructions still accurate (incl. `swift run` vs packaged-app login-item caveat).

## 3. Build & sign

> **The four scripted steps of §3–§5 are one command:**
> `SIGNING_IDENTITY="Developer ID Application: …" Scripts/release.sh x.y.z`
>
> It runs build → notarize app → package → notarize DMG in order, asserts each
> step's postcondition before continuing, refuses to start if
> `ALLOW_UNSTAPLED_APP` is set or the identity is ad-hoc/absent, never re-enters
> `build-app.sh` after the app is stapled, and ends with the stapled DMG's
> sha256 — the cask value.
>
> **It does not cover the human boxes.** Still yours: the clean build, the
> entitlements review, `codesign --verify --verbose=2` on app and CLI, the
> universal-binary check, and §5's Gatekeeper pass on a clean machine. The
> driver removes the *ordering* hazards, not the checklist.

- [ ] Clean release build: `swift build -c release` for **both** products (`DockKeeper`, `dockkeeper-cli`).
- [ ] Assemble bundle: `VERSION=x.y.z SIGNING_IDENTITY="Developer ID Application: …" Scripts/build-app.sh release` (hardened runtime applied automatically with a real identity). Export `SIGNING_IDENTITY` for the whole §3–§5 sequence — `package-dmg.sh` signs the CLI with it too.
- [ ] Nothing may modify the bundle after §4 staples it: stamp the version here, sign here, then leave it alone.
- [x] Developer ID Application certificate present ✅ (2026-07-23 — "Christopher Pishaki", team `PG8VP4PTGV`, already in the keychain from the owner's other apps; signed build verified: hardened-runtime flag set, Designated Requirement satisfied, signed DMG cut).
- [ ] App Intents metadata (`Metadata.appintents`) — **attempted 2026-07-24 and root-caused**: the `ExtractAppIntentsMetadata` phase runs only for Xcode *app targets*; neither `swift build` nor `xcodebuild` against an SPM *executable product* triggers it (CONFIRMED — clean xcodebuild produced no metadata and logged no extraction step). Proper fix (v1.1): a minimal Xcode app-target shell embedding the package. Until then Shortcuts discovery is not guaranteed; the `dockkeeper://` URL scheme is the working automation path (noted in release notes).
- [ ] Entitlements reviewed — no sandbox entitlement (would break `killall`/`dlsym` — ADR-002); nothing unexpected added.
- [ ] `codesign --verify --strict --verbose=2` passes on app and CLI.
- [ ] Universal binary confirmed if shipping Intel support (INFERRED unproblematic — verify first time, ADR-001).

## 4. Notarize & staple the app (before it is packaged)

**Two tickets, in this order** (restructured for v1.0.0 — v0.9.0 shipped with only the DMG stapled). `brew install --cask` copies `DockKeeper.app` out of the image into `/Applications`, and the DMG's ticket does not travel with the copy. An app with no ticket of its own has to reach Apple's Gatekeeper service on first launch — slow online, blocked offline. CONFIRMED on the shipped v0.9.0 artifact: `xcrun stapler validate` on the mounted `.../DockKeeper.app` reported *"does not have a ticket stapled to it"*, while the DMG itself validated. So the app is notarized and stapled first, and the DMG is built from the already-stapled bundle.

- [x] `notarytool` credentials configured ✅ (2026-07-23, profile `dockkeeper-notary`; required accepting an updated Apple Developer agreement first — 403 until it propagated).
- [ ] `Scripts/notarize.sh dist/DockKeeper.app` — zips the bundle with `ditto` (notarytool takes no bare bundle), submits, waits, then staples **the bundle** and validates. Fails fast with the notary log on rejection, and refuses an ad-hoc-signed app up front.
- [ ] `xcrun stapler validate dist/DockKeeper.app` passes before packaging.
- [ ] Do not re-run `Scripts/build-app.sh` after this point — it rebuilds the bundle from scratch and the ticket goes with it (re-notarize if you do).

## 5. Package, then notarize & staple the DMG

- [ ] `Scripts/package-dmg.sh` — produces `dist/DockKeeper-<version>.dmg` (app + `dockkeeper` CLI + /Applications symlink; layout decided 2026-07-23). With a real `SIGNING_IDENTITY` it refuses to package an app that carries no ticket, copies the bundle with `ditto`, and re-mounts the finished image to confirm the ticket survived (`ALLOW_UNSTAPLED_APP=1` overrides, test builds only).
- [ ] `Scripts/notarize.sh dist/DockKeeper-<version>.dmg` — the image needs its own ticket too, or the download is blocked before the app is ever copied out. **Pipeline validated 2026-07-23**: submission `b981d4de` Accepted, stapled, and the mounted app assessed `Notarized Developer ID` — the TDD's "no entitlement conflicts" claim is CONFIRMED (first attempt `eb36ef6c` was Invalid solely for the then-unsigned CLI; fixed in `package-dmg.sh`).
- [ ] **Take the cask/release-notes sha256 from `Scripts/notarize.sh`'s final line, not `package-dmg.sh`'s** — stapling rewrites the DMG. v0.9.0 shipped the pre-staple hash and `brew install --cask` failed with a checksum mismatch until it was corrected (2026-07-24). Unchanged by the §4 reorder: only the *DMG* staple happens after the hash is first printed, and it still rewrites the file.
- [ ] Gatekeeper check on a clean machine/VM: `spctl --assess --type execute` passes; app launches from `~/Downloads` without warnings beyond the standard first-open dialog.
- [ ] Known limitation (INFERRED, accepted): the `dockkeeper` CLI is signed and notarized as part of the DMG submission but **cannot be stapled** — a bare Mach-O executable has nowhere to store a ticket. Only the `.app` and the `.dmg` carry tickets.

## 6. Verify the artifact (fresh user pass, clean machine)

- [ ] Download → open → menu-bar item appears; no Dock icon (`LSUIElement` honored in the *shipped* plist).
- [ ] Ticket survived the install: after `brew install --cask` (or a drag to /Applications), `xcrun stapler validate /Applications/DockKeeper.app` passes — this is the v0.9.0 regression (§4).
- [ ] **Offline first launch**: with networking off on a clean machine, the installed app opens without a Gatekeeper stall or refusal. Fails if the app lost its ticket anywhere in §3–§5.
- [ ] Edge lock works; forced fallback shows `Degraded` honestly.
- [ ] Launch at Login registers from the packaged app; `.requiresApproval` deep link works.
- [ ] `dockkeeper status` reports correctly. **Verify sharing by divergence, not agreement**: set a lock edge in the app, confirm the CLI reports *that* edge, then `dockkeeper unlock` and confirm the running app goes disabled. Matching output alone proves nothing — v0.9.0's CLI read its own domain and still printed a plausible answer, because both sides happened to fall back to the same registration default.
- [ ] **Zero network**: network monitor shows no connections during a full exercise of the app (DK-NFR-002); CI no-networking-symbols check green (PROPOSED gate).
- [ ] Logs contain no sensitive names (DK-PRIV-001 spot check).

## 7. Publish

- [ ] Git tag pushed; GitHub release created with changelog, artifacts, checksums.
- [ ] Homebrew cask: fill version+sha in `Casks/dockkeeper.rb` (template ready); ⚙️ first release: host in a personal tap (`blamechris/homebrew-tap`) or submit to homebrew/cask; `brew install --cask` verified end-to-end including the CLI.
- [ ] README install instructions point at the new release.

## 8. Post-release

- [ ] Monitor GitHub issues for the first days; drift/oscillation reports get a diagnostics-file ask (once M1 file diagnostics ship).
- [ ] Update [risk register](risk-register.md) with anything the release taught (R-004 smoke result, notarization findings).
- [ ] File follow-ups for deferred items (Sparkle ADR, App Store re-evaluation only if mechanisms change).
