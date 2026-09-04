import Foundation

/// Renders a `LiveGuardReading` for `dockkeeper status --live` and for the
/// `--diagnostics` report (DK-FR-015).
///
/// **Re-derivation is foreclosed by the signature, not by discipline.** Every
/// entry point takes a reading, three plain disk values and a clock, and has no
/// handle on `Settings`, `DockController`, `CoreDock`, `DisplayManager` or
/// `BottomDockGuard.decide`. So the acceptance criterion "never silently falling
/// back to re-derivation" is not a property someone has to keep remembering
/// during review — there is nothing in scope to re-derive *from*. That is a
/// deliberately stronger guarantee than a test of the same property, because a
/// test can be deleted and a missing dependency cannot be forgotten.
///
/// Ages are relative, never wall clocks, matching `--diagnostics` (DK-PRIV-001
/// S2). Unlike `status`, this block is designed to be pasted into an issue.
public enum LiveGuardReport {

    /// Exit codes, so release-checklist §6 can gate on this rather than read it.
    ///
    /// `0` means one specific thing — a live instance was found *and* its
    /// settings agree with the disk — because a gate that passes on "live but
    /// contradicting the disk" would pass on the exact condition #78 was filed
    /// about.
    /// `CaseIterable` so a test can assert the whole set at once — specifically
    /// that nothing here collides with `1` (`EXIT_FAILURE`, which the CLI already
    /// uses for a usage error) or with `2`, the shell's own usage convention.
    public enum Status: Int32, Sendable, Equatable, CaseIterable {
        case liveAndConsistent = 0
        case noLiveState = 3
        case writerGone = 4
        case unreadable = 5
        case liveButDiverging = 6
    }

    // MARK: - Entry points

    /// The `dockkeeper status --live` block, in order.
    public static func cliLines(
        for reading: LiveGuardReading,
        onDisk: DiskSettings,
        instances: [ObservedInstance],
        now: Date
    ) -> [String] {
        var lines = ["DockKeeper live state", "---------------------"]
        switch reading {
        case .live(let record):
            lines.append(contentsOf: liveLines(record, onDisk: onDisk, instances: instances, now: now))
        default:
            lines.append(contentsOf: notLiveLines(reading, instances: instances, now: now))
        }
        return lines
    }

    /// The status a caller should exit with.
    public static func status(
        for reading: LiveGuardReading,
        onDisk: DiskSettings
    ) -> Status {
        switch reading {
        case .live(let record):
            // A record that contradicts itself fails the gate too. Without this
            // the release check exits 0 on "the decision says guarding" beside
            // "no tap is armed" — which is #77 exactly, and #77 is one of the
            // two bugs this instrument exists to make impossible to miss.
            return divergences(record.held, onDisk).isEmpty && record.selfContradictions.isEmpty
                ? .liveAndConsistent
                : .liveButDiverging
        case .noRecord:
            return .noLiveState
        case .writerGone, .writerReplaced, .otherUser:
            return .writerGone
        case .unreadable, .futureSchema:
            return .unreadable
        }
    }

