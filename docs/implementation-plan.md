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
| ~~CoreDock-persistence spike~~ ✅ Done 2026-07-22 — write-through to defaults CONFIRMED ([findings](spikes/coredock-defaults-persistence.md)); restarts are benign, no mirroring needed, R-011 closed | #3 | R-011 |
| Event-burst instrumentation session (real burst profile → debounce width) | #4 | R-005 |
| Mirroring/clamshell behavior notes | #6 | R-002 |

**Acceptance.** Each spike has a Findings write-up in `docs/spikes/` with evidence labels and a recommendation. **Dependencies.** #2/#6 need the M6 rig; #3/#4 run on the single-display dev machine now.

## M1 — Application shell ✅ (2026-07-23)

Menu bar, Preferences, login item, os_log, ad-hoc-signed `.app` packaging (72fbcc2), plus the final items:

- ✅ Opt-in bounded file diagnostics (`FileDiagnostics`: ~1 MB size-rotate with one predecessor, 7-day prune, high-signal state/pin trail) + "Reveal Diagnostics File" in a new Advanced preferences tab; `diagnosticsFileEnabled` key, off by default.
- ✅ State-distinct menu-bar icons (`RecoveryState.menuSymbolName`: dashed=disabled, warning=degraded/error, pause reserved — open question #8 resolved).
- ✅ Dead `showMenuBarIcon` setting deleted (a menu-bar-only app without its icon would be unreachable).
- ✅ `settingsVersion` key registered (currently 1).

**Acceptance met:** rotation cap and opt-in-off verified by unit test (`FileDiagnosticsTests`); icon mapping pinned by test; 65 tests passing. Long-run log-growth measurement remains in the M6 reliability suite (R-009).

## M2 — Display registry ✅ (2026-07-23)

- ✅ `DisplayFingerprint` (Codable) + `FingerprintMatcher` scored matching with the unique-max ≥ 70 acceptance rule.
- ✅ Stale-preference repair (`DisplayIdentityResolver` returns a refreshed fingerprint on fallback-evidence matches; `Settings.repairPreferredDisplay` persists it).
- ✅ Migration: legacy `preferredDisplayUUID` → fingerprint (write-once); legacy key mirrored until v1.1 for rollback; `"cg-<id>"` pseudo-UUIDs discarded, never persisted.
- ✅ Real display names via `NSScreen.localizedName` (menu + fingerprint evidence).
- ✅ Ambiguity surfaced: `PinOutcome.ambiguousIdentity` — "pick your preferred display again", never guess.

**Acceptance met:** score table, tie→ambiguous, repair, migration, and mirror-key behavior all unit-tested ([DisplayIdentityTests.swift](../Tests/DockKeeperTests/DisplayIdentityTests.swift); 61 tests total passing). Score thresholds remain PROPOSED pending M6 hardware tuning.

## M3 — Dock observation ✅ (2026-07-22)

- ✅ `DockMonitor` emits typed `DockEvent` values only; all decisions moved to the coordinator.
- ✅ Debounce + generation-counter coalescing (in `RecoveryCoordinator`, TDD §8.3).
- ✅ External `UserDefaults` observation via KVO (cross-process; CLI edits reflect live — DK-FR-007-S3).
- ✅ `stop()` observer removal fixed (per-center lists); unused `DistributedNotificationCenter` dropped (A.4).
- ~~Dock-restart detection~~ **Dropped**: spike #3 proved restarts benign (CoreDock writes through to defaults); the poll covers the residual gap.

**Acceptance met:** synthetic burst → exactly one reconcile (S2 test green in `RecoveryTests.swift`).

## M4 — Dock restoration (the recovery engine) ✅ code complete (2026-07-22)

- ✅ `RecoveryCoordinator` + pure `RecoveryMachine` core: retry ladder (0/+1.5/+4 s), cooldown budget (6/60 s → `Error`), echo suppression, generation coalescing, single-owner state machine per TDD §5.1/§8.3.
- ✅ `DockAdapter` protocol seam (`CoreDockAdapter`/`DefaultsDockAdapter`); `DockController` refactored onto it with `isDegraded` reporting.
- ✅ Explicit `dlopen` of the ApplicationServices umbrella in `CoreDock` (spike-validated hardening; CLI verified on-device).
- ✅ Poll default 30 s + poll-caught-drift counter (ADR-005); `autoRecover` removed (ADR-007).
- ~~Mirror CoreDock sets into defaults~~ **Not needed**: spike #3 confirmed CoreDock writes through (R-011 closed).

**Acceptance:** all DK-FR-003 scenarios S1–S5 unit-green (`RecoveryTests.swift`, 26 new tests; 39 total passing). The 100-restore no-oscillation run belongs to the reliability suite → verified at **M6**. Legacy restore path deleted in the same change (the coordinator is the only reconciler).

## M5 — Permission & onboarding ✅ (by elimination)

No privacy-gated permission exists in v1 (TDD §10 — CONFIRMED); Login Items approval UX is built. No work. Reopens only if follow-window ships (post-v1).

## M6 — Reliability (hardware validation) ❌ — **gate for v1.0**

- Acquire/borrow a 2-monitor rig; execute the full [manual matrix](test-strategy.md#3-manual-system-tests-hardware-matrix).
- **Verify the INFERRED core claim: main-display relocation moves the Dock** (R-002 — top risk; if false, DK-FR-002 copy narrows, architecture stands per Decision 3).
- Measure DK-NFR-001 budgets (24 h idle CPU, memory, cold launch); tune fingerprint thresholds and debounce width with real data.
- Run reliability suite (sleep/wake cycles, replug storms, long-run).

**Acceptance.** Matrix results recorded per cell; budgets met or owner-ratified adjustments logged as ADR amendments; risk register updated with evidence. **Dependencies.** M2–M4 complete; rig available (schedule risk).

## M7 — Release ✅ **v0.9.1 public beta shipped 2026-07-28**

Tag `v0.9.0` (pre-release): notarized, stapled DMG (Gatekeeper `Notarized Developer ID`) on [GitHub Releases](https://github.com/blamechris/DockKeeper/releases/tag/v0.9.0); `brew install --cask blamechris/tap/dockkeeper` live — the tap resolved, but the cask carried the **pre-staple** sha256 and every install failed on a checksum mismatch until it was corrected 2026-07-24 (resolving ≠ installing; §7 now requires a real `brew install` before the tap is called done). A second install-path defect surfaced the same day: v0.9.0 stapled only the DMG, so the app a cask install copies into `/Applications` carries **no ticket of its own** (CONFIRMED — `stapler validate` on the mounted app: *"does not have a ticket stapled to it"*). Fine for online users, a stall or refusal offline; the pipeline is reordered for v1.0.0 to staple the app before packaging ([checklist](release-checklist.md) §4). R-010 trademark reviewed and cleared. **v0.9.1 (2026-07-28)** shipped the reordered pipeline: the app is notarized and stapled before packaging, so a cask-installed copy carries its own ticket and first launch no longer needs a network round-trip to Apple. Submissions `cfb5b19a` (app zip) and `6635e783` (DMG) both Accepted; the shipped artifact validates from inside the image. Also in it: the shared settings domain, honest privacy claims, the real network gate, and `Scripts/release.sh`, which drove the whole release in one invocation on its first real use. v1.0.0 follows once M6's hardware matrix and soak complete. Remaining v1.1 packaging item: App Intents metadata (needs an Xcode app-target shell — root-caused; URL scheme works today).

### Pipeline state (for the record) — completed 2026-07-23, reshaped 2026-07-24

Done 2026-07-23: privacy statement, issue templates, public repo + Sponsors live, **and the full release pipeline, locally verified end-to-end**: app icon (`Scripts/gen-icon.swift` → `AppIcon.icns`, wired into the bundle), `build-app.sh` with `SIGNING_IDENTITY`/`VERSION` + hardened runtime, `package-dmg.sh` (app + CLI + symlink, sha256), `notarize.sh` (notarytool wrapper), CI (`.github/workflows/ci.yml`: build, tests, DK-NFR-002 no-networking-symbols gate), cask template (`Casks/dockkeeper.rb`).

Reshaped for v1.0.0 (2026-07-24): `notarize.sh` now takes **either** artifact — a `.app` is zipped with `ditto` for submission and the ticket is stapled onto the bundle, a `.dmg` behaves as before and prints the post-staple sha256 last — and refuses an ad-hoc-signed *app* up front (the guard sits in the `.app` branch; a `.dmg` is not signature-checked). `package-dmg.sh` gained the staple gate and a post-package ticket re-check, both active only with a real `SIGNING_IDENTITY`. See the two-ticket note in [technical design §13](technical-design.md).

Remaining (owner-gated ⚙️): Developer ID certificate + notarytool credentials (Apple Developer account) · App Intents metadata packaging (tool present; wire via an `xcodebuild`-driven release build — Shortcuts discovery until then via the URL scheme) · R-010 trademark call. **Dependencies.** M6 green before the first tag.

## M8 — Separate-Spaces pinning (parity workstream, targets v1.1) 🟡 spike phase

Owner-directed 2026-07-23 (ADR-008): full DockLock replacement requires pinning in the macOS-default separate-Spaces mode.

- ✅ **Spike core question resolved same day** ([separate-spaces-pinning](spikes/separate-spaces-pinning.md)): detection via public visibleFrame insets CONFIRMED; the mode is edge-asymmetric — left/right Docks follow the main display (CONFIRMED both directions), bottom Docks don't.
- ✅ **ADR-009 shipped 2026-07-23**: left/right pinning works in separate-Spaces mode through the existing `MainDisplayPinner` (a `dockEdge` gate in `decide`); bottom declines with two-remedy guidance copy. Zero new mechanisms, zero permissions, no menu-bar cost in this mode.
- 🟡 **Remaining research track**: bottom-Dock-with-separate-Spaces (DockLock's niche). Candidates queued in the spike (pointer summon, AX, killall-relocation), deprioritized; would need its own ADR and possibly opt-in Accessibility.
- ⏳ **Hardware validation**: matrix cells for left/right pinning in this mode under wake/replug (with the standard recovery machinery); the reliability bar (Decision 3) governs.

**Acceptance.** Left/right pinning survives the matrix in separate-Spaces mode without oscillation (no drift source exists — the pointer can't summon left/right Docks, CONFIRMED); bottom remains an honest decline until a mechanism earns its ADR.

## M9 — Window restore across a pin (opt-in comfort feature, ADR-010) ✅ code complete (2026-07-23)

The former "top post-v1 candidate" (TDD open question #11) is shipped as an opt-in toggle. The main-display re-base can shuffle windows to the other screen (owner-observed); this moves them back.

- ✅ `Settings.preserveWindowLayout` (Bool, default **false**, registered) — the zero-permission default is untouched.
- ✅ `WindowLayoutPreserver` (@MainActor): `CGWindowList` snapshot of layer-0 windows (owner-PID + global bounds; **no titles/names** — §12), max-overlap display assignment, and AX restore (`kAXPositionAttribute`) gated on `AXIsProcessTrusted()`. Pure decision core (assignment/delta/plan/tolerance) split from the `CGWindowList`/AX side effects.
- ✅ `RecoveryCoordinator` wiring: the production `applyPin` closure snapshots pre-pin, pins, and restores post-pin only on `.pinned` — inside the closure, coordinator core logic and tests untouched.
- ✅ Advanced-tab toggle with contextual caption, explain-then-prompt-once on enable (never from the core), a "waiting for permission" note + deep link to the Accessibility pane, and `accessibilityGranted` refreshed on toggle and app reactivation.
- ✅ ADR-010 recorded; §10 permissions table + open question #11 + DK-FR-002 updated.

**Acceptance met (unit level):** max-overlap assignment (incl. straddle), rig-geometry delta, restore-plan (affected/unaffected/missing displays), tolerance matching, and settings-default all unit-green ([WindowLayoutTests.swift](../Tests/DockKeeperTests/WindowLayoutTests.swift); 76 tests total passing). The AX write path's coordinate-system assumption is **INFERRED** — hardware validation folds into **M6** (does `kAXPositionAttribute` restore windows exactly on the pinned rig).

## M10 — Pause & temporary Dock move (parity gap G4, DK-FR-009, targets v1.1) ✅ code complete (2026-07-23)

The cheapest parity win ([parity assessment](parity-assessment.md) recommended order #1): makes the reserved `Paused` state (TDD §5.1) reachable and adds an optional zero-permission hotkey. **No ADR** — no architectural deviation: pause reuses the existing pure `RecoveryMachine` + injected-scheduler coordinator; the hotkey mirrors the established `Unmanaged` C-callback pattern (DockMonitor's CG callback). The "temporary move" story is exactly pause → drag via normal macOS → resume → full reconcile re-enforces.

- ✅ `RecoveryMachine.notePaused()` / `noteResumed()` — pure transitions; `Paused` reachable only from a non-disabled state; resume → `.starting` so the follow-up reconcile re-derives steady state. Machine stays timer-free.
- ✅ `RecoveryCoordinator.pause(for:)` / `resume()` + readable `pausedUntil` / `isPaused`; auto-resume via the injected `schedule` closure with a **pause-generation counter** (manual resume or a second pause strands the stale timer — same pattern as reconcile generations). `resume()` triggers `requestReconcile()`; `disable()` strands a pending auto-resume timer.
- ✅ `HotKeyCenter` (@MainActor, app target): thin Carbon `RegisterEventHotKey`/`UnregisterEventHotKey` wrapper, ⌃⌥⌘D fixed, C-callback trampoline via `GetEventDispatcherTarget`/`InstallEventHandler`. Registered only while the setting is on. Customization deferred (future work).
- ✅ `Settings.pauseHotkeyEnabled` (Bool, default **false**, registered) — no surprise global hotkey (kickoff rule 20).
- ✅ AppState published `isPaused` / `pausedUntil` mirrors (driven by `onStateChange` + coordinator queries); menu pause/resume section (hidden while disabled); Advanced-tab toggle with combo-naming caption; hotkey and menu share one toggle path; `FileDiagnostics` note on pause/resume.

**Acceptance met (unit level):** machine pause/resume transitions incl. from-disabled rejection, and coordinator orchestration — strand-on-pause, ignore-events-while-paused, auto-resume fires reconcile via the fake scheduler, manual-resume strands the stale auto-resume timer, second-pause supersedes — all unit-green ([RecoveryTests.swift](../Tests/DockKeeperTests/RecoveryTests.swift); 87 tests total passing). The Carbon registration and menu wiring are manual (system-level, out of unit scope), folding into **M6**.

---

## M11 — Apple Shortcuts + URL-scheme automation (parity gap G6, DK-FR-010, targets v1.1) ✅ code complete (2026-07-23)

Recommended order #2 ([parity assessment](parity-assessment.md)): expose the existing controls to automation over **public APIs only, no new permission, no new engine mechanism**. **No ADR** — public surfaces (App Intents, `CFBundleURLTypes`, a stock `NSApplicationDelegate` URL method), no architectural deviation; the design note is this section. Everything routes through one pure command layer and the existing enable/lock/pause/resume funnel.

- ✅ `ControlCommand` (pure enum, **`DockKeeperCore`**) — `.lock(edge)` / `.unlock` / `.pause(TimeInterval?)` / `.resume`, plus a total `parse(url:)` for the `dockkeeper://` scheme (edge case-insensitive, user-selectable only, `minutes` positive & capped at 24h; unknown scheme/host/params → `nil`). Placed in Core (not the app target) so the test target, which links only the core library, can import it — the side-effecting funnel stays app-side.
- ✅ `AppState.perform(_:)` (app target) — the single funnel both the URL handler and the intents use; `AppState.shared` (a `@MainActor` weak reference, set on init) reaches the one live instance. `lock` enables + sets the edge (CLI parity); `unlock` disables.
- ✅ `dockkeeper://` URL scheme — `CFBundleURLTypes` in [Info.plist](../Resources/Info.plist) (scheme `dockkeeper`, role Editor, name `com.dockkeeper.app.url`; ships via the existing `build-app.sh` copy), handled in `AppDelegate.application(_:open:)`. Privacy: invalid URLs log host + a validity flag only — never query values.
- ✅ App Intents ([DockKeeperIntents.swift](../Sources/DockKeeper/App/DockKeeperIntents.swift)) — `Lock`/`Unlock`/`Pause`/`Resume` + `DockKeeperStatusIntent` (returns a `StatusSummary` shared with the `dockkeeper status` CLI so the two cannot drift) + an `AppShortcutsProvider` with Siri phrases. Mutating intents set `openAppWhenRun`; status reads the shared engine directly (`StatusSummary.live()`), so it works without the app running.
- ✅ `swift build` clean under Swift 6 strict concurrency; 106 tests green (added `ControlCommandParseTests` + `StatusSummaryTests`).

**Acceptance met (unit level):** the parse table is exhaustively green and `StatusSummary` parity is asserted. **Honest compromises (INFERRED, not executed on-device — fold verification into M6):** (1) App Intents metadata (`Metadata.appintents`) is normally an Xcode build phase; the `swift build` + `build-app.sh` path does not emit it, so Shortcuts/Siri **discovery** is UNKNOWN until packaging adds the extraction step — the URL scheme is the fully-working path meanwhile. (2) For mutating intents, accessory-app launch/`perform` ordering under `openAppWhenRun` is unverified; a not-yet-live `AppState` is a safe no-op. Neither fights the accessory model — both are documented rather than worked around ([DK-FR-010](behavior-specification.md#dk-fr-010-apple-shortcuts--url-scheme-automation) Testability). Makes **G7** (Raycast) a thin downstream deliverable over this surface.

---

## M12 — Hide the Dock during screen capture (parity gap G5, DK-FR-011, targets v1.1) ✅ code complete (2026-07-23)

Recommended-order #4 ([parity assessment](parity-assessment.md)), governed by **[ADR-011](decision-log.md#adr-011-hide-the-dock-during-screen-capture-via-a-private-screen-watcher-flag--dock-auto-hide-opt-in)** (owner-ratified). Matches DockLock Lite's screen-sharing hide with a zero-permission mechanism: detect a screen capture via the private SkyLight `CGSIsScreenWatcherPresent` (no public API exists for it — the rule-7 trade signed in ADR-011; the public camera signal is a *different* trigger, deliberately out of scope), and hide by toggling the already-CONFIRMED `CoreDockSetAutoHideEnabled`.

- ✅ `ScreenCapture` (pure wrapper, **`DockKeeperCore`**) — `dlopen`s SkyLight and resolves `CGSIsScreenWatcherPresent` with the exact `dlsym` pattern as `CoreDock`; `isAvailable`, `isCapturing()` → `false` when the symbol is absent. No state, no polling.
- ✅ `CoreDock` extended with `getAutoHideEnabled() -> Bool?` / `setAutoHideEnabled(_:) -> Bool` (over the existing `CoreDockGet/SetAutoHideEnabled`) and `getRect() -> CGRect?` (over `CoreDockGetRect`, `@convention(c) (UnsafeMutablePointer<CGRect>) -> Void`). `getRect` is the auto-hide-proof host sensor reserved for a future separate-Spaces bottom-Dock detector (spike gotcha) — **unused** by the shipped pinning path, which reads `CGDisplayBounds`/`CGMainDisplayID`.
- ✅ `ScreenShareHider` (@MainActor, **`DockKeeperCore`**) — a **pure** `decide(capturing:weHidIt:currentAutoHide:) -> {none, hide, restore}` core (all ADR-011 rules; the single `weHidIt` flag suffices because we only ever hide from a prior "off"), plus a side-effecting `evaluate`/`tick` that reads/writes `CoreDock` auto-hide and logs. Owns a 3 s poll (`defaultCheckInterval`, a documented constant — no capture-state event source exists, Principle 19 satisfied by that absence) and an `onTransition` callback for the diagnostics note. `stop()` restores if we hid (never leaves the Dock hidden).
- ✅ `Settings.hideDockDuringScreenShare` (Bool, default **false**, registered) — opt-in, off by default.
- ✅ AppState wiring: published `hideDockDuringScreenShare` (persists + starts/stops the hider), `screenCaptureAvailable` for the UI; the poll runs only while the feature is on **and** DockKeeper is enabled **and** the symbol resolved (start/stop folded into `applyEnabledState`, so disabling DockKeeper also stops it and restores). `FileDiagnostics` note (`screenshare hidden`/`restored`, state only — no PII) on transitions.
- ✅ Advanced-tab toggle "Hide the Dock while screen sharing" with a caption; disabled with an "unavailable on this macOS" note when `!ScreenCapture.isAvailable`.
- ✅ **No `RecoveryMachine`/coordinator change** — verified: the auto-hide toggle is a direct `CoreDock` call outside the recovery machinery; it changes neither orientation (`currentEdge`) nor main display / display bounds (pin decision), so it can't produce a drift correction. A visibleFrame-driven `.screenParametersChanged` would reconcile to a guaranteed no-op (no effect, no oscillation budget). Documented in ADR-011 "Coordinator interaction".

**Acceptance met (unit level):** the pure `decide` truth table is exhaustively green (all 8 `capturing × weHidIt × currentAutoHide` combos, incl. never-touch-user-auto-hide, idempotence, teardown-safe, and the registered default-false short-circuit) ([ScreenShareTests.swift](../Tests/DockKeeperTests/ScreenShareTests.swift)); full suite **114 tests** green; `swift build` clean under Swift 6 strict concurrency. **UNKNOWN pending on-device verification (folds into M6):** does the watcher flag actually flip on a real capture, its latency, and which apps trip it (QuickTime, Zoom, Teams, Screen Sharing.app) — not exercised here (starting a real capture would prompt/interfere; it is a documented hardware-matrix cell, ADR-011 Evidence). Do **not** treat the true-case detection as CONFIRMED.

---

## Cross-cutting debt (fold into the touching milestone)

From TDD A.4, tracked here so it isn't lost: ~~observer-removal fix + dead `DistributedNotificationCenter`~~ ✅ · icon ternary + `showMenuBarIcon` (M1) · pseudo-UUID persistence (M2) · ~~external-defaults observation~~ ✅ · `Log.verbose` static folded into diagnostics rework (M1) · ~~`autoRecover` removal per ADR-007~~ ✅ (all ✅ 2026-07-22 with M3/M4).

**Out of scope for v1.0** (kickoff/TDD non-goals): follow-mouse/window/app modes, Shortcuts/Raycast/AppleScript, per-app rules and profiles, per-display Dock allow/disallow, App Store, auto-update (Sparkle needs a post-v1 ADR), restoring display arrangement on disable (resolved leave-as-is — ADR-006). These deferred modes are exactly the **DockLock Plus/Pro** premium differentiators (follow mouse/active app/active window, automation, Shortcuts/Raycast — CONFIRMED, [product investigation](product-investigation.md)); staged parity is intentional per kickoff §17. **Top post-v1 parity candidate** (from investigation §3): pinning while "separate Spaces" is ON — the macOS default mode and the competitor's only supported mode — which would need a new mechanism spike (AX- or SkyLight-based, both currently rejected) and its own ADR.
