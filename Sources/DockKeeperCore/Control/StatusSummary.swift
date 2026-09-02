import Foundation

/// The fields `dockkeeper status` reports, in one place so the CLI and the
/// `DockKeeperStatusIntent` cannot drift — a claim that now holds because both
/// go through `live(settings:now:)` rather than re-spelling the construction,
/// and because no field may be silently omitted (see `init`).
///
/// Pure and `Sendable`, and that includes the clock: `reportedAt` is a stored
/// input, so every rendering on one value reads the same "now" and `==` still
/// implies identical output. `live(settings:now:)` is the only place that
/// touches the real clock, the same way it is the only place that touches
/// `Settings` and `CoreDock`.
public struct StatusSummary: Equatable, Sendable {
    public let isEnabled: Bool
    public let lockEdge: DockOrientation
    /// The Dock's current edge, or `nil` when macOS reports an unknown value.
    public let currentEdge: DockOrientation?
    /// Human-readable name of the active edge mechanism (primary or fallback).
    public let mechanism: String
    public let coreDockAvailable: Bool

    /// The durable pause record, or `nil` when corrections are not paused
    /// (DK-FR-009, ADR-014). Distinct from `isEnabled`: a paused instance is
    /// still enabled and still configured, it is simply not correcting — which
    /// is why reporting only `Enabled: yes` was actively misleading (#36).
    public let pauseRecord: PauseRecord?

    /// When this snapshot was taken — the "now" every pause deadline is read
    /// against.
    ///
    /// It is a stored input rather than a `Date()` read inside the accessors
    /// because the type's contract is that it is pure: `live(settings:now:)` is
    /// the one place allowed to touch the real clock, exactly as it is the one
    /// place allowed to touch `Settings` and `CoreDock`. A hidden clock read
    /// would also make `cliText` and `voiceLine` two *different* nows on the
    /// same value, which is the bug `Diagnostics.pauseStatus()` already avoids
    /// by taking one reading for both quantities.
    ///
    /// The consequence, stated because it is surprising: `Equatable` gets
    /// stricter. Two summaries of an identical state taken a millisecond apart
    /// now compare unequal. That is the safe direction — `==` again implies
    /// identical rendered output, which it would *not* if the clock were read
    /// per-accessor — but a test comparing whole summaries must supply the same
    /// `reportedAt` to both.
    public let reportedAt: Date

    public init(
        isEnabled: Bool,
        lockEdge: DockOrientation,
        currentEdge: DockOrientation?,
        mechanism: String,
        coreDockAvailable: Bool,
        // Deliberately **not** defaulted. It was, for source compatibility, and
        // that default silently kept a stale hand-rolled copy in
        // `AppState.statusSummary()` compiling — so the Shortcuts/Siri intent
        // went on reporting "enabled" while paused. A required argument turns
        // that class of miss into a build error instead of a wrong answer.
        pauseRecord: PauseRecord?,
        // Not defaulted either, for the same reason and with a sharper edge: a
        // `= Date()` here would put an ambient clock read back into every call
        // site that forgot it, which is precisely the hidden-clock property the
        // stored value exists to remove.
        reportedAt: Date
    ) {
        self.isEnabled = isEnabled
        self.lockEdge = lockEdge
        self.currentEdge = currentEdge
        self.mechanism = mechanism
        self.coreDockAvailable = coreDockAvailable
        self.pauseRecord = pauseRecord
        self.reportedAt = reportedAt
    }

    /// Snapshot the live state from the shared engine surface. Works without the
    /// menu-bar app running — it reads the same `Settings`/`DockController`/
    /// `CoreDock` the CLI does.
    public static func live(settings: Settings = .shared, now: Date = Date()) -> StatusSummary {
        let controller = DockController(settings: settings)
        return StatusSummary(
            isEnabled: settings.isEnabled,
            lockEdge: settings.lockEdge,
            currentEdge: controller.currentOrientation(),
            mechanism: controller.activeMechanismName,
            coreDockAvailable: CoreDock.isAvailable,
            pauseRecord: settings.pauseRecord,
            reportedAt: now
        )
    }

    /// The exact lines `dockkeeper status` prints, in order.
    public var cliLines: [String] {
        [
            "Enabled:    \(isEnabled ? "yes" : "no")",
            "Lock edge:  \(lockEdge.displayName)",
            "Dock is on: \(currentEdge?.displayName ?? "unknown")",
            "Paused:     \(pauseLine)",
            "CoreDock:   \(coreDockAvailable ? "available" : "unavailable (using defaults fallback)")",
        ]
    }

