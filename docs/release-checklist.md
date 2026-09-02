# DockKeeper — Release Checklist

| | |
|---|---|
| **Status** | In use — v0.9.0 (2026-07-24), v0.9.1 (2026-07-28) and v0.9.2 (2026-08-18) all ran through it; the reordered §3–§5 is proven |
| **Date** | 2026-07-22 · last revised 2026-09-02 |
| **Owner** | blamechris |
| **Scope** | Every public release (v0.9.0 onward), Developer ID direct download + Homebrew cask per ADR-002 |
| **Inputs** | [Technical design](technical-design.md) §13, [decision log](decision-log.md), [risk register](risk-register.md), [test strategy](test-strategy.md) |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**.

Current tooling state (2026-07-23): the pipeline is **built and locally verified end-to-end** — `Scripts/build-app.sh` (icon + version stamping + `SIGNING_IDENTITY` env for Developer ID with hardened runtime, ad-hoc fallback), `Scripts/package-dmg.sh` (app + CLI + /Applications symlink, sha256 output, staple gate), `Scripts/notarize.sh` (notarytool submit/staple/validate for **both** the `.app` and the `.dmg`, graceful without credentials), `Scripts/gen-icon.swift` (regenerable `AppIcon.icns`), `.github/workflows/ci.yml` (build + tests + the DK-NFR-002 no-networking-symbols gate), `Casks/dockkeeper.rb` (template). Items marked ⚙️ still need the owner's one-time setup (Apple Developer account artifacts).

Update 2026-07-24 (targeting v1.0.0): §3–§5 were **reordered** so the `.app` is notarized and stapled *before* it is packaged — v0.9.0 stapled only the DMG, leaving cask-installed copies without a ticket of their own (§4). The scripts enforce the new order themselves; the sequence is build → notarize app → package → notarize DMG. **Exercised end-to-end 2026-07-28 in the v0.9.1 release — all of it now CONFIRMED.** `Scripts/release.sh 0.9.1` ran the four steps in order: app submission `cfb5b19a` (`DockKeeper-notarize.zip`) Accepted and stapled, `package-dmg.sh`'s staple gate and its post-package ticket re-check both passed, DMG submission `6635e783` Accepted and stapled. The shipped artifact was verified from inside the image: `xcrun stapler validate` on the mounted `.../DockKeeper.app` reported *"The validate action worked!"* — where the same check on v0.9.0 reported *"does not have a ticket stapled to it"*. The two-ticket model is no longer INFERRED anywhere.

## 1. Gates (before cutting anything)

- [ ] All unit + integration tests green (`swift test`).
- [ ] Manual hardware matrix executed for this release's macOS versions; results recorded ([test strategy §3](test-strategy.md)). First release: full matrix (M6); later releases: regression subset + new-macOS rows.
- [ ] Reliability suite run; DK-NFR-001 budgets met (idle CPU ~0%, memory, cold launch) or an owner-ratified budget change is logged.
- [ ] CoreDock smoke test on the newest macOS point release (R-004: symbols resolve, live set works, fallback still engages when forced).
- [ ] Screen-watcher smoke test on the newest macOS point release (R-004, ADR-011 / DK-FR-011): `CGSIsScreenWatcherPresent` resolves (else the toggle is disabled with a note); with the feature on, starting a real screen capture (QuickTime / Zoom / Screen Sharing.app) flips the flag and the Dock auto-hides, and stopping restores it — and a pre-existing user auto-hide is left untouched. This is the DK-FR-011 true-case, **UNKNOWN until run here** (do not claim CONFIRMED before this passes).
- [ ] Crash-recovery smoke test on the newest macOS point release (ADR-013 / DK-FR-013), three cells, all **UNKNOWN until run** ([test strategy §3c](test-strategy.md) has the full ten-row matrix):
  - [ ] **Kill mid-capture.** With the feature on, start a real capture so the Dock auto-hides, then `kill -9` the app and relaunch it: auto-hide is back **off**, `--diagnostics` reports no record held, and the menu shows the "restored your Dock" note.
  - [ ] **Kill mid-capture with the capture still running.** Same, but relaunch *while* the capture continues: the Dock does **not** flash — the repair adopts the existing hide and issues no Dock write — and stopping the capture restores auto-hide normally.
  - [ ] **Logout with a hide held.** Log out while the Dock is hidden for a capture, then log back in: auto-hide is off. This is the path ADR-013 refuses to depend on a termination hook for, and the only way to exercise it is a real logout.
