# DockKeeper — Product Investigation (Phase 1)

| | |
|---|---|
| **Status** | First pass complete (documentation-based); black-box testing not yet performed |
| **Date** | 2026-07-23 |
| **Owner** | blamechris |
| **Subject** | The DockLock family (Lite / Plus / Pro) by Ihor July — the commercial product DockKeeper replaces |
| **Inputs** | [research/evidence/docklock-2026-07-23.md](../research/evidence/docklock-2026-07-23.md) (E-1…E-4), kickoff Phase-1 template |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**. Per the kickoff rules: a vendor's published claim is CONFIRMED **as a claim** (public product documentation); whether the behavior actually works as described stays UNKNOWN until black-box tested on a legitimately installed copy. No decompiling, no asset copying — independent implementation only.

## 1. Product variants

| | Lite | Plus | Pro |
|---|---|---|---|
| Distribution | Mac App Store | Mac App Store | Website-only, "upcoming" |
| Pricing | Free + IAP ($1.99/mo, $16.99/yr, $39.99 unlock) | **$39.99 lifetime** | unstated |
| Trial | 7-day full trial, core stays free | — | — |
| macOS | 10.9+ | 10.9+ | 10.9+ |
| Permissions | Accessibility | Accessibility | UNKNOWN |
| Sandbox | Yes (App Store) | Yes (App Store) | No (direct) — INFERRED from channel |

All rows CONFIRMED from E-1/E-2/E-3 except as labeled.

## 2. Behavior inventory (evidence table)

| ID | Behavior | Status | Evidence | Notes |
|---|---|---|---|---|
| P-001 | Locks Dock to a selected display | CONFIRMED (claimed) | E-1/E-2/E-3 | The headline feature; mechanism undisclosed |
| P-002 | **Requires "Displays have separate Spaces" ENABLED** | CONFIRMED (claimed) | E-2/E-3 limitations | The pivotal fact — see §3 |
| P-003 | **Bottom Dock only** | CONFIRMED (claimed) | E-2/E-3 limitations | Left/right unsupported in Lite/Plus |
| P-004 | **Requires ≥ 2 displays to function** | CONFIRMED (claimed) | E-2/E-3 limitations | |
| P-005 | Requires Accessibility permission | CONFIRMED (claimed) | E-1 | Sandboxed + AX → mechanism likely AX-event-driven, INFERRED |
| P-006 | Recovers after sleep/wake ("position restoration after sleep") | CONFIRMED (claimed) | E-2 | Quality/latency UNKNOWN |
| P-007 | Follow-mouse mode | CONFIRMED (claimed) | E-2 (Plus) | Premium tier |
| P-008 | Follow-active-window / follow-apps mode | CONFIRMED (claimed) | E-2 (Plus) | Premium tier |
| P-009 | Shortcuts, URL scheme, Raycast, CLI, hotkeys | CONFIRMED (claimed) | E-1/E-2 (Plus) | Premium tier |
| P-010 | Hide Dock during screen sharing/meetings | CONFIRMED (claimed) | E-3 | Not in DockKeeper's scope |
| P-011 | Any-edge + works with Spaces disabled + cross-display vertical Dock | CONFIRMED (claimed, **unreleased**) | E-1 (Pro) | Pro is direct-download → likely non-sandboxed mechanisms, INFERRED (mirrors DockKeeper's approach) |
| P-012 | Behavior with mirrored displays / clamshell / Stage Manager | UNKNOWN | none | Not documented |
| P-013 | Subscription nag in Lite | CONFIRMED (user reports, low sample) | E-3 reviews | The pain point DockKeeper's principles delete |
| P-014 | Actual reliability of P-001/P-006 under the hardware matrix | UNKNOWN | none | Needs black-box testing on an installed copy (Lite is installed on the dev rig — E-5) |
| P-015 | Ships an "incompatible display" warning (`warn_incompatible_display`) | CONFIRMED | E-5 (installed copy's prefs) | Its bottom-only summon approach is known-fragile on some topologies — observed failing on stacked portrait-above (spike) |

## 3. The structural insight: the two products cover **opposite macOS modes**

macOS's "Displays have separate Spaces" setting (default **ON**) splits the world:

| Mode | DockLock Lite/Plus | DockKeeper v1 |
|---|---|---|
| Separate Spaces **ON** (default) | ✅ Its only supported mode (P-002) — pins the per-display Dock, bottom-only, ≥2 displays, via Accessibility | Edge lock ✅ · display pinning **declined honestly** (Decision 2A) |
| Separate Spaces **OFF** | ❌ Unsupported | Edge lock ✅ · display pinning ✅ (main-display relocation, no permissions) |

Consequences (all PROPOSED as roadmap input, none changing v1 — Decision 3 stands):

1. **DockKeeper's differentiators are real and complementary**: free/MIT, zero permissions, zero network, any Dock edge, works with one display (edge lock), no trial/subscription mechanics — versus DockLock's bottom-only/≥2-display/Accessibility/paid profile.
2. **The gap to name honestly**: in the macOS *default* mode, DockKeeper does not pin to a display (by owner decision) while the competitor's core feature does. Staged parity's next candidate is therefore a **separate-Spaces-mode pinning spike** (likely AX- or SkyLight-based — both previously rejected for v1; a post-v1 ADR would be required), ranking *above* follow-mouse in parity value.
3. DockLock **Pro**'s unreleased claims (any edge, Spaces-off support, direct distribution) mirror DockKeeper's shipped v1 mechanism profile — INFERRED that both converge on non-sandboxed approaches for those capabilities.
4. R-010 (name/trademark) is live: an active, paid, similarly-named product family exists.

## 4. Parity status

Tracked separately and kept current: [parity-assessment.md](parity-assessment.md) (verdict + gap ladder G1–G8).

## 5. Open investigation work

- Black-box test on a legitimately installed DockLock Lite (free tier): verify P-001/P-006 behavior, latency, and oscillation under the [hardware matrix](hardware-matrix-results.md) — turns "claimed" rows into observed facts.
- Mine E-4 (GitHub landing) for changelog/mechanism hints (public info only).
- Feed observed behaviors into `behavior-specification.md` only where DockKeeper *chooses* to match them (rule 17: no parity claims without evidence).
