import CoreGraphics
import Foundation
import Testing

@testable import DockKeeperCore

// Asking a running DockKeeper what it is actually doing (DK-FR-015) ----------
//
// Coverage for the record a live instance publishes, the classification that
// decides whether a reader may believe it, and the two renderings built on top.
//
// The requirement exists because every other guard surface re-derives, and twice
// a re-derivation contradicted the running app while sounding certain — once
// claiming `guarding 1 display(s)` with no tap armed (#77), once claiming the
// feature was off while the tap was clamping the pointer. So the assertions here
// are weighted towards the *negative* properties, which are the ones that make an
// instrument trustworthy:
//
// 1. **No not-live verdict may render guard state.** That is enforced by the
//    type — only `.live` carries a record — and asserted anyway, because the
//    type could be widened by someone who did not know why it was narrow.
// 2. **Liveness never consults a clock.** Every classification case below fixes
//    `observedAt` at a stamp far from any plausible "now" and still expects the
//    verdict to turn purely on the injected process table.
// 3. **Whole lines, not substrings.** A `contains` check passes just as happily
//    when a line has been appended to the wrong branch.

private let anchor = Date(timeIntervalSince1970: 1_756_000_000)   // 2025-08-24T01:46:40Z UTC

private func identity(pid: pid_t = 4242, started: Int64 = 111_222_333, uid: uid_t = 501) -> ProcessIdentity {
    ProcessIdentity(pid: pid, startedAtMicroseconds: started, uid: uid)
}

private func held(
    enabled: Bool = true,
    edge: DockOrientation = .bottom,
    bottomGuard: Bool = true
) -> LiveGuardRecord.HeldSettings {
    LiveGuardRecord.HeldSettings(
        isEnabled: enabled, lockEdge: edge, lockBottomDockToDisplay: bottomGuard
    )
}

private func disk(
    enabled: Bool = true,
    edge: DockOrientation = .bottom,
    bottomGuard: Bool = true
) -> DiskSettings {
    DiskSettings(isEnabled: enabled, lockEdge: edge, lockBottomDockToDisplay: bottomGuard)
}

/// A zone over a display whose bottom edge is at `y = 0`, so `clampY` is `-3` —
/// the negative-`clampY` rig the on-device session actually measured, kept
/// because every sanity rule carried over from a positive-`y` arrangement
/// inverts on it.
private func zone(_ id: CGDirectDisplayID = 7) -> BottomDockGuard.ClampZone {
    BottomDockGuard.ClampZone(
        displayID: id, frame: CGRect(x: 1728, y: -1178, width: 2112, height: 1178)
    )
}

private func record(
    writer: ProcessIdentity = identity(),
    version: String? = "0.9.5",
    bundlePath: String? = "/Applications/DockKeeper.app",
    observedAt: Date = anchor,
    stateChangedAt: Date = anchor,
    settings: LiveGuardRecord.HeldSettings = held(),
    accessibility: Bool = true,
    decision: BottomDockGuard.Decision = .idle(.featureDisabled),
    tap: LiveGuardRecord.TapRecord? = nil
) -> LiveGuardRecord {
    LiveGuardRecord(
        writer: writer,
        appVersion: version,
        bundlePath: bundlePath,
        observedAt: observedAt,
        stateChangedAt: stateChangedAt,
        held: settings,
        accessibilityTrusted: accessibility,
        decision: LiveGuardRecord.DecisionRecord(decision),
        tap: tap
    )
}

private func vitals(
    armedAt: Date = anchor,
    zones: Int = 2,
    systemEnabled: Bool = true,
    clamps: Int = 1284,
    reenables: Int = 0
) -> LiveGuardRecord.TapRecord {
    LiveGuardRecord.TapRecord(
        armedAt: armedAt,
        installedZoneCount: zones,
        systemEnabled: systemEnabled,
        clampCount: clamps,
        reenableCount: reenables
    )
}

// MARK: -

@Suite("Live guard record wire format")
struct LiveGuardRecordTests {