    /// What the pause record says once read against `reportedAt`.
    ///
    /// Deliberately **private, and deliberately not shared with**
    /// `Diagnostics.pauseStatus()`, though #47 suggested one formatter for
    /// both. The two surfaces have opposite privacy contracts — `status` may
    /// print a wall clock because the user reads it at their own machine
    /// (below), `--diagnostics` may never (DK-PRIV-001 S2) — so the most that
    /// could be shared is this *classification*, never a rendered string. That
    /// is worth doing, but not here: `pauseStatus()` is a `private static` in
    /// the app target, which the test bundle cannot link, so promoting it is a
    /// refactor of the surface users paste to a stranger, in service of a
    /// defect that lives entirely in this file (AGENTS rule 12). Filed instead.
    ///
    /// `pausedAt` is deliberately **not** consulted. `status` has never used
    /// it, and classifying on it would let an absurd-but-decodable `pausedAt`
    /// swallow a perfectly good `pausedUntil` — reporting "corrupt" where the
    /// deadline is right there and readable. Record age is `--diagnostics`'
    /// job, and it already does it.
    private enum PauseReading: Equatable {
        case notPaused
        /// No timer at all — nothing but an explicit resume ever ends it.
        case untimed
        case timed(until: Date)
        /// The deadline has passed. Says nothing about whether DockKeeper is
        /// alive: ADR-014 is explicit that `status` reports *configured state,
        /// not liveness*, and this process has no liveness signal of any kind.
        /// A renderer may say the deadline has passed; it must not say the app
        /// is dead.
        case overdue(until: Date)
        case unreadableDeadline
    }

    private var pauseReading: PauseReading {
        guard let pauseRecord else { return .notPaused }
        guard let until = pauseRecord.pausedUntil else { return .untimed }
        // `wholeSeconds` is the clamp, not a nicety: `pausedUntil` is decoded
        // from a user-writable defaults domain, and `Int(_: Double)` traps on
        // the decodable-but-absurd stamps that store can hold. `status` did no
        // arithmetic on these dates before this change, so the exposure is
        // created here and covered in the same breath.
        //
        // It bounds the magnitude and nothing else. A deadline inside the bound
        // but still absurd — a year-5828963 stamp — stays classified and gets
        // rendered, saturated, by `deadlineText`. That is accepted: it is
        // *visibly* nonsense, where the pre-#47 rendering turned the same input
        // into a plausible-looking "until 4:00 PM" that hid the corruption
        // entirely. Tightening it to a plausibility window would be a new
        // policy about what a legitimate deadline may be, which belongs in its
        // own decision rather than in a reporting fix.
        let remaining = until.timeIntervalSince(reportedAt)
        guard DisplayDuration.wholeSeconds(remaining) != nil else { return .unreadableDeadline }
        // Compared as an interval, not as `wholeSeconds`' truncated `Int`:
        // truncation toward zero puts every deadline in [now, now + 1s) at 0,
        // which would report a pause with most of a second still to run as
        // one whose auto-resume is overdue. The sign is the whole question, so
        // it is asked of the quantity that actually carries it.
        return remaining > 0 ? .timed(until: until) : .overdue(until: until)
    }

    /// A deadline the reader cannot misdate.
    ///
    /// `date: .omitted` alone renders *yesterday* 3:45 PM identically to
    /// today's, so a day-old record reads as later today. That is wrong for a
    /// stale record and wrong for a live one too — a pause taken at 11 PM with
    /// a 12-hour timer has a perfectly valid deadline on the following day —
    /// so the date rides along whenever the deadline is not on the reporting
    /// day, and the common case stays the short bare time it always was.
    private func deadlineText(_ until: Date) -> String {
        // Asked of `Calendar` and nothing else. An earlier revision guarded this
        // with `abs(interval) < 86_400 &&`, on the reasoning that beyond a day
        // the same-day answer cannot be true. Two things were wrong with it and
        // both are worth recording, because the guard looked obviously correct.
        //
        // It was **false**: a fall-back DST day is 25 hours long, so 00:10 and
        // 23:50 on it are 88,800 s apart and genuinely the same day — the guard
        // would have short-circuited that pair and printed a redundant date.
        //
        // And it was **unobservable**: deleting it changed no output and failed
        // no test (measured). `pauseReading` has already rejected anything
        // outside `DisplayDuration`'s bound, so every date reaching here is one
        // `Calendar` answers correctly; for an absurd-but-in-bound value it
        // simply answers `false`, which is the same branch the guard forced.
        // A guard with a wrong justification and no effect is worse than none.
        let sameDay = Calendar.current.isDate(until, inSameDayAs: reportedAt)
        return sameDay
            ? until.formatted(date: .omitted, time: .shortened)
            : until.formatted(date: .abbreviated, time: .shortened)
    }