    /// One line for the `--diagnostics` report's `Live state:` row.
    ///
    /// The report's other rows all re-derive, so this row's whole job is to say
    /// whether the running instance agrees with them. It leads with the
    /// disagreement when there is one, because a support reader scanning
    /// thirteen aligned rows will read the *value* and not the label, and the
    /// value that matters is "these two do not match".
    public static func diagnosticsLine(
        for reading: LiveGuardReading,
        onDisk: DiskSettings,
        derived: DerivedObservation,
        now: Date
    ) -> String {
        switch reading {
        case .live(let record):
            let diffs = divergences(record.held, onDisk)
                + derivedDivergences(record, derived)
                + record.selfContradictions
            let age = age(from: record.observedAt, to: now)
            guard !diffs.isEmpty else {
                return "live — pid \(record.writer.pid) agrees with every row above (read \(age))"
            }
            // The rows above this one were re-derived from disk and from *this*
            // process's view of the Accessibility grant. Saying so here is the
            // difference between a report that contradicts itself and one that
            // explains why.
            return "**DIVERGES** — pid \(record.writer.pid): \(diffs.joined(separator: "; "))"
                + "; the rows above are re-derived and the running app's values are what act (read \(age))"
        case .noRecord:
            return "none published — no instance is running, or it predates this feature"
        case .unreadable(let reason):
            return "unreadable (\(reason)) — the rows above are re-derived and unverified"
        case .futureSchema(let found, let expected):
            return "published by a newer DockKeeper (schema \(found), this reader knows \(expected))"
        case .writerGone(let pid, let observedAt):
            return "stale — pid \(pid) published \(age(from: observedAt, to: now)) and is no longer running"
                + "; it was killed rather than quit"
        case .writerReplaced(let pid, let observedAt):
            return "stale — pid \(pid) published \(age(from: observedAt, to: now)) and that pid now belongs to another process"
        case .otherUser(let pid, let uid):
            return "published by another user's DockKeeper (pid \(pid), uid \(uid)); not this session's state"
        }
    }

    /// What the *reporting* process re-derived, for comparison against what the
    /// running instance published.
    ///
    /// Passed in rather than computed, so this type still cannot re-derive
    /// anything: it is handed two observations and asked whether they agree,
    /// which is a different act from producing one of them.
    public struct DerivedObservation: Equatable, Sendable {
        public let accessibilityTrusted: Bool
        public let decision: BottomDockGuard.Decision

        public init(accessibilityTrusted: Bool, decision: BottomDockGuard.Decision) {
            self.accessibilityTrusted = accessibilityTrusted
            self.decision = decision
        }
    }

    /// Where the running instance and the re-deriving process disagree about
    /// something that is not a setting.
    ///
    /// This is the #77 comparison, and it is the one a settings check cannot
    /// make. In #77 the settings agreed perfectly on both sides; what differed
    /// was the Accessibility answer — TCC resolves `AXIsProcessTrusted()` for
    /// the *responsible* process, so a report run from a granted Terminal got
    /// `true` for the Terminal while the app had no grant at all — and the
    /// verdict that followed from it. Comparing only settings would have printed
    /// "agrees" underneath the wrong row, adding false corroboration to the
    /// exact failure this feature was built to expose.
    private static func derivedDivergences(
        _ record: LiveGuardRecord,
        _ derived: DerivedObservation
    ) -> [String] {
        var out: [String] = []
        if record.accessibilityTrusted != derived.accessibilityTrusted {
            out.append(
                "Accessibility: app sees \(record.accessibilityTrusted ? "granted" : "NOT granted"),"
                    + " this report sees \(derived.accessibilityTrusted ? "granted" : "NOT granted")"
                    + " — TCC answers for the process that asks, so the app's is the one that governs the tap"
            )
        }
        let derivedKind: LiveGuardRecord.DecisionRecord.Kind
        switch derived.decision {
        case .idle: derivedKind = .idle
        case .guarding: derivedKind = .guarding
        }
        if record.decision.kind != derivedKind {
            out.append(
                "verdict: app is \(record.decision.kind.rawValue), this report re-derived \(derivedKind.rawValue)"
            )
        }
        return out
    }

    // MARK: - The live block