    @Test("A record survives a JSON round trip unchanged")
    func roundTrip() throws {
        let original = record(
            decision: .guarding(zones: [zone(7), zone(9)], skipped: [3], partiallyGuarded: [7]),
            tap: vitals()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(
            LiveGuardRecord.self, from: try encoder.encode(original)
        )
        #expect(restored == original)
    }

    @Test("An idle decision travels as its rendered sentence, so an older reader can print a reason it has never heard of")
    func idleTravelsAsText() {
        let projected = LiveGuardRecord.DecisionRecord(.idle(.accessibilityNotGranted))
        #expect(projected.kind == .idle)
        #expect(projected.idleExplanation == BottomDockGuard.IdleReason.accessibilityNotGranted.explanation)
        #expect(projected.zones.isEmpty)
        // There is nothing to reconstruct for an idle record, and saying so is
        // the point: the reader prints the sentence and counts nothing.
        #expect(projected.guardingDecision == nil)
    }

    @Test("A guarding decision rebuilds into an equal Decision")
    func guardingRoundTrips() {
        let original = BottomDockGuard.Decision.guarding(
            zones: [zone(7), zone(9)], skipped: [3, 4], partiallyGuarded: [7]
        )
        #expect(LiveGuardRecord.DecisionRecord(original).guardingDecision == original)
    }

    @Test("A rebuilt zone derives clampY from its frame rather than carrying it")
    func zoneDerivesClampY() {
        // The oracle is the arrangement: this display's bottom edge is y = 0 and
        // the guard band is 3, so the band's limit is -3. Asserted as a literal
        // rather than recomputed, because `frame.maxY - guardBand` is the
        // expression under test.
        let rebuilt = LiveGuardRecord.ZoneRecord(zone(7)).clampZone
        #expect(rebuilt.frame.maxY == 0)
        #expect(rebuilt.clampY == -3)
        #expect(rebuilt == zone(7))
    }

    @Test("Counters do not count as a state change, but everything else does")
    func changeGuardSemantics() {
        let base = record(tap: vitals(clamps: 10))
        // A clamp is the guard working, not the state moving. If this compared
        // unequal, `stateChangedAt` would decay into a copy of `observedAt` the
        // moment the pointer touched a guarded band.
        #expect(base.describesSameStateAs(record(tap: vitals(clamps: 99))))
        #expect(base.describesSameStateAs(record(tap: vitals(reenables: 4))))
        // Everything a user or a maintainer would call a state change.
        #expect(!base.describesSameStateAs(record(settings: held(bottomGuard: false), tap: vitals(clamps: 10))))
        #expect(!base.describesSameStateAs(record(accessibility: false, tap: vitals(clamps: 10))))
        #expect(!base.describesSameStateAs(record(decision: .idle(.singleDisplay), tap: vitals(clamps: 10))))
        #expect(!base.describesSameStateAs(record(tap: vitals(zones: 5, clamps: 10))))
        #expect(!base.describesSameStateAs(record(tap: vitals(systemEnabled: false, clamps: 10))))
        #expect(!base.describesSameStateAs(record(tap: vitals(armedAt: anchor.addingTimeInterval(60), clamps: 10))))
        // Arming and releasing are state changes in both directions.
        #expect(!base.describesSameStateAs(record(tap: nil)))
        #expect(!record(tap: nil).describesSameStateAs(base))
    }

    @Test("Carrying a change stamp forward alters only that field")
    func carryForward() {
        let original = record(tap: vitals())
        let carried = original.withStateChangedAt(anchor.addingTimeInterval(-3600))
        #expect(carried.stateChangedAt == anchor.addingTimeInterval(-3600))
        #expect(carried.observedAt == original.observedAt)
        #expect(carried.withStateChangedAt(original.stateChangedAt) == original)
    }
}

// MARK: -

@Suite("Live guard classification (DK-FR-015)")
struct LiveGuardClassificationTests {

    /// A process table with exactly one live process in it.
    private func table(_ live: ProcessIdentity...) -> (pid_t) -> ProcessIdentity? {
        { pid in live.first { $0.pid == pid } }
    }

    @Test("Nothing published reads as no record, never as an unreadable one")
    func absent() {
        #expect(
            LiveGuardReading.classify(stored: .absent, writerIdentityNow: table(), readerUID: 501)
                == .noRecord
        )
    }

    @Test("An undecodable record is reported as unreadable rather than degraded to absent")
    func unreadableIsNotAbsent() {
        // The distinction is the whole reason `StoredLiveGuardRecord` exists.
        // "No instance is publishing" and "an instance published something I
        // could not read" are different claims, and only one of them is true.
        let reading = LiveGuardReading.classify(
            stored: .unreadable("keyNotFound"), writerIdentityNow: table(), readerUID: 501
        )
        #expect(reading == .unreadable("keyNotFound"))
        #expect(reading != .noRecord)
    }

    @Test("A record from a newer schema fails closed, naming both versions")
    func futureSchema() {
        // The envelope is decoded before the payload, so this arrives already
        // classified as a version difference rather than as damage — see
        // `Settings.liveGuardRecord`. The reader's job here is only to say which
        // two versions are involved.
        #expect(
            LiveGuardReading.classify(
                stored: .wrongSchema(found: LiveGuardRecord.currentSchema + 1),
                // The writer's liveness is never even consulted: nothing about a
                // record this reader cannot interpret is safe to evaluate.
                writerIdentityNow: table(identity()),
                readerUID: 501
            ) == .futureSchema(found: LiveGuardRecord.currentSchema + 1, expected: LiveGuardRecord.currentSchema)
        )
    }

    @Test("A live writer with a matching kernel identity reads as live")
    func live() {
        let stored = record()
        #expect(
            LiveGuardReading.classify(
                stored: .present(stored), writerIdentityNow: table(identity()), readerUID: 501
            ) == .live(stored)
        )
    }

    @Test("A writer that is no longer in the process table is gone, however fresh its stamp")
    func writerGone() {
        // `observedAt` is `now` here. A design that inferred liveness from
        // freshness would call this live; this one asks the kernel.
        let stored = record(observedAt: Date())
        #expect(
            LiveGuardReading.classify(
                stored: .present(stored), writerIdentityNow: table(), readerUID: 501
            ) == .writerGone(pid: 4242, observedAt: stored.observedAt)
        )
    }

    @Test("A recycled pid is not the writer, even though the pid is live")
    func pidReuse() {
        // Same pid, later start time — the shape a wrapped pid actually takes.
        let stored = record(writer: identity(started: 111_222_333))
        #expect(
            LiveGuardReading.classify(
                stored: .present(stored),
                writerIdentityNow: table(identity(started: 999_888_777)),
                readerUID: 501
            ) == .writerReplaced(pid: 4242, observedAt: anchor)
        )
    }

    @Test("A single microsecond of difference is enough to reject the writer")
    func startTimeIsExact() {
        // No tolerance, on purpose: a tolerance is a window in which a wrong
        // answer can hide, and the kernel hands the value over in whole
        // microseconds so none is needed.
        let stored = record(writer: identity(started: 111_222_333))
        #expect(
            LiveGuardReading.classify(
                stored: .present(stored),
                writerIdentityNow: table(identity(started: 111_222_334)),
                readerUID: 501
            ) == .writerReplaced(pid: 4242, observedAt: anchor)
        )
    }

    @Test("Another user's DockKeeper is not this session's live state")
    func otherUser() {
        let stored = record()
        #expect(
            LiveGuardReading.classify(
                stored: .present(stored),
                writerIdentityNow: table(identity(uid: 502)),
                readerUID: 501
            ) == .otherUser(pid: 4242, uid: 502)
        )
    }
}