    /// Appended when a record is present alongside `Enabled: no`.
    ///
    /// The pair is reachable and durable: an untrappable exit leaves the record
    /// (ADR-014), and `dockkeeper unlock` then writes `isEnabled` from a
    /// separate process without touching it, so nothing reconciles the two
    /// until the app next launches. The record is **qualified, never
    /// suppressed** — dropping it would destroy the evidence #36 exists to
    /// preserve, and both lines are individually true. What was wrong was the
    /// report contradicting itself.
    private var disabledQualifier: String {
        isEnabled ? "" : "; DockKeeper is disabled"
    }

    /// The `Paused:` value, printed whether or not a pause is in force — the
    /// point of #36 is that the two cases be *distinguishable*, which a line
    /// that vanishes when unpaused does not achieve in a pasted support report.
    ///
    /// A wall-clock deadline is fine here: unlike `--diagnostics`, `status` is
    /// read by the user at their own machine, and a wall clock is what the menu
    /// already shows them (`AppState.pausedStatusText`). Note the menu still
    /// renders `date: .omitted` unconditionally, so it keeps the day ambiguity
    /// fixed here — reachable there too, since a `dockkeeper://pause` may run to
    /// `ControlCommand.maxPauseSeconds` (24 h). Left alone deliberately: it is
    /// in the app target, which the test bundle cannot link, and sharing the
    /// rule means promoting it. Filed rather than duplicated.
    ///
    /// Every branch keeps the `yes (` prefix, so the line stays greppable and
    /// the existing substring assertions keep meaning what they meant.
    var pauseLine: String {
        guard let detail = pauseDetail else { return "no" }
        return "yes (\(detail)\(disabledQualifier))"
    }

    /// The parenthetical after `yes`, or `nil` when there is no record.
    private var pauseDetail: String? {
        switch pauseReading {
        case .notPaused:
            return nil
        case .untimed:
            return "until resumed — no timer"
        case .timed(let until):
            return "until \(deadlineText(until))"
        case .overdue(let until):
            // "auto-resume overdue", not "stale record". The deadline having
            // passed is a fact this process can establish from the record
            // alone; that the record is stale is a liveness claim it cannot
            // make (ADR-014: `status` reports configured state, not liveness).
            return "auto-resume overdue since \(deadlineText(until))"
        case .unreadableDeadline:
            return "deadline unreadable — record may be corrupt"
        }
    }

    /// The CLI `status` block as a single string.
    public var cliText: String { cliLines.joined(separator: "\n") }

    /// A one-line, voice-friendly summary for Siri / Shortcuts results.
    public var voiceLine: String {
        let state = isEnabled
            ? "enabled, locking the Dock to the \(lockEdge.displayName.lowercased())"
            : "disabled"
        let current = currentEdge.map { " The Dock is on the \($0.displayName.lowercased())." } ?? ""
        // Pause leads, and suppresses the mechanism tail: asked out loud whether
        // DockKeeper is on, "enabled" alone is the wrong answer while it is
        // deliberately not correcting anything (#36).
        //
        // Gated on `isEnabled` since #47. The pause branch used to return before
        // `state` was ever read, so a record left by an untrappable exit and a
        // later `dockkeeper unlock` made Siri answer "DockKeeper is paused" for
        // an install that is simply off. #36's rule is untouched: it forbids
        // "enabled" standing alone *while paused*, and a disabled install never
        // says "enabled" — "disabled" is itself an honest "not correcting
        // anything", and a more actionable one than inviting the user to resume
        // a pause that no longer governs.
        if isEnabled {
            switch pauseReading {
            case .notPaused:
                break
            case .untimed:
                return "DockKeeper is paused, so it is not correcting the Dock right now.\(current)"
            case .timed(let until):
                return "DockKeeper is paused until \(deadlineText(until)), "
                    + "so it is not correcting the Dock right now.\(current)"
            case .overdue(let until):
                // Must not fall through to the enabled line: a record is
                // present, and answering "DockKeeper is enabled" out loud would
                // be the #36 defect again. Says the deadline passed, not that
                // the app died — see `PauseReading.overdue`.
                return "DockKeeper is paused, and its auto-resume deadline of "
                    + "\(deadlineText(until)) has already passed.\(current)"
            case .unreadableDeadline:
                // Distinct from the untimed line on purpose. Folding the two
                // together would speak an unreadable record as a plain live
                // pause, asserting a deadline nothing could read.
                return "DockKeeper is paused, but its auto-resume deadline is unreadable.\(current)"
            }
        }
        return "DockKeeper is \(state).\(current) Mechanism: \(mechanism)."
    }
}
