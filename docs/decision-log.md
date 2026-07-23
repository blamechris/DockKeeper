# DockKeeper — Decision Log (ADRs)

| | |
|---|---|
| **Status** | Living document |
| **Date** | 2026-07-22 |
| **Owner** | blamechris |
| **Inputs** | [Technical design](technical-design.md) §13/§16, [Preferred-display spike](../Documentation/spikes/preferred-display-spike.md) (owner Decisions 1–3, signed 2026-07-22), kickoff package §9 (ADR-001…005 slots) |

Evidence labels: **CONFIRMED** · **INFERRED** · **PROPOSED** · **UNKNOWN**. Record format per the kickoff package: Context / Options / Decision / Consequences / Evidence / Date / Status.

**Pre-ADR owner decisions.** The spike records three owner-ratified decisions (2026-07-22) that ADRs below build on: (1) pin via the public main-display route, menu-bar move accepted, no SkyLight; (2) "separate Spaces ON" is unsupported-and-explained, never fought; (3) v1.0 = always-reliable edge lock + best-effort pinning. These are treated as CONFIRMED inputs.

---

## ADR-001: Minimum supported macOS version — macOS 14+

**Context.** The kickoff assumed macOS 14+ as a starting point, to be validated. The v0.1 codebase already targets it.

**Options.** macOS 13 (wider reach; `MenuBarExtra`/`SMAppService` both exist there) · macOS 14 (current toolchain default, smaller test matrix) · macOS 15+ (needlessly narrow).

**Decision.** macOS 14 or later.

**Consequences.** Smaller OS test matrix; excludes pre-2018-era unsupported machines only; Intel remains supported where practical (universal binary — INFERRED unproblematic, verify at first release build). Lowering to 13 later would require re-testing `CoreDock` behavior there (UNKNOWN on 13).

**Evidence.** `Package.swift` declares `platforms: [.macOS(.v14)]` — CONFIRMED; v0.1 built and verified on-device against it.

**Date / Status.** 2026-07-22 · **Accepted** (de facto — ratified by the shipped scaffold).

---

## ADR-002: Distribution — Developer ID direct download + Homebrew cask; no Mac App Store for v1