// MARK: -

@Suite("Live guard report rendering")
struct LiveGuardReportTests {

    private func lines(
        _ reading: LiveGuardReading,
        onDisk: DiskSettings = disk(),
        instances: [ObservedInstance] = [],
        now: Date = anchor
    ) -> [String] {
        LiveGuardReport.cliLines(for: reading, onDisk: onDisk, instances: instances, now: now)
    }

    @Test("No not-live verdict prints a single field of guard state")
    func notLiveNeverRendersState() {
        // The acceptance criterion "never silently falling back to
        // re-derivation" is a negative one, so it is asserted negatively — over
        // every not-live case at once, because the one that gets it wrong will
        // be the one added later.
        let notLive: [LiveGuardReading] = [
            .noRecord,
            .unreadable("boom"),
            .futureSchema(found: 9, expected: 1),
            .writerGone(pid: 4242, observedAt: anchor.addingTimeInterval(-90)),
            .writerReplaced(pid: 4242, observedAt: anchor.addingTimeInterval(-90)),
            .otherUser(pid: 4242, uid: 502),
        ]
        for reading in notLive {
            let text = lines(reading).joined(separator: "\n")
            #expect(!text.contains("guarding"))
            #expect(!text.contains("Guard:"))
            #expect(!text.contains("Tap:"))
            #expect(!text.contains("clamp(s)"))
            #expect(!text.contains("Held:"))
            // The five `status` fields, which would be the re-derivation.
            #expect(!text.contains("Enabled:"))
            #expect(!text.contains("Lock edge:"))
            #expect(!text.contains("Dock is on:"))
            #expect(!text.contains("CoreDock:"))
            #expect(text.contains("Nothing here is re-derived."))
        }
    }