- [ ] Bottom-Dock guard smoke test (ADR-015 / DK-FR-014), **UNKNOWN until run** ([test strategy §3d](test-strategy.md) has the full eight-row matrix). Needs a two-display rig with **both bottom edges free**. This gate exists because the same omission happened twice: PR #28 shipped DK-FR-012 with no §1 line, this checklist recorded that as an asymmetry to fix, and PR #60 then shipped DK-FR-014 the same way. The guard is the strongest candidate of any feature here for an on-device gate — it installs a system-wide event tap on mouse-move, it is Accessibility-gated, and its failure mode is a pointer that cannot reach the bottom of a screen.
  - [x] **A real hand cannot complete the summon** on the non-preferred display, and the Dock does not migrate. **PASSED 2026-09-02 with a control** — armed: no migration; released: migration ([session 3](hardware-matrix-results.md)). Re-run per macOS release.
  - [ ] **Fails open**: revoke Accessibility while armed, and force the system tap-disable — the pointer is released, never stuck.
  - [ ] **Refusals hold**: a stacked arrangement leaves that display unguarded (the pointer crosses normally), and mirrored displays stand the guard down.
  - **Owner decision for 0.9.3:** **row 1 run and passed** on 2026-09-02. The displays' native arrangement is stacked (the Dell flush above the laptop), which is the geometry the guard refuses, so the rig was temporarily rearranged side-by-side for the run — as the [spike](spikes/separate-spaces-pinning.md) did on 2026-08-27. Rows 3 and 6–8 remain unrun and are deferred: the feature is opt-in and off by default, and every one of them is a fail-*open* path, so an unrun cell cannot trap a cursor.
  - **Row 2 (cost) is deferred to the soak, deliberately.** Spot samples on a machine in use were incoherent and are recorded as such rather than quoted. **Do not attempt it with synthetic `CGEvent.post`** — that instrument reads ~25x high ([session 3](hardware-matrix-results.md)).
  - **This gate needs a real signing identity.** `build-app.sh` ad-hoc signs by default and rebuilds the bundle from scratch, so the Accessibility grant goes stale every build while System Settings still shows the row on — the tap then never arms and `--diagnostics` reports success anyway ([#77](https://github.com/blamechris/DockKeeper/issues/77)). Build with `SIGNING_IDENTITY` and confirm arming from the unified log, not from `--diagnostics`.
- [ ] Single-instance smoke test (ADR-012 / DK-FR-012), **UNKNOWN until run** ([test strategy §3b](test-strategy.md) has the full eleven-row matrix, tracked in [#30](https://github.com/blamechris/DockKeeper/issues/30)). PR #28 shipped the guard without adding a §1 line, so it was under-gated relative to DK-FR-013; recording it here fixes that asymmetry rather than leaving it implicit. Row 1 (fast user switching) **no longer gates the shipped guard** — the [ADR-012 amendment](decision-log.md#adr-012-single-instance-guard-in-process-at-appinit-lsmultipleinstancesprohibited-withheld) made per-uid scoping a unit-tested invariant instead of an inference — but it still gates the `LSMultipleInstancesProhibited` follow-on.
  - **Owner decision for 0.9.2:** §3b runs as a *post-install* gate — the DMG is cut and tagged as a pre-release first, and the Homebrew cask bump is held until it passes. A pre-release that nobody installs by default is the cheapest place to exercise a guard that only misbehaves across real launches.
  - **What actually happened at 0.9.2, recorded so the decision is re-made rather than re-assumed:** the cask was mirrored to the tap **7 minutes 27 seconds** after the release was published, and the first §3b result of any kind was posted to [#30](https://github.com/blamechris/DockKeeper/issues/30) 37 minutes *after* that. So the hold was not held — and it was not free, either. Row 1 **still gated the shipped guard when it lapsed**: PR #39 retired that gate the following day, ~21 hours after the tag, and its merge commit is not an ancestor of `v0.9.2`. So 0.9.2 went out to users under a gate nobody had run. What #39 then did — replacing the fast-user-switching inference with a unit-tested per-uid invariant — is why the exposure is retrospective rather than live, and why row 2 is now the only outstanding row that bears on the guard.
  - **Owner decision for 0.9.3:** no hold. Rows 1 and 2 need a second local account and a real logout, neither of which is available; the guard's per-uid scoping is unit-tested rather than inferred; and a hold nobody honours is worse than an honest deferral. #30 stays open.
- [ ] Docs current: behavior spec, TDD, risk register, decision log, README, CHANGELOG, PRIVACY/SECURITY, parity assessment and implementation plan all reflect shipped behavior (AGENTS rule 13). Naming the user-facing set is deliberate — the 0.9.3 audit found README and PRIVACY carrying false claims while the four originally-named documents were the ones being checked.
- [ ] Open `Error`/`Degraded`-class bugs triaged; none release-blocking.
- [x] **First-release gates all met:** name/trademark review ✅ (R-010 closed 2026-07-24 — no conflicting product or filing; see register) · ADR-003 ratification ✅ · privacy statement + issue templates ✅ · public repo + Sponsors/FUNDING verified ✅. Owner decision 2026-07-24: first public tag is a **v0.9.0 pre-release beta** (hardware matrix completes before v1.0.0).

## 2. Version & changelog

- [ ] Choose version; tag plan (`vX.Y.Z`).
- [ ] Root [`CHANGELOG.md`](../CHANGELOG.md) updated: move *Unreleased* into a new `[x.y.z]` section, dated (user-facing behavior, not commit list; Keep-a-Changelog format), **and the link-reference block at the foot of the file** — a new section with no `[x.y.z]:` definition renders as literal brackets, and `[Unreleased]` must be re-based on the new tag. GitHub release notes draw from it.
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

- [ ] Git tag pushed; GitHub release created with changelog, artifacts, checksums, and **marked as a pre-release** — every 0.9.x tag is a public beta ([CHANGELOG](../CHANGELOG.md) header), and all three shipped releases are flagged that way. The flag is not implied by the version string; set it explicitly (`gh release create --prerelease`).
- [ ] **Mirror `Casks/dockkeeper.rb` into `blamechris/homebrew-tap` and push it** — copy the **whole file**, not just the version and sha lines. The two copies must stay byte-identical, and a partial copy silently strands caveat or uninstall changes in a repo no reviewer reads again — 0.9.3 is the worked example, since it rewrites the `caveats` block that a version-and-sha-only copy would leave stale in the tap. The in-repo cask reaches nobody; the tap is what `brew install --cask blamechris/tap/dockkeeper` resolves. **Verify falsifiably:** `brew update && brew info --cask blamechris/tap/dockkeeper` must report the NEW version before the box below is ticked — against a stale tap, `brew install --cask` installs the *old* version and exits 0, so a green install proves nothing.
- [ ] Homebrew cask: fill version+sha in `Casks/dockkeeper.rb` (template ready); ⚙️ first release: host in a personal tap (`blamechris/homebrew-tap`) or submit to homebrew/cask; `brew install --cask` verified end-to-end including the CLI.
- [ ] README install instructions point at the new release.

## 8. Post-release

- [ ] Monitor GitHub issues for the first days; drift/oscillation reports get a diagnostics-file ask (once M1 file diagnostics ship).
- [ ] Update [risk register](risk-register.md) with anything the release taught (R-004 smoke result, notarization findings).
- [ ] File follow-ups for deferred items (Sparkle ADR, App Store re-evaluation only if mechanisms change).