    private static func liveLines(
        _ record: LiveGuardRecord,
        onDisk: DiskSettings,
        instances: [ObservedInstance],
        now: Date
    ) -> [String] {
        var lines: [String] = []
        let version = record.appVersion.map { "DockKeeper \($0)" } ?? "version unknown (running unbundled)"
        lines.append(row("Live:", "yes — pid \(record.writer.pid), \(version)"))
        lines.append(row("Bundle:", record.bundlePath ?? "unknown (running unbundled)"))
        lines.append(row(
            "Observed:",
            "\(age(from: record.observedAt, to: now)); unchanged for \(age(from: record.stateChangedAt, to: now, suffix: ""))"
        ))
        lines.append(row(
            "Accessibility:",
            record.accessibilityTrusted
                ? "granted, as the running app sees it"
                : "NOT granted, as the running app sees it"
        ))
        lines.append(row("Held:", heldText(record.held)))
        lines.append(row("Guard:", guardText(record.decision)))
        lines.append(row("Tap:", tapText(record.tap, now: now)))
        lines.append(contentsOf: divergenceRows(record.held, onDisk))
        for contradiction in record.selfContradictions {
            // Louder than a divergence, because it needs no second opinion: the
            // record disagrees with itself, so one of its own fields is wrong
            // whatever the disk says.
            lines.append(row("Warning:", contradiction))
        }
        // Only when there is more than one, so the common case stays quiet. With
        // several publishers sharing one key the record is whichever wrote last,
        // and presenting it as *the* state would be the single-answer lie this
        // block is otherwise built to avoid.
        if instances.count > 1 {
            lines.append(row("Note:", "\(instances.count) instances are running and share one record;"))
            lines.append(row("", "what is shown above is whichever published most recently."))
            lines.append(contentsOf: instanceRows(instances))
        }
        return lines
    }

    /// The `Guard:` value.
    ///
    /// The guarding case is rendered by `BottomDockGuard.diagnosticsLine`, the
    /// function that already knows a display and a span are different units
    /// (#83). A parallel renderer here would have to learn that lesson again,
    /// and the first thing it would get wrong is the thing that lesson is about.
    ///
    /// `paused: false` is passed unconditionally and that is correct rather than
    /// a shortcut: pause suspends *corrections*, and the guard is prevention
    /// with nothing to resume (DK-FR-014 Known cost, #62). The pause qualifier
    /// exists on `--diagnostics` because a `Paused:` row sits directly beneath
    /// it there and the pair reads as a contradiction; this block has no such
    /// row, and a pause state is not published here at all — it does not pass
    /// through the funnel that writes this record, so claiming it would be the
    /// one field in the block that could go stale.
    private static func guardText(_ decision: LiveGuardRecord.DecisionRecord) -> String {
        guard let live = decision.guardingDecision else {
            return decision.idleExplanation ?? "idle (reason not recorded)"
        }
        return BottomDockGuard.diagnosticsLine(for: live, paused: false)
    }

    private static func tapText(_ tap: LiveGuardRecord.TapRecord?, now: Date) -> String {
        guard let tap else {
            // Counters are unreachable in this branch by construction — see
            // `LiveGuardRecord.tap`. They reset only when a tap arms and never
            // when one is released, so a released tap still holds the previous
            // run's totals, and printing them here is exactly the stale-figure-
            // as-live reading the optional exists to make impossible.
            return "not armed"
        }
        let filtering = tap.systemEnabled
            ? "filtering"
            : "NOT filtering — macOS has the tap disabled"
        return "armed \(age(from: tap.armedAt, to: now)) over \(tap.installedZoneCount) span(s), \(filtering)"
            + "; \(tap.clampCount) clamp(s), \(tap.reenableCount) re-enable(s) since it armed"
    }

    private static func heldText(_ held: LiveGuardRecord.HeldSettings) -> String {
        "enabled=\(held.isEnabled ? "yes" : "no")"
            + " edge=\(held.lockEdge.displayName)"
            + " bottom-guard=\(held.lockBottomDockToDisplay ? "on" : "off")"
    }

    // MARK: - Divergence