    @Test("A live, armed, agreeing instance renders every row")
    func liveBlock() {
        let stored = record(
            observedAt: anchor.addingTimeInterval(-4),
            stateChangedAt: anchor.addingTimeInterval(-725),
            decision: .guarding(zones: [zone(7), zone(9)], skipped: [], partiallyGuarded: []),
            tap: vitals(armedAt: anchor.addingTimeInterval(-725))
        )
        #expect(lines(.live(stored)) == [
            "DockKeeper live state",
            "---------------------",
            "Live:          yes — pid 4242, DockKeeper 0.9.5",
            "Bundle:        /Applications/DockKeeper.app",
            "Observed:      4s ago; unchanged for 12m 5s",
            "Accessibility: granted, as the running app sees it",
            "Held:          enabled=yes edge=Bottom bottom-guard=on",
            "Guard:         guarding 2 display(s) over 2 span(s)",
            "Tap:           armed 12m 5s ago over 2 span(s), filtering; 1284 clamp(s), 0 re-enable(s) since it armed",
            "Divergence:    none — the running app and this machine's settings agree",
        ])
    }

    @Test("The motivating divergence is named, and so is which side acts")
    func divergenceIsTheHeadline() {
        // The exact shape of the false negative: an external `defaults write`
        // turned the feature off on disk, the running app never observed it
        // because the key is not in `externallyObservedKeys`, and the tap kept
        // clamping. Before this line nothing could see both halves at once.
        let stored = record(
            settings: held(bottomGuard: true),
            decision: .guarding(zones: [zone(7)], skipped: [], partiallyGuarded: []),
            tap: vitals(zones: 1)
        )
        let rendered = lines(.live(stored), onDisk: disk(bottomGuard: false))
        #expect(rendered.contains("Divergence:    bottom-guard: app=on disk=off"))
        #expect(rendered.contains("               The running app's values are the ones in force."))
        #expect(rendered.contains("               An external `defaults write` to the bottom-guard key never reaches a"))
        #expect(rendered.contains("               running app — it is not in the watched set — so this is expected."))
    }

    @Test("Every divergent field is named, not just the first")
    func allDivergencesNamed() {
        let stored = record(settings: held(enabled: true, edge: .bottom, bottomGuard: true))
        let rendered = lines(
            .live(stored), onDisk: disk(enabled: false, edge: .left, bottomGuard: false)
        )
        #expect(rendered.contains(
            "Divergence:    enabled: app=yes disk=no; edge: app=Bottom disk=Left; bottom-guard: app=on disk=off"
        ))
    }

    @Test("A released tap publishes no counters, so the previous arming's total cannot be read as live")
    func releasedTapHasNoCounters() {
        // `clampCount` is reset in `start()` and never in `stop()`, so a
        // released tap still holds the last run's figure. The record makes it
        // unreachable rather than merely unwise to print.
        let rendered = lines(.live(record(tap: nil)))
        #expect(rendered.contains("Tap:           not armed"))
        #expect(!rendered.joined().contains("clamp(s)"))
    }

    @Test("A tap macOS has disabled is reported as armed and not filtering")
    func armedButNotFiltering() {
        // The state nothing in the codebase could see before: `isActive` is
        // `tap != nil`, so between a timeout-disable and the next event the
        // guard looks armed and is filtering nothing.
        let rendered = lines(.live(record(
            observedAt: anchor, stateChangedAt: anchor,
            tap: vitals(armedAt: anchor.addingTimeInterval(-30), systemEnabled: false, clamps: 12, reenables: 3)
        )))
        #expect(rendered.contains(
            "Tap:           armed 30s ago over 2 span(s), NOT filtering — macOS has the tap disabled;"
                + " 12 clamp(s), 3 re-enable(s) since it armed"
        ))
    }

    @Test("A surviving record whose writer is gone is reported as a kill, not merely as stale")
    func writerGoneIsACrashSignal() {
        // A clean quit retracts the record, so finding one is positive evidence
        // about *how* the process died — the only crash signal this app has.
        let rendered = lines(.writerGone(pid: 4242, observedAt: anchor.addingTimeInterval(-7325)))
        #expect(rendered.contains("Live:          no — the record names pid 4242, which is not running"))
        #expect(rendered.contains("Observed:      2h 2m ago, by the process that has since died"))
        #expect(rendered.contains("Note:          DockKeeper removes this record when it quits, so it was killed"))
        #expect(rendered.contains("               rather than quit — a crash, Force Quit, `kill -9`, or a logout."))
    }

    @Test("A running instance that has published nothing is distinguished from no instance at all")
    func runningButSilent() {
        // Saying only "no instance is running" here would be the acceptance
        // criterion's forbidden answer wearing an honest word.
        #expect(lines(.noRecord).contains("Live:          no — no DockKeeper instance is running"))

        let withInstance = lines(
            .noRecord,
            instances: [ObservedInstance(pid: 28571, bundlePath: "/Applications/DockKeeper.app", version: "0.9.4")]
        )
        #expect(withInstance.contains("Live:          no — an instance is running but has published no live state"))
        #expect(withInstance.contains("Running:       pid 28571 0.9.4 at /Applications/DockKeeper.app"))
        #expect(withInstance.contains("Note:          It may predate this feature. Quit and relaunch it to publish."))
    }

    @Test("An unbundled instance is reported as such rather than given a plausible wrong path")
    func unbundled() {
        let rendered = lines(.live(record(version: nil, bundlePath: nil)))
        #expect(rendered.contains("Live:          yes — pid 4242, version unknown (running unbundled)"))
        #expect(rendered.contains("Bundle:        unknown (running unbundled)"))
    }

    @Test("Exit codes gate on live AND consistent, so a divergence cannot pass a release check")
    func exitCodes() {
        let agreeing = record()
        #expect(LiveGuardReport.status(for: .live(agreeing), onDisk: disk()) == .liveAndConsistent)
        #expect(LiveGuardReport.status(for: .live(agreeing), onDisk: disk(bottomGuard: false)) == .liveButDiverging)
        #expect(LiveGuardReport.status(for: .noRecord, onDisk: disk()) == .noLiveState)
        #expect(LiveGuardReport.status(for: .writerGone(pid: 1, observedAt: anchor), onDisk: disk()) == .writerGone)
        #expect(LiveGuardReport.status(for: .unreadable("x"), onDisk: disk()) == .unreadable)
        #expect(LiveGuardReport.status(for: .futureSchema(found: 2, expected: 1), onDisk: disk()) == .unreadable)
        // Nothing but a live, agreeing instance may exit 0.
        #expect(LiveGuardReport.Status.liveAndConsistent.rawValue == 0)
    }

    @Test("An absurd-but-decodable stamp renders as unreadable rather than trapping")
    func absurdStampDoesNotTrap() {
        // `Int(_: Double)` traps on a value out of range, and every date here
        // comes from a user-writable defaults domain — the exact exposure that
        // once crashed `--diagnostics`.
        let absurd = Date(timeIntervalSince1970: 1e300)
        #expect(LiveGuardReport.age(from: absurd, to: anchor)
            == "an unreadable length of time — the record may be corrupt")
    }

    @Test("A stamp in the future is called out rather than shown as zero")
    func futureStamp() {
        // Rendering this as "0s ago" would hide a clock step, which is the one
        // fact that explains everything else on the screen.
        #expect(LiveGuardReport.age(from: anchor.addingTimeInterval(90), to: anchor)
            == "a time stamped 1m 30s in the future — check this machine's clock")
    }

    @Test("The --diagnostics row leads with the disagreement when there is one")
    func diagnosticsRow() {
        let stored = record(observedAt: anchor.addingTimeInterval(-4))
        let agreeing = LiveGuardReport.DerivedObservation(
            accessibilityTrusted: true, decision: .idle(.featureDisabled)
        )
        #expect(
            LiveGuardReport.diagnosticsLine(
                for: .live(stored), onDisk: disk(), derived: agreeing, now: anchor
            ) == "live — pid 4242 agrees with every row above (read 4s ago)"
        )
        #expect(
            LiveGuardReport.diagnosticsLine(
                for: .live(stored), onDisk: disk(bottomGuard: false), derived: agreeing, now: anchor
            ) == "**DIVERGES** — pid 4242: bottom-guard: app=on disk=off; the rows above are"
                + " re-derived and the running app's values are what act (read 4s ago)"
        )
        #expect(
            LiveGuardReport.diagnosticsLine(
                for: .noRecord, onDisk: disk(), derived: agreeing, now: anchor
            ) == "none published — no instance is running, or it predates this feature"
        )
    }

    @Test("The --diagnostics row catches #77: identical settings, opposite permission and verdict")
    func diagnosticsRowCatchesTheAccessibilityDivergence() {
        // #77's exact shape, and the case a settings-only comparison misses
        // entirely. The app has no grant, so it decided idle and armed nothing.
        // The report runs from a Terminal that *does* hold the grant, so TCC
        // answers `true` for it and it re-derives `guarding`. Every setting
        // matches on both sides. A row that compared only settings would print
        // "agrees" directly beneath a guarding claim for a tap that never armed
        // — adding false corroboration to the failure it exists to expose.
        let appSees = record(
            observedAt: anchor,
            accessibility: false,
            decision: .idle(.accessibilityNotGranted),
            tap: nil
        )
        let reportSees = LiveGuardReport.DerivedObservation(
            accessibilityTrusted: true,
            decision: .guarding(zones: [zone(7)], skipped: [], partiallyGuarded: [])
        )
        let line = LiveGuardReport.diagnosticsLine(
            for: .live(appSees), onDisk: disk(), derived: reportSees, now: anchor
        )
        #expect(line.hasPrefix("**DIVERGES**"))
        #expect(line.contains(
            "Accessibility: app sees NOT granted, this report sees granted"
                + " — TCC answers for the process that asks, so the app's is the one that governs the tap"
        ))
        #expect(line.contains("verdict: app is idle, this report re-derived guarding"))
    }

    @Test("A record that contradicts itself says so, and fails the gate")
    func selfContradiction() {
        // Reachable from the record alone, with nothing to compare against:
        // "guarding" beside no armed tap is #77 stated by the app itself.
        let guardingWithNoTap = record(
            decision: .guarding(zones: [zone(7)], skipped: [], partiallyGuarded: []), tap: nil
        )
        #expect(guardingWithNoTap.selfContradictions == ["the decision says guarding but no tap is armed"])
        #expect(LiveGuardReport.status(for: .live(guardingWithNoTap), onDisk: disk()) == .liveButDiverging)
        #expect(lines(.live(guardingWithNoTap))
            .contains("Warning:       the decision says guarding but no tap is armed"))

        let disabledByOS = record(
            decision: .guarding(zones: [zone(7)], skipped: [], partiallyGuarded: []),
            tap: vitals(zones: 1, systemEnabled: false)
        )
        #expect(disabledByOS.selfContradictions
            == ["the tap is armed but macOS has disabled it, so nothing is being filtered"])
        #expect(LiveGuardReport.status(for: .live(disabledByOS), onDisk: disk()) == .liveButDiverging)

        let zoneMismatch = record(
            decision: .guarding(zones: [zone(7), zone(9)], skipped: [], partiallyGuarded: []),
            tap: vitals(zones: 1)
        )
        #expect(zoneMismatch.selfContradictions == ["the tap holds 1 span(s) but the decision names 2"])

        let idleWithTap = record(decision: .idle(.featureDisabled), tap: vitals())
        #expect(idleWithTap.selfContradictions.contains("the decision is idle but a tap is still armed"))

        // The healthy shapes say nothing.
        #expect(record(tap: nil).selfContradictions.isEmpty)
        #expect(record(
            decision: .guarding(zones: [zone(7)], skipped: [], partiallyGuarded: []),
            tap: vitals(zones: 1)
        ).selfContradictions.isEmpty)
    }

    @Test("Divergence advice is per-field, so it cannot contradict the divergence it explains")
    func adviceIsPerField() {
        // A blanket "a defaults write reaches a running app only for enabled,
        // lockEdge, ..." is self-contradicting when the divergent field IS
        // `enabled`: it names the key on both sides of its own sentence.
        let unwatched = lines(.live(record(settings: held(bottomGuard: true))), onDisk: disk(bottomGuard: false))
        #expect(unwatched.contains("               An external `defaults write` to the bottom-guard key never reaches a"))
        #expect(!unwatched.contains("               The edge and enabled keys ARE watched for external edits, so a"))

        let watched = lines(.live(record(settings: held(enabled: true))), onDisk: disk(enabled: false))
        #expect(watched.contains("               The edge and enabled keys ARE watched for external edits, so a"))
        #expect(!watched.contains("               An external `defaults write` to the bottom-guard key never reaches a"))
    }

    @Test("Several live publishers are named rather than one being presented as the truth")
    func multipleInstances() {
        let two = [
            ObservedInstance(pid: 100, bundlePath: "/Applications/DockKeeper.app", version: "0.9.5"),
            ObservedInstance(pid: 200, bundlePath: "/tmp/build/DockKeeper.app", version: "0.9.6"),
        ]
        let rendered = lines(.live(record()), instances: two)
        #expect(rendered.contains("Note:          2 instances are running and share one record;"))
        #expect(rendered.contains("               what is shown above is whichever published most recently."))
        #expect(rendered.contains("Running:       pid 200 0.9.6 at /tmp/build/DockKeeper.app"))
        // The common case stays quiet.
        #expect(!lines(.live(record()), instances: [two[0]]).contains(where: { $0.hasPrefix("Running:") }))
    }

    @Test("An age reads correctly in the 'unchanged for' position too")
    func suffixlessAges() {
        // These render after "unchanged for", where a trailing " ago" would make
        // the sentence contradict itself.
        #expect(LiveGuardReport.age(from: anchor.addingTimeInterval(-90), to: anchor, suffix: "") == "1m 30s")
        #expect(LiveGuardReport.age(from: Date(timeIntervalSince1970: 1e300), to: anchor, suffix: "")
            == "an unreadable length of time — the record may be corrupt")
        #expect(LiveGuardReport.age(from: anchor.addingTimeInterval(90), to: anchor, suffix: "")
            == "a time stamped 1m 30s in the future — check this machine's clock")
    }

    @Test("The compact age crosses both of its unit boundaries")
    func ageUnitBoundaries() {
        #expect(LiveGuardReport.age(from: anchor.addingTimeInterval(-59), to: anchor) == "59s ago")
        #expect(LiveGuardReport.age(from: anchor.addingTimeInterval(-60), to: anchor) == "1m 0s ago")
        #expect(LiveGuardReport.age(from: anchor.addingTimeInterval(-3599), to: anchor) == "59m 59s ago")
        #expect(LiveGuardReport.age(from: anchor.addingTimeInterval(-3600), to: anchor) == "1h 0m ago")
    }

    @Test("Every exit code is pinned, because scripts are the contract")
    func exitCodeValues() {
        #expect(LiveGuardReport.Status.liveAndConsistent.rawValue == 0)
        #expect(LiveGuardReport.Status.noLiveState.rawValue == 3)
        #expect(LiveGuardReport.Status.writerGone.rawValue == 4)
        #expect(LiveGuardReport.Status.unreadable.rawValue == 5)
        #expect(LiveGuardReport.Status.liveButDiverging.rawValue == 6)
        // The stale readings all gate the same way.
        #expect(LiveGuardReport.status(for: .writerReplaced(pid: 1, observedAt: anchor), onDisk: disk()) == .writerGone)
        #expect(LiveGuardReport.status(for: .otherUser(pid: 1, uid: 502), onDisk: disk()) == .writerGone)
        // 1 is EXIT_FAILURE and 2 is the shell's usage convention; neither is used.
        #expect(!LiveGuardReport.Status.allCases.map(\.rawValue).contains(1))
        #expect(!LiveGuardReport.Status.allCases.map(\.rawValue).contains(2))
    }

    @Test("Stale readings name the other instances they can see")
    func staleReadingsNameInstances() {
        // The most useful moment for this: the record's writer died, something
        // else is running now, and the reader must not conflate them.
        let rendered = lines(
            .writerGone(pid: 4242, observedAt: anchor.addingTimeInterval(-60)),
            instances: [ObservedInstance(pid: 28571, bundlePath: "/Applications/DockKeeper.app", version: "0.9.4")]
        )
        #expect(rendered.contains("Running:       pid 28571 0.9.4 at /Applications/DockKeeper.app"))
        let replaced = lines(
            .writerReplaced(pid: 4242, observedAt: anchor.addingTimeInterval(-60)),
            instances: [ObservedInstance(pid: 28571, bundlePath: nil, version: nil)]
        )
        #expect(replaced.contains("Running:       pid 28571 at unknown path"))
    }
}

