# DockKeeper vs DockLock — Parity Assessment

| | |
|---|---|
| **Status** | Point-in-time assessment (repo state `63e00f2` + window-restore feature in flight) |
| **Date** | 2026-07-23 |
| **Owner** | blamechris |
| **Inputs** | [Product investigation](product-investigation.md) (E-1…E-5), [hardware-matrix results](hardware-matrix-results.md), shipped code + 66-test suite |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**. DockLock capabilities are CONFIRMED **as vendor claims** (public listings; not yet black-box tested — rule 17 applies); DockKeeper capabilities are CONFIRMED by tests and on-rig verification.

## Verdict, up front

- **Replacement for this owner's setup (stacked portrait, left/right Dock): achieved.** Pinning, edge lock, recovery, identity, CLI all work today — in the macOS default mode, with zero permissions, on a topology where DockLock's own preferences flag incompatibility (P-015).
- **Feature-for-feature parity with DockLock Plus: not yet.** Seven gaps remain (G1–G3, G5–G8 below); **G4 shipped 2026-07-23** (pause + optional hotkey, DK-FR-009). None blocks v1.0; the recommended attack order is at the bottom.
- **DockKeeper already exceeds DockLock in six areas** — including two capabilities their unreleased "Pro" edition only *advertises*.

## Head-to-head

| Capability | DockLock (edition) | DockKeeper today | Verdict |
|---|---|---|---|
| Pin Dock to display — separate Spaces ON, **bottom** Dock | ✓ core (Lite) | ✗ honest decline + guidance | **Gap G1** (their headline) |
| Pin Dock to display — separate Spaces ON, **left/right** Dock | ✗ (bottom-only) | ✓ ADR-009, hardware-confirmed | **DockKeeper leads** |
| Pin Dock — separate Spaces **OFF** | ✗ (requires the setting ON); "Pro" claims it, unreleased | ✓ (mechanism confirmed; final observation pending logout cell) | **DockKeeper leads** |
| Any-edge Dock (bottom/left/right) lock | ✗ (bottom-only; "Pro" claims any-edge, unreleased) | ✓ shipped | **DockKeeper leads** |
| Works with a single display (edge lock) | ✗ (needs ≥2 displays) | ✓ | **DockKeeper leads** |
| Recovery after sleep/wake/display changes | ✓ claimed | ✓ event-driven + retry ladder + oscillation guard, unit-tested | Parity (ours verified, theirs untested claim) |
| Permissions | Accessibility **required** | None (AX strictly opt-in for window restore only) | **DockKeeper leads** |
| Windows kept in place on pin | n/a (different mechanism) | 🟡 opt-in restore feature in flight (ADR-010) | in progress |
| Menu-bar controls, enable/disable | ✓ | ✓ | Parity |
| Launch at login | ✓ (macOS 12+) | ✓ (`SMAppService`) | Parity |
| CLI | ✓ paid (Plus) | ✓ free | Parity (free) |
| Hide own icons / discrete mode | ✓ paid | menu-bar-only app by design | Parity-ish (n/a) |
| Temporary Dock move via modifier/hotkey | ✓ (Lite paid) | ✓ pause + optional ⌃⌥⌘D hotkey (DK-FR-009) | **G4 shipped** 2026-07-23 (Parity; free, zero-permission) |
| Hide Dock during screen sharing / meetings | ✓ (Lite) | ✗ | **Gap G5** |
| Follow mouse | ✓ (Plus) | ✗ deferred | **Gap G2** |
| Follow active window / app | ✓ (Plus) | ✗ deferred | **Gap G3** |
| Apple Shortcuts + URL scheme | ✓ (Plus) | ✗ | **Gap G6** |
| Raycast extension | ✓ (Plus, official) | ✗ | **Gap G7** |
| Sidecar / DisplayLink support | ✓ claimed (Plus) | UNKNOWN — untested | **Gap G8** (test cell) |
| Price / model | $39.99 lifetime; Lite = trial + subscription IAP (nag reported) | Free, MIT, no prompts ever | **DockKeeper leads** (mission) |

## The gaps, with honest difficulty estimates

| # | Gap | Difficulty / notes |
|---|---|---|
| G1 | **Bottom-Dock lock in separate-Spaces mode** | The big one — DockLock's core for default-config users. Needs the summon-lock mechanism spike ([separate-spaces-pinning](spikes/separate-spaces-pinning.md) queued candidates: pointer summon, AX, killall-relocation); likely needs opt-in Accessibility; own ADR. Note: macOS itself makes this fragile on stacked topologies (their own `warn_incompatible_display` — P-015). |
| G2 | Follow mouse | After G1. For left/right Docks it would mean a main-relocation per pointer-display change — a re-base storm (window shuffles each hop) that likely fails the reliability bar; for bottom Docks it needs G1's mechanism. PROPOSED: treat as G1-dependent, possibly left/right-excluded. |
| G3 | Follow active window/app | Needs Accessibility (focused-window geometry — TDD §10 anticipated this). After G1/G2. |
| ~~G4~~ | ~~Temporary-move hotkey / pause~~ | **✅ Shipped 2026-07-23** (DK-FR-009, M10). Pause (15 min / 1 hour / until resumed) + "Resume Now", optional ⌃⌥⌘D hotkey (OFF by default). `RegisterEventHotKey` public and permission-free as predicted; made the reserved `Paused` state real; no new mechanism, no ADR. Unit-tested (machine transitions + coordinator orchestration). |
| G5 | Hide Dock during screen sharing | Needs a capture-detection spike (candidate public signals exist; UNKNOWN reliability). Auto-hide toggling via `CoreDockSetAutoHideEnabled` already resolves (spike-confirmed symbol). |
| G6 | Shortcuts + URL scheme | Straightforward: AppIntents (public) + a URL-scheme handler over the existing engine. |
| G7 | Raycast extension | Separate TypeScript deliverable against the CLI/URL scheme; post-first-release. |
| G8 | Sidecar / DisplayLink | Not a feature — a hardware-matrix test cell (fingerprints for virtual displays UNKNOWN, e.g. UUID-less `cg-` cases already handled defensively). |

## Recommended order

1. ~~**G4** (hotkey pause/temporary move)~~ — **✅ done 2026-07-23** (zero permissions, used the reserved machinery, as predicted).
2. **G6** (Shortcuts + URL scheme) — small, makes G7 possible.
3. **G1** (bottom-mode lock) — the flagship gap; spike first, own ADR, likely opt-in AX.
4. **G5** (screen-share hide) — spike, then small feature.
5. **G2/G3** (follow modes) — after G1; design constrained by the re-base cost.
6. **G7/G8** — post-release.

With G4+G6+G1 done, DockKeeper would match or beat every *shipping* DockLock capability; G2/G3 close the premium tier.