    /// The whole reason this feature exists, in one row.
    ///
    /// Both historical false verdicts were a divergence between what the running
    /// app held and what the disk said, and neither surface could see both
    /// halves at once. This row sees both.
    private static func divergenceRows(
        _ held: LiveGuardRecord.HeldSettings,
        _ onDisk: DiskSettings
    ) -> [String] {
        let diffs = divergences(held, onDisk)
        guard !diffs.isEmpty else {
            return [row("Divergence:", "none — the running app and this machine's settings agree")]
        }
        var lines = [row("Divergence:", diffs.joined(separator: "; "))]
        // Naming *which side acts* is the actionable half. Without it the reader
        // knows the two disagree and still cannot predict what the pointer will
        // do, which is the position the on-device sessions were already in.
        //
        // The advice is per-field rather than a blanket sentence, because the two
        // kinds of key fail differently and a single sentence has to be wrong
        // about one of them. An unwatched key genuinely cannot reach a running
        // app, so the app's value stays in force and that is working as designed.
        // A watched key should have arrived, so a disagreement there is not an
        // explanation — it is a second symptom.
        lines.append(row("", "The running app's values are the ones in force."))
        if unwatchedKeysDiverge(held, onDisk) {
            lines.append(row("", "An external `defaults write` to the bottom-guard key never reaches a"))
            lines.append(row("", "running app — it is not in the watched set — so this is expected."))
        }
        if watchedKeysDiverge(held, onDisk) {
            lines.append(row("", "The edge and enabled keys ARE watched for external edits, so a"))
            lines.append(row("", "disagreement there means the app has not processed the change."))
        }
        return lines
    }

    /// Whether a divergent field is one an external write can never deliver.
    /// `lockBottomDockToDisplay` is absent from `Settings.externallyObservedKeys`,
    /// which is the whole mechanism behind the false negative that motivated this.
    private static func unwatchedKeysDiverge(
        _ held: LiveGuardRecord.HeldSettings, _ onDisk: DiskSettings
    ) -> Bool {
        held.lockBottomDockToDisplay != onDisk.lockBottomDockToDisplay
    }

    private static func watchedKeysDiverge(
        _ held: LiveGuardRecord.HeldSettings, _ onDisk: DiskSettings
    ) -> Bool {
        held.isEnabled != onDisk.isEnabled || held.lockEdge != onDisk.lockEdge
    }

    /// Each field the running app and the disk disagree about, as a phrase.
    private static func divergences(
        _ held: LiveGuardRecord.HeldSettings,
        _ onDisk: DiskSettings
    ) -> [String] {
        var out: [String] = []
        if held.isEnabled != onDisk.isEnabled {
            out.append("enabled: app=\(held.isEnabled ? "yes" : "no") disk=\(onDisk.isEnabled ? "yes" : "no")")
        }
        if held.lockEdge != onDisk.lockEdge {
            out.append("edge: app=\(held.lockEdge.displayName) disk=\(onDisk.lockEdge.displayName)")
        }
        if held.lockBottomDockToDisplay != onDisk.lockBottomDockToDisplay {
            out.append(
                "bottom-guard: app=\(held.lockBottomDockToDisplay ? "on" : "off")"
                    + " disk=\(onDisk.lockBottomDockToDisplay ? "on" : "off")"
            )
        }
        return out
    }

    // MARK: - The not-live block