// MARK: -

@Suite("Live guard publish policy")
struct LiveGuardPublisherTests {

    private func candidate(
        writer: ProcessIdentity = identity(),
        at: Date = anchor,
        settings: LiveGuardRecord.HeldSettings = held(),
        tap: LiveGuardRecord.TapRecord? = nil
    ) -> LiveGuardRecord {
        record(writer: writer, observedAt: at, stateChangedAt: at, settings: settings, tap: tap)
    }

    @Test("With nothing stored, the record is published")
    func firstPublish() {
        let c = candidate()
        #expect(LiveGuardPublisher.next(candidate: c, stored: .absent) == .write(c))
    }

    @Test("An unreadable or newer-schema value in the store is replaced, not preserved")
    func unusableStoreIsReplaced() {
        // All three mean the same thing to a publisher: what is stored does not
        // describe this instance.
        let c = candidate()
        #expect(LiveGuardPublisher.next(candidate: c, stored: .unreadable("x")) == .write(c))
        #expect(LiveGuardPublisher.next(candidate: c, stored: .wrongSchema(found: 99)) == .write(c))
    }

    @Test("A record belonging to another process is never adopted as a baseline")
    func foreignRecordIsReplaced() {
        // Otherwise a peer's identical-looking state would suppress this
        // instance's first publish, and the store would keep naming a writer
        // that is not the one running.
        let mine = candidate(writer: identity(pid: 100, started: 1))
        let theirs = candidate(writer: identity(pid: 200, started: 2))
        #expect(LiveGuardPublisher.next(candidate: mine, stored: .present(theirs)) == .write(mine))
    }

