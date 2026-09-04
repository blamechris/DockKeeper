# DockKeeper vs DockLock — Parity Assessment

| | |
|---|---|
| **Status** | Living assessment — last updated 2026-09-02 (G1 bottom-Dock guard ADR-015 shipped opt-in, on-device confirmation open; earlier: window-restore ADR-010, G4 pause/hotkey, G6 Shortcuts+URL scheme, G5 screen-share hide) |
| **Date** | 2026-07-23 · last revised 2026-09-02 |
| **Owner** | blamechris |
| **Inputs** | [Product investigation](product-investigation.md) (E-1…E-5), [hardware-matrix results](hardware-matrix-results.md), shipped code + 114-test suite |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**. DockLock capabilities are CONFIRMED **as vendor claims** (public listings; not yet black-box tested — rule 17 applies); DockKeeper capabilities are CONFIRMED by tests and on-rig verification.

## Verdict, up front

- **Replacement for this owner's setup (stacked portrait, left/right Dock): achieved.** Pinning, edge lock, recovery, identity, CLI all work today — in the macOS default mode, with zero permissions, on a topology where DockLock's own preferences flag incompatibility (P-015).
- **Feature-for-feature parity with DockLock Plus: not yet.** Four gaps remain (G2–G3, G7–G8 below); **G1 shipped opt-in in v0.9.3** (bottom-Dock guard, DK-FR-014 / ADR-015 — the human-in-the-loop confirmation remains an open obligation), **G4 shipped 2026-07-23** (pause + optional hotkey, DK-FR-009), **G6 shipped 2026-07-23** (Apple Shortcuts + `dockkeeper://` URL scheme, DK-FR-010), and **G5 shipped 2026-07-23** (hide the Dock during screen capture, DK-FR-011, ADR-011). None blocks v1.0; the recommended attack order is at the bottom.
- **DockKeeper already exceeds DockLock in six areas** — including two capabilities their unreleased "Pro" edition only *advertises*.

## Head-to-head