    private static func notLiveLines(
        _ reading: LiveGuardReading,
        instances: [ObservedInstance],
        now: Date
    ) -> [String] {
        var lines: [String] = []
        switch reading {
        case .live:
            return []
        case .noRecord:
            if instances.isEmpty {
                lines.append(row("Live:", "no — no DockKeeper instance is running"))
            } else {
                // Both halves are true and they are not the same claim. Saying
                // only "no" here would be the acceptance criterion's forbidden
                // answer wearing an honest word.
                lines.append(row("Live:", "no — an instance is running but has published no live state"))
                lines.append(contentsOf: instanceRows(instances))
                lines.append(row("Note:", "It may predate this feature. Quit and relaunch it to publish."))
            }
        case .unreadable(let reason):
            lines.append(row("Live:", "no — the published record could not be read (\(reason))"))
        case .futureSchema(let found, let expected):
            lines.append(row("Live:", "no — the record was published by a newer DockKeeper"))
            lines.append(row("Note:", "Record schema \(found); this `dockkeeper` understands \(expected). Update the CLI."))
        case .writerGone(let pid, let observedAt):
            lines.append(row("Live:", "no — the record names pid \(pid), which is not running"))
            lines.append(row("Observed:", "\(age(from: observedAt, to: now)), by the process that has since died"))
            // This is a positive signal, not merely an absence: a clean quit
            // removes the record, so finding one whose writer is gone means the
            // writer died by a route that skipped its own cleanup.
            lines.append(row("Note:", "DockKeeper removes this record when it quits, so it was killed"))
            lines.append(row("", "rather than quit — a crash, Force Quit, `kill -9`, or a logout."))
            lines.append(contentsOf: instanceRows(instances))
        case .writerReplaced(let pid, let observedAt):
            lines.append(row("Live:", "no — pid \(pid) now belongs to an unrelated process"))
            lines.append(row("Observed:", "\(age(from: observedAt, to: now)), by the original process"))
            lines.append(contentsOf: instanceRows(instances))
        case .otherUser(let pid, let uid):
            lines.append(row("Live:", "no — the record belongs to another user's DockKeeper"))
            lines.append(row("Note:", "Published by pid \(pid) running as uid \(uid). Under fast user"))
            lines.append(row("", "switching that is a different Dock, not this session's state."))
        }
        // Stated once, in every not-live branch, because the acceptance
        // criterion this satisfies is a *negative* one and a reader cannot
        // verify an absence they were not told about.
        lines.append(row("Note:", "No guard state is shown above. Nothing here is re-derived."))
        return lines
    }

    private static func instanceRows(_ instances: [ObservedInstance]) -> [String] {
        instances.map { instance in
            let version = instance.version.map { " \($0)" } ?? ""
            return row("Running:", "pid \(instance.pid)\(version) at \(instance.bundlePath ?? "unknown path")")
        }
    }

    // MARK: - Formatting

    /// Label column is 15 characters wide; values start at column 16.
    ///
    /// 15 rather than 14 because `Accessibility:` is itself 14 characters, and
    /// a field exactly as wide as its longest label leaves that one row with no
    /// separating space — every other value would sit one column to its right.
    /// The overflow branch below is kept for a label longer still, where a
    /// single space is the most that can be offered without moving the column
    /// for everyone.
    ///
    /// An empty label produces a pure continuation line, which is how the
    /// multi-line notes stay aligned under their own row.
    private static func row(_ label: String, _ value: String) -> String {
        let width = 15
        let padded = label.count >= width
            ? label + " "
            : label + String(repeating: " ", count: width - label.count)
        return padded + value
    }

    /// A relative age. Never a wall clock (DK-PRIV-001 S2).
    ///
    /// Every date here is decoded from a user-writable defaults domain, so the
    /// conversion goes through `DisplayDuration.wholeSeconds` for the same
    /// reason `--diagnostics` does: `Int(_: Double)` traps on a
    /// decodable-but-absurd stamp, and a support command that crashes is worse
    /// than one that says "unreadable".
    ///
    /// A negative age is reported as such rather than rendered as a huge
    /// positive one. It means the record is stamped in this machine's future —
    /// a clock step or an edited record — and quietly showing "0s" would hide
    /// the one fact that explains everything else on the screen.
    static func age(from date: Date, to now: Date, suffix: String = " ago") -> String {
        // The suffix is dropped on both error branches on purpose: "an
        // unreadable time ago" and "an unreadable time" would need different
        // wording anyway, and appending " ago" to a future stamp would contradict
        // the sentence it is attached to. Every branch reads correctly in both
        // the "N ago" and the "unchanged for N" position.
        guard let seconds = DisplayDuration.wholeSeconds(now.timeIntervalSince(date)) else {
            return "an unreadable length of time — the record may be corrupt"
        }
        if seconds < 0 {
            return "a time stamped \(compact(-seconds)) in the future — check this machine's clock"
        }
        return compact(seconds) + suffix
    }

    /// Whole seconds as a short, locale-independent, deterministic string.
    private static func compact(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}