    @Test("A vanished record is republished, which a process-local memo could not do")
    func vanishedRecordIsRepaired() {
        // The concrete failure: something clears the key while the app runs. A
        // publisher comparing against its own memory of the last write would see
        // no change and stay silent forever, and the reader would report that
        // nothing had published about a healthy running app.
        let c = candidate()
        #expect(LiveGuardPublisher.next(candidate: c, stored: .absent) == .write(c))
    }

    @Test("An idle instance whose state has not changed writes nothing")
    func idleIsSilent() {
        // Every install with the feature off — the default — settles here.
        let stored = candidate(at: anchor.addingTimeInterval(-3600), tap: nil)
        let now = candidate(at: anchor, tap: nil)
        #expect(LiveGuardPublisher.next(candidate: now, stored: .present(stored)) == .skip)
    }

    @Test("A substantive change is always written, and resets the change stamp")
    func substantiveChange() {
        let stored = candidate(at: anchor.addingTimeInterval(-3600), settings: held(bottomGuard: true))
        let now = candidate(at: anchor, settings: held(bottomGuard: false))
        #expect(LiveGuardPublisher.next(candidate: now, stored: .present(stored)) == .write(now))
        // `now`'s own stateChangedAt is `anchor` — the change happened now.
        guard case .write(let written) = LiveGuardPublisher.next(candidate: now, stored: .present(stored)) else {
            Issue.record("expected a write"); return
        }
        #expect(written.stateChangedAt == anchor)
    }