**Context.** The sandbox question had to be settled before choosing distribution (kickoff §6.13: don't pick the App Store until sandbox feasibility is established).

**Options.** Mac App Store · Developer ID notarized direct download · Homebrew cask · source-only.

**Decision.** Primary: notarized Developer ID direct download (`.dmg`/`.zip`). Alongside: a Homebrew cask pointing at the same notarized artifact (also solving CLI install/symlink). Source builds remain supported for developers. Mac App Store: rejected for v1.

**Consequences.** No sandbox constraints on `dlsym`/`killall`; requires hardened runtime + notarization pipeline (release checklist); no App Store discovery; auto-update deferred (Sparkle would add a network call — needs its own ADR post-v1 to honor the no-unnecessary-network principle).

**Evidence.** Sandbox blocks signaling other processes (`killall Dock`) — CONFIRMED policy; private-API use fails App Store review — CONFIRMED policy; a sandboxed CoreDock-free build would have no working restore mechanism at all (TDD §13). No entitlement conflicts expected for notarization — INFERRED, verify at first notarization run.

**Date / Status.** 2026-07-22 · **Accepted**.

---

## ADR-003: Dock restoration mechanism — private CoreDock API with public fallback ⚠️ needs owner ratification

**Context.** There is no public API to set the Dock's edge or display. Kickoff rule 7: *"Use public macOS APIs unless an ADR explicitly approves otherwise"* — this is that ADR. The spike's owner decisions implicitly approve the approach; this record formalizes it.

**Options.**
1. `defaults write com.apple.dock orientation` + `killall Dock` as primary — public-ish, but visibly restarts the Dock and destroys Dock state on every correction.
2. Accessibility-driven interaction (AX drag) — needs the heavyweight permission v1 otherwise avoids entirely; fragile against Dock UI changes.
3. Private `CoreDock` C API (`CoreDockSet/GetOrientationAndPinning`), resolved at runtime via `dlsym`, with option 1 as automatic fallback.
4. Private SkyLight/CGS — rejected by owner (Decision 1) for fragility.

**Decision.** Option 3 for edge lock. For display pinning: public `CGDisplayConfiguration` main-display relocation (owner Decision 1) — no private APIs in the pinning path.

**Consequences.** Deviates from "public APIs strongly preferred" on the edge path; accepted because the failure mode is graceful (unresolved symbol → fallback + `Degraded` state, not a crash) and the user experience of the primary path is categorically better (live, flicker-free — the fallback restarts the Dock visibly). Ongoing obligations: per-macOS-release smoke test (risk R-004), explicit `dlopen` of HIServices for non-AppKit processes (spike hardening), Mac App Store remains blocked (see ADR-002).

**Evidence.** Symbols resolve and work live, flicker-free, on-device — CONFIRMED (spike, macOS 26.5 Apple Silicon); fallback path works — CONFIRMED; symbol availability requires HIServices loaded — CONFIRMED (spike).

**Date / Status.** 2026-07-22 · **Proposed — awaiting explicit owner ratification.** The spike decisions cover the pinning mechanism but do not explicitly ratify private-API use for the edge path; kickoff rule 7 requires that sign-off to be recorded here. Everything already ships this way in v0.1, so ratification (or reversal) should be prompt.

---

## ADR-004: Display identity — multi-identifier fingerprint with scored matching

**Context.** A preferred display must be recognized across reconnects, docks, adapters, and reboots. UUID stability across those paths is UNKNOWN (kickoff §6.6 explicitly forbids assuming it), and v0.1's bare-UUID storage — with an unstable `"cg-<id>"` pseudo-UUID fallback that can be persisted — is insufficient.

**Options.** Bare UUID (status quo) · display name only (collides on identical models) · multi-identifier fingerprint (UUID + vendor/model/serial + localized name + built-in flag) with scored matching, repair, and an ambiguity refusal.

**Decision.** Fingerprint + scored matching per TDD §7.2: accept the best candidate iff score ≥ 70 and it is the unique maximum; on fallback-evidence matches, rewrite the stored fingerprint with fresh values (stale-preference repair); on ties (e.g. identical twin externals with serial 0), never guess — ask the user to re-pick. When the preferred display is absent, no fallback display is ever selected (TDD §7.4).

**Consequences.** Migration required (`preferredDisplayUUID` → fingerprint with only `uuid` populated); score thresholds are PROPOSED and must be tuned on hardware (R-003); slightly more persistence complexity for materially better resilience.

**Evidence.** All constituent APIs CONFIRMED available (TDD §7.1); serial-number reliability INFERRED (frequently 0 on consumer panels); UUID stability UNKNOWN — the design assumes the worst case by construction.

**Date / Status.** 2026-07-22 · **Accepted** (design; thresholds subject to hardware tuning at M6).

---

## ADR-005: Monitoring — hybrid event-driven with a 30-second polling safety net

**Context.** Kickoff rule 19: avoid continuous polling unless evidence shows events are insufficient. v0.1 ships a 2 s poll — polling-first in spirit, inverting the burden of proof. Whether events ever miss in practice is UNKNOWN.

**Options.** Event-only (risks standing drift on gaps — UNKNOWN frequency) · polling-only (rejected outright, rule 19) · hybrid with a conservative interval.

**Decision.** Events are primary (catalog in TDD §8.1); the poll is a safety net only, default interval **30 s** (up from v0.1's 2 s). Every poll-caught drift (as opposed to event-caught) is counted locally; that evidence later justifies lengthening toward 60 s+/event-only — or shortening, if real gaps appear.

**Consequences.** A drift landing in an event gap can stand for up to 30 s — accepted (rare, and invisible correction beats constant wakeups); the interval stays user-tunable via the existing `recoveryInterval` setting so field-tuning needs no release.

**Evidence.** All event sources CONFIRMED wired in v0.1; poll work per tick is two C calls — INFERRED negligible either way (the objection to 2 s is principle, not measured cost); gap frequency UNKNOWN pending the drift-source counter.

**Date / Status.** 2026-07-22 · **Accepted** (supersedes the v0.1 de facto 2 s choice; implementation pending).