| Capability | DockLock (edition) | DockKeeper today | Verdict |
|---|---|---|---|
| Pin Dock to display — separate Spaces ON, **bottom** Dock | ✓ core (Lite) | ✓ opt-in guard (DK-FR-014, ADR-015), confirmed on-device with a control | **G1 closed** 2026-09-02 (shipped 2026-08-29, confirmed on hardware 2026-09-02) |
| Pin Dock to display — separate Spaces ON, **left/right** Dock | ✗ (bottom-only) | ✓ ADR-009, hardware-confirmed | **DockKeeper leads** |
| Pin Dock — separate Spaces **OFF** | ✗ (requires the setting ON); "Pro" claims it, unreleased | ✓ (mechanism confirmed; final observation pending logout cell) | **DockKeeper leads** |
| Any-edge Dock (bottom/left/right) lock | ✗ (bottom-only; "Pro" claims any-edge, unreleased) | ✓ shipped | **DockKeeper leads** |
| Works with a single display (edge lock) | ✗ (needs ≥2 displays) | ✓ | **DockKeeper leads** |
| Recovery after sleep/wake/display changes | ✓ claimed | ✓ event-driven + retry ladder + oscillation guard, unit-tested | Parity (ours verified, theirs untested claim) |
| Permissions | Accessibility **required** | None by default (AX strictly opt-in, for window restore and the bottom-Dock guard) | **DockKeeper leads** |
| Windows kept in place on pin | n/a (different mechanism) | ✓ opt-in restore shipped (ADR-010; one of the app's two opt-in permission uses) | **DockKeeper-only capability** |
| Menu-bar controls, enable/disable | ✓ | ✓ | Parity |
| Launch at login | ✓ (macOS 12+) | ✓ (`SMAppService`) | Parity |
| CLI | ✓ paid (Plus) | ✓ free | Parity (free) |
| Hide own icons / discrete mode | ✓ paid | menu-bar-only app by design | Parity-ish (n/a) |
| Temporary Dock move via modifier/hotkey | ✓ (Lite paid) | ✓ pause + optional ⌃⌥⌘D hotkey (DK-FR-009) | **G4 shipped** 2026-07-23 (Parity; free, zero-permission) |
| Hide Dock during screen sharing / meetings | ✓ (Lite) | ✓ screen-capture detect + Dock auto-hide (DK-FR-011, ADR-011) | **G5 shipped** 2026-07-23 (Parity; free, zero-permission; true-case UNKNOWN pending on-device) |
| Follow mouse | ✓ (Plus) | ✗ deferred | **Gap G2** |
| Follow active window / app | ✓ (Plus) | ✗ deferred | **Gap G3** |
| Apple Shortcuts + URL scheme | ✓ (Plus) | ✓ App Intents + `dockkeeper://` scheme (DK-FR-010) | **G6 shipped** 2026-07-23 (Parity; free, zero-permission) |
| Raycast extension | ✓ (Plus, official) | ✗ | **Gap G7** |
| Sidecar / DisplayLink support | ✓ claimed (Plus) | UNKNOWN — untested | **Gap G8** (test cell) |
| Price / model | $39.99 lifetime; Lite = trial + subscription IAP (nag reported) | Free, MIT, no prompts ever | **DockKeeper leads** (mission) |

## The gaps, with honest difficulty estimates

| # | Gap | Difficulty / notes |
|---|---|---|
| G1 | **Bottom-Dock lock in separate-Spaces mode** — **SHIPPED opt-in 2026-08-29** (DK-FR-014, [ADR-015](decision-log.md#adr-015-hold-a-bottom-dock-by-blocking-the-summon-never-by-relocating-it)): `BottomDockGuard` decides, `BottomDockGuardTap` holds the band, **87 unit tests**, mutation-checked on the coordinate orientation, the safety gate and the free-span arithmetic. **Extended to per-free-span clamping 2026-09-03** ([#83](https://github.com/blamechris/DockKeeper/issues/83)): a whole-display refusal left ~2112 px of the owner's own bottom edge unguarded, so zones are emitted per free span and only the shared span is skipped. **The human-in-the-loop confirmation of the summon block is CLOSED** — confirmed on-device with a control 2026-09-02 — and **the crossing under per-span zones is CONFIRMED too** — 2026-09-03 with a control on the owner's stacked rig (test-strategy §3d row 9, hardware matrix session 4): the shared span stays crossable while both overhangs hold 10/10 at `clampY = -3`. G1's on-device obligations are closed — including row 9's Dock-migration clause, which a synthetic walk cannot exercise and which was confirmed by hand with a control on the same rig. What remains open is the *cost* (R-015). **REOPENED 2026-08-27: viable by *prevention*.** A `CGEventTap` that keeps the pointer off the trigger row of a non-preferred display stops the hop; confirmed with a control (clamped `y=2157` vs `y=2159` unclamped). Matches every DockLock constraint — Accessibility, bottom-only, ≥2 displays, separate-Spaces-on, and their `warn_incompatible_display` (clamping a *shared* bottom edge would trap the cursor). Briefly closed as not-viable earlier the same day; that was scoped to **relocation**, which is genuinely impossible and stands. Every mechanism family falsified on hardware (summon via warp and via `CGEventPost` under a real Accessibility grant; AX geometry read-only; `SLSSetDockRect{WithOrientation,WithReason}` accept a rect on another display without the Dock following). A real pointer works and nothing a userspace process can do reproduces it — placement is the Dock process's decision. The "DockLock synthesizes a summon" hypothesis is **unsupported**; what their Accessibility grant buys is UNKNOWN. See [the spike](spikes/separate-spaces-pinning.md). Original assessment follows. | The big one — DockLock's core for default-config users. Needs the summon-lock mechanism spike ([separate-spaces-pinning](spikes/separate-spaces-pinning.md) queued candidates: pointer summon, AX, killall-relocation); likely needs opt-in Accessibility; own ADR. Note: macOS itself makes this fragile on stacked topologies (their own `warn_incompatible_display` — P-015). |
| G2 | Follow mouse | After G1. For left/right Docks it would mean a main-relocation per pointer-display change — a re-base storm (window shuffles each hop) that likely fails the reliability bar; for bottom Docks it needs G1's mechanism. PROPOSED: treat as G1-dependent, possibly left/right-excluded. |
| G3 | Follow active window/app | Needs Accessibility (focused-window geometry — TDD §10 anticipated this). After G1/G2. |
| ~~G4~~ | ~~Temporary-move hotkey / pause~~ | **✅ Shipped 2026-07-23** (DK-FR-009, M10). Pause (15 min / 1 hour / until resumed) + "Resume Now", optional ⌃⌥⌘D hotkey (OFF by default). `RegisterEventHotKey` public and permission-free as predicted; made the reserved `Paused` state real; no new mechanism, no ADR. Unit-tested (machine transitions + coordinator orchestration). |
| ~~G5~~ | ~~Hide Dock during screen sharing~~ | **✅ Shipped 2026-07-23** (DK-FR-011, M12, **ADR-011**). Screen-capture detection via the **private** `CGSIsScreenWatcherPresent` (degrades safely — feature simply unavailable if the symbol is absent) + Dock auto-hide toggle; **opt-in, off by default**, zero permission. Scope deliberately narrowed to *screen capture* (not the public camera / video-call signal). Pure `decide` core exhaustively unit-tested (never touches a user's own auto-hide; idempotent; teardown-safe). The auto-hide toggle is verified **not** to trigger any drift/reconcile (no `RecoveryMachine` change). `CoreDockGetRect` wrapper added as the auto-hide-proof host sensor for a future G1 detector (unused today). **Honest INFERRED follow-up:** the true capture-flip (does the flag fire, latency, which apps) is **UNKNOWN pending on-device verification** — a documented M6/M12 hardware cell; not exercised here (a real capture would prompt/interfere). |
| ~~G6~~ | ~~Shortcuts + URL scheme~~ | **✅ Shipped 2026-07-23** (DK-FR-010, M11). App Intents (Lock/Unlock/Pause/Resume/Status) + `AppShortcutsProvider` and a `dockkeeper://` URL scheme, all funneled through one pure `ControlCommand` + `AppState.perform(_:)` — public APIs, zero permission, no new mechanism, no ADR. Parse table unit-tested; on-device Shortcuts/Siri discovery + the App Intents metadata packaging step are the honest INFERRED follow-ups (URL scheme works today). Unblocks G7. |
| G7 | Raycast extension | Separate TypeScript deliverable against the CLI/URL scheme; post-first-release. |
| G8 | Sidecar / DisplayLink | Not a feature — a hardware-matrix test cell (fingerprints for virtual displays UNKNOWN, e.g. UUID-less `cg-` cases already handled defensively). |

## Recommended order

1. ~~**G4** (hotkey pause/temporary move)~~ — **✅ done 2026-07-23** (zero permissions, used the reserved machinery, as predicted).
2. ~~**G6** (Shortcuts + URL scheme)~~ — **✅ done 2026-07-23** (public APIs, zero permission; made G7 a thin downstream deliverable).
3. ~~**G1** (bottom-mode lock)~~ — **shipped opt-in 2026-08-29** (DK-FR-014, ADR-015): ADR written, Accessibility opt-in, shared-bottom-edge refusal implemented as a hard gate. Relocation remains impossible and the framing is binding: *stop the Dock leaving*, not *put it back*. Remaining: observe a real pointer failing to summon on a two-display rig.
4. ~~**G5** (screen-share hide)~~ — **✅ done 2026-07-23** (DK-FR-011, M12, ADR-011; private detector behind graceful degradation, zero permission; true-case is a documented on-device follow-up).
5. **G2/G3** (follow modes) — after G1; design constrained by the re-base cost.
6. **G7/G8** — post-release.

With G4+G5+G6 shipped and **G1 shipped opt-in on 2026-08-29**, DockKeeper has an implementation for every *shipping* DockLock capability — by prevention rather than relocation, which is almost certainly what DockLock does too (INFERRED from constraint-fit, not reverse-engineered). G1's on-device confirmation remains open. G2/G3 close the premium tier.