    @Test("An armed tap is refreshed every time, so a wedged instance stops looking healthy")
    func armedHeartbeat() {
        // The whole point: with writes suppressed, `observedAt` silently stops
        // meaning "when this was last observed". A healthy idle instance and one
        // whose run loop has wedged — tap disabled by macOS, guarding nothing —
        // would then be byte-identical in the output.
        let stored = candidate(at: anchor.addingTimeInterval(-30), tap: vitals(clamps: 7))
        let now = candidate(at: anchor, tap: vitals(clamps: 7))   // nothing at all moved
        guard case .write(let written) = LiveGuardPublisher.next(candidate: now, stored: .present(stored)) else {
            Issue.record("an armed tap must refresh"); return
        }
        #expect(written.observedAt == anchor)
        // ...but it is still not a state *change*, so the stamp carries forward.
        #expect(written.stateChangedAt == anchor.addingTimeInterval(-30))
    }

    @Test("A moved counter is written even when nothing is armed any more")
    func counterMovementWrites() {
        let stored = candidate(at: anchor.addingTimeInterval(-30), tap: vitals(clamps: 7))
        let now = candidate(at: anchor, tap: vitals(clamps: 9))
        guard case .write(let written) = LiveGuardPublisher.next(candidate: now, stored: .present(stored)) else {
            Issue.record("expected a write"); return
        }
        #expect(written.tap?.clampCount == 9)
        #expect(written.stateChangedAt == anchor.addingTimeInterval(-30))
    }

    @Test("Retraction refuses to delete a record this process did not write")
    func retractionIsOwnershipChecked() {
        // DK-FR-012 documents two supported multi-instance modes, and both share
        // this key. An unconditional retraction would let one instance's quit
        // delete a live instance's record.
        let me = identity(pid: 100, started: 1)
        let mine = candidate(writer: me)
        let theirs = candidate(writer: identity(pid: 200, started: 2))
        #expect(LiveGuardPublisher.shouldRetract(stored: .present(mine), writer: me))
        #expect(!LiveGuardPublisher.shouldRetract(stored: .present(theirs), writer: me))
        // Nothing to withdraw, and nothing that is ours to destroy.
        #expect(!LiveGuardPublisher.shouldRetract(stored: .absent, writer: me))
        #expect(!LiveGuardPublisher.shouldRetract(stored: .unreadable("x"), writer: me))
        #expect(!LiveGuardPublisher.shouldRetract(stored: .wrongSchema(found: 99), writer: me))
    }
}

// MARK: -

@Suite("Live guard record persistence")
struct LiveGuardRecordSettingsTests {

    @Test("A published record round-trips through the shared domain")
    func roundTrip() {
        let settings = makeTestSettings("liveguard")
        let original = record(
            decision: .guarding(zones: [zone(7)], skipped: [3], partiallyGuarded: []),
            tap: vitals()
        )
        settings.publishLiveGuardRecord(original)
        guard case .present(let restored) = settings.liveGuardRecord else {
            Issue.record("expected a present record")
            return
        }
        #expect(restored == original)
    }

    @Test("Nothing published reads as absent")
    func absent() {
        #expect(makeTestSettings("liveguard").liveGuardRecord == .absent)
    }

    @Test("A corrupt value reads as unreadable, never as absent")
    func corruptIsNotAbsent() {
        // Deliberately unlike `pauseRecord`, which degrades to nil. "Not paused"
        // is a true reading of a broken pause record; "no instance is
        // publishing" is not a true reading of a broken live record.
        let defaults = makeTestDefaults("liveguard")
        defaults.set("{ not json", forKey: "liveGuardRecord")
        guard case .unreadable = Settings(defaults: defaults).liveGuardRecord else {
            Issue.record("expected .unreadable")
            return
        }
    }

    @Test("Retracting removes the key, so a surviving record means an untrappable death")
    func retraction() {
        let defaults = makeTestDefaults("liveguard")
        let settings = Settings(defaults: defaults)
        settings.publishLiveGuardRecord(record())
        #expect(defaults.object(forKey: "liveGuardRecord") != nil)
        settings.publishLiveGuardRecord(nil)
        #expect(defaults.object(forKey: "liveGuardRecord") == nil)
        #expect(settings.liveGuardRecord == .absent)
    }

    @Test("The stored value is readable JSON text, because machine-readable is the requirement")
    func storedAsText() {
        // `defaults read com.dockkeeper.app liveGuardRecord` is the
        // machine-readable artifact. A `Data` value — the idiom the two older
        // records use — renders there as a hex blob no support reader can use.
        let defaults = makeTestDefaults("liveguard")
        Settings(defaults: defaults).publishLiveGuardRecord(record())
        let text = defaults.string(forKey: "liveGuardRecord")
        #expect(text != nil)
        #expect(text?.hasPrefix("{") == true)
        #expect(text?.contains("\"schema\":1") == true)
    }

    @Test("A non-string value in the domain reads as unreadable, not as absent")
    func nonStringIsNotAbsent() {
        // A stray `defaults write com.dockkeeper.app liveGuardRecord -int 1`
        // makes `string(forKey:)` answer nil, which would read as "no instance
        // has published" — collapsing the exact distinction this enum exists to
        // keep, and doing it silently.
        let defaults = makeTestDefaults("liveguard")
        defaults.set(1, forKey: "liveGuardRecord")
        guard case .unreadable = Settings(defaults: defaults).liveGuardRecord else {
            Issue.record("expected .unreadable")
            return
        }
    }

    @Test("A record naming an unknown schema is a version difference, not damage")
    func newerSchemaIsNotCorruption() {
        // Decided from the envelope alone, before the payload is parsed. A newer
        // DockKeeper may have made a field required or given a case an associated
        // value; parsing the payload to reach `schema` would report every such
        // change as a damaged record.
        let defaults = makeTestDefaults("liveguard")
        defaults.set(#"{"schema":99,"somethingEntirelyNew":true}"#, forKey: "liveGuardRecord")
        #expect(Settings(defaults: defaults).liveGuardRecord == .wrongSchema(found: 99))
    }

    @Test("The wire format is pinned against a literal, not against the encoder under test")
    func wireFormatIsPinned() {
        // Every other persistence test round-trips through the same encoder and
        // decoder, so it would pass just as happily if the format changed
        // wholesale — and the format is a published artifact that support reads
        // with `defaults read` and that an older CLI must still parse. The oracle
        // here is a literal written by hand.
        let defaults = makeTestDefaults("liveguard")
        Settings(defaults: defaults).publishLiveGuardRecord(
            LiveGuardRecord(
                writer: ProcessIdentity(pid: 4242, startedAtMicroseconds: 111_222_333, uid: 501),
                appVersion: "0.9.5",
                bundlePath: "/Applications/DockKeeper.app",
                observedAt: Date(timeIntervalSince1970: 1_756_000_000),
                stateChangedAt: Date(timeIntervalSince1970: 1_755_999_275),
                held: LiveGuardRecord.HeldSettings(
                    isEnabled: true, lockEdge: .bottom, lockBottomDockToDisplay: true
                ),
                accessibilityTrusted: true,
                decision: LiveGuardRecord.DecisionRecord(.idle(.featureDisabled)),
                tap: nil
            )
        )
        #expect(defaults.string(forKey: "liveGuardRecord") == LIVEGUARD_GOLDEN)
    }

    @Test("A sub-second stamp survives the round trip, so the change guard cannot thrash")
    func datesAreWholeSeconds() {
        // The wire format is ISO8601 without fractional seconds. If the in-memory
        // record kept a sub-second stamp, it would differ from the stored one on
        // every comparison and the publisher would write on every single
        // reconcile forever — defeating the whole change guard.
        let settings = makeTestSettings("liveguard")
        let original = record(observedAt: Date(timeIntervalSince1970: 1_756_000_000.75))
        settings.publishLiveGuardRecord(original)
        guard case .present(let restored) = settings.liveGuardRecord else {
            Issue.record("expected a present record"); return
        }
        #expect(restored == original)
        #expect(restored.observedAt == Date(timeIntervalSince1970: 1_756_000_000))
    }

    @Test("The key is not registered and not externally observed")
    func notRegisteredNotObserved() {
        // Absence is a real state, so a registration default would invent a
        // record nobody published. And this app writes the key — observing it
        // would turn every publish into a reconcile.
        #expect(makeTestSettings("liveguard").liveGuardRecord == .absent)
        #expect(!Settings.externallyObservedKeys.contains("liveGuardRecord"))
    }
}

// MARK: -

@Suite("Process identity")
struct ProcessIdentityTests {

    @Test("This process can read its own kernel identity")
    func selfIsAlive() {
        guard let me = ProcessIdentity.current() else {
            Issue.record("sysctl could not read this process")
            return
        }
        #expect(me.pid == getpid())
        #expect(me.uid == getuid())
        // A start time of zero would mean the read silently returned a zeroed
        // struct, which is the failure the `size > 0` guard exists to catch.
        #expect(me.startedAtMicroseconds > 0)
    }

    @Test("A pid that cannot exist reads as no process")
    func absentPid() {
        // `-1` is not a pid at all — `KERN_PROC_PID` cannot match it, so the
        // lookup fails rather than matching something unexpected. Deliberately
        // not pid 0: on macOS that is the kernel task and `sysctl` does answer
        // for it, so a test built on "0 is never a process" would assert
        // something false and pass only by accident.
        #expect(ProcessIdentity.of(pid: -1) == nil)
    }

    @Test("Reading the same process twice gives the same identity")
    func stable() {
        // The property the liveness check depends on: a start time that drifted
        // between reads would reject a live writer.
        #expect(ProcessIdentity.current() == ProcessIdentity.current())
    }
}

/// The exact string the wire format must produce for the fixture in
/// `wireFormatIsPinned`, written out by hand.
///
/// A raw string, because `JSONEncoder` escapes forward slashes as `\/` and a
/// normal Swift literal would need those doubled — at which point the thing the
/// test claims to pin is no longer what the file shows. Keys are alphabetical
/// because the encoder is configured `.sortedKeys`.
private let LIVEGUARD_GOLDEN = #"{"accessibilityTrusted":true,"appVersion":"0.9.5","bundlePath":"\/Applications\/DockKeeper.app","decision":{"idleExplanation":"off — not enabled in Preferences","kind":"idle","partiallyGuardedDisplayIDs":[],"skippedDisplayIDs":[],"zones":[]},"held":{"isEnabled":true,"lockBottomDockToDisplay":true,"lockEdge":2},"observedAt":"2025-08-24T01:46:40Z","schema":1,"stateChangedAt":"2025-08-24T01:34:35Z","writer":{"pid":4242,"startedAtMicroseconds":111222333,"uid":501}}"#
