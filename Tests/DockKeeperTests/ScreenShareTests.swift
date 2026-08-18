import Testing
import Foundation
@testable import DockKeeperCore

/// DK-FR-011 / ADR-011 — hide the Dock during screen capture.
///
/// Only the pure `decide` core is exercised here (kickoff §7): the private
/// CoreDock auto-hide reads/writes and the `CGSIsScreenWatcherPresent` detector
/// are never called from tests — that would move the real Dock and needs the
/// on-device hardware cell (M6/M12). `decide` holds every rule, so the table
/// below is the whole behavioral contract.
@Suite("ScreenShareHider.decide")
struct ScreenShareDecideTests {

    private typealias Action = ScreenShareHider.Action

    /// One row of the truth table: the three inputs and the expected action.
    private struct Case {
        let capturing: Bool
        let weHidIt: Bool
        let currentAutoHide: Bool
        let expected: Action
        let note: String
    }

    /// Exhaustive: every combination of `capturing × weHidIt × currentAutoHide`
    /// (2³ = 8 rows). This is the complete decision contract of ADR-011.
    @Test("Full truth table over capturing × weHidIt × currentAutoHide (all 8)")
    func exhaustiveTable() {
        let cases: [Case] = [
            // Capture running.
            Case(capturing: true,  weHidIt: false, currentAutoHide: false, expected: .hide,
                 note: "Share starts, user auto-hide OFF → we hide"),
            Case(capturing: true,  weHidIt: false, currentAutoHide: true,  expected: .none,
                 note: "Share starts, user already auto-hides → never touch (and never record a hide)"),
            Case(capturing: true,  weHidIt: true,  currentAutoHide: true,  expected: .none,
                 note: "Already hidden by us → idempotent"),
            Case(capturing: true,  weHidIt: true,  currentAutoHide: false, expected: .none,
                 note: "Already hidden by us, even if auto-hide reads off → idempotent, no re-hide"),
            // Capture stopped.
            Case(capturing: false, weHidIt: true,  currentAutoHide: true,  expected: .restore,
                 note: "Share ends, we hid it → restore (auto-hide back off)"),
            Case(capturing: false, weHidIt: true,  currentAutoHide: false, expected: .restore,
                 note: "Share ends, we hid it → restore even if already off (clears the flag)"),
            Case(capturing: false, weHidIt: false, currentAutoHide: true,  expected: .none,
                 note: "No capture, user runs auto-hide, we didn't hide → leave it alone"),
            Case(capturing: false, weHidIt: false, currentAutoHide: false, expected: .none,
                 note: "No capture, nothing hidden → nothing to do"),
        ]

        #expect(cases.count == 8)  // guards against an accidentally dropped row
        for row in cases {
            let action = ScreenShareHider.decide(
                capturing: row.capturing,
                weHidIt: row.weHidIt,
                currentAutoHide: row.currentAutoHide
            )
            #expect(action == row.expected, "\(row.note)")
        }
    }

    @Test("Never hides when the user already runs auto-hide, so it never restores it (ADR-011)")
    func neverTouchesUserAutoHide() {
        // The user set auto-hide themselves: no hide while capturing…
        #expect(ScreenShareHider.decide(capturing: true, weHidIt: false, currentAutoHide: true) == .none)
        // …and because we never recorded a hide (weHidIt stays false), stopping
        // capture is a no-op — we never "restore" (turn off) what we didn't set.
        #expect(ScreenShareHider.decide(capturing: false, weHidIt: false, currentAutoHide: true) == .none)
    }

    @Test("Hides once, then stays put across repeated capture ticks (idempotent)")
    func hideThenIdempotent() {
        // First tick of a capture with auto-hide off → hide.
        #expect(ScreenShareHider.decide(capturing: true, weHidIt: false, currentAutoHide: false) == .hide)
        // Subsequent ticks (now weHidIt == true, auto-hide == true) → no-op.
        #expect(ScreenShareHider.decide(capturing: true, weHidIt: true, currentAutoHide: true) == .none)
    }

    @Test("Restores exactly once on capture-stop, then stays quiet (idempotent)")
    func restoreThenIdempotent() {
        // Capture stops while we hold the hide → restore.
        #expect(ScreenShareHider.decide(capturing: false, weHidIt: true, currentAutoHide: true) == .restore)
        // After restore the flag is cleared; a further no-capture tick → no-op.
        #expect(ScreenShareHider.decide(capturing: false, weHidIt: false, currentAutoHide: false) == .none)
    }
}

@Suite("ScreenShareHider lifecycle & settings")
struct ScreenShareLifecycleTests {

    /// Isolated defaults so the test never touches the real user domain.
    private func makeSettings(_ test: String = #function) -> Settings {
        makeTestSettings("ScreenShare", test)
    }

    @Test("Feature is opt-in: off by default (setting-off short-circuit)")
    func offByDefault() {
        // Off by default → AppState never starts the poll, so `decide` (and any
        // CoreDock write) is never reached. This is the setting-level guard that
        // keeps the private API untouched unless the user opts in.
        //
        // DK-FR-013 added a second entry point that runs on *every* launch
        // regardless of this setting — the launch repair — so the guarantee no
        // longer rests on this toggle alone. Its half is asserted separately by
        // `repairWithNoRecordTouchesNoPrivateAPI`.
        #expect(makeSettings().hideDockDuringScreenShare == false)
    }

    @Test("Persists the opt-in")
    func persists() {
        let settings = makeSettings()
        settings.hideDockDuringScreenShare = true
        #expect(settings.hideDockDuringScreenShare == true)
    }

    @MainActor
    @Test("A fresh hider holds no hide, so teardown-restore is a safe no-op")
    func freshHiderHasNoHide() {
        // Constructing the hider and reading the flag touches no private API.
        // Isolated settings so the hide record can never reach the real domain.
        let hider = ScreenShareHider(settings: makeSettings())
        #expect(hider.weHidIt == false)
        hider.restoreIfNeeded()  // guarded by weHidIt → returns before any CoreDock call
        #expect(hider.weHidIt == false)
    }

    @Test("Documented default poll cadence")
    func pollCadence() {
        #expect(ScreenShareHider.defaultCheckInterval == 3)
    }
}

/// DK-FR-013 — restore Dock auto-hide on the way out.
///
/// These drive the *side-effecting* half of `ScreenShareHider` through the
/// injected auto-hide port, so the teardown contract the termination hook
/// depends on is covered without the private CoreDock symbols ever being
/// called and without the real Dock moving (kickoff §7 still holds).
@Suite("ScreenShareHider teardown restore (DK-FR-013)")
@MainActor
struct ScreenShareTerminationTests {

    /// Stand-in for the Dock's auto-hide bit, recording every write so a test
    /// can assert not just the end state but that we did not touch it at all.
    private final class FakeDock {
        var autoHide: Bool
        var writes: [Bool] = []
        init(autoHide: Bool = false) { self.autoHide = autoHide }
    }

    /// `settings` is passed explicitly rather than defaulted, so a `.hide` here
    /// writes its DK-FR-013 record into an isolated suite instead of the real
    /// `com.dockkeeper.app` domain. Each test owns one, created up front.
    private func makeHider(_ dock: FakeDock, settings: Settings, capturing: Bool = false) -> ScreenShareHider {
        ScreenShareHider(
            probe: { capturing },
            readAutoHide: { dock.autoHide },
            writeAutoHide: { dock.autoHide = $0; dock.writes.append($0); return true },
            settings: settings
        )
    }

    @Test("Quit while we hold the hide restores auto-hide (the DK-FR-013 fix)")
    func teardownRestoresOurHide() {
        let dock = FakeDock(autoHide: false)
        let hider = makeHider(dock, settings: makeTestSettings("ScreenShareTeardown"))

        #expect(hider.evaluate(capturing: true) == .hide)
        #expect(hider.weHidIt)
        #expect(dock.autoHide)

        // What applicationWillTerminate -> AppState.prepareForTermination does.
        hider.stop()

        #expect(hider.weHidIt == false)
        #expect(dock.autoHide == false)
        #expect(dock.writes == [true, false])
    }

    @Test("Quit never touches auto-hide the user owns (ADR-011 invariant survives teardown)")
    func teardownLeavesUserAutoHideAlone() {
        let dock = FakeDock(autoHide: true)   // the user runs auto-hide themselves
        let hider = makeHider(dock, settings: makeTestSettings("ScreenShareTeardown"))

        #expect(hider.evaluate(capturing: true) == .none)
        #expect(hider.weHidIt == false)

        hider.stop()

        #expect(dock.autoHide)                // still on, as the user left it
        #expect(dock.writes.isEmpty)          // and we never wrote at all
    }

    @Test("Quit with nothing hidden writes nothing")
    func teardownWithNoHideIsInert() {
        let dock = FakeDock(autoHide: false)
        let hider = makeHider(dock, settings: makeTestSettings("ScreenShareTeardown"))

        hider.stop()

        #expect(dock.writes.isEmpty)
        #expect(hider.weHidIt == false)
    }

    @Test("Teardown is idempotent — a second quit-time restore is a no-op")
    func teardownIsIdempotent() {
        let dock = FakeDock(autoHide: false)
        let hider = makeHider(dock, settings: makeTestSettings("ScreenShareTeardown"))
        #expect(hider.evaluate(capturing: true) == .hide)

        hider.stop()
        hider.stop()
        hider.restoreIfNeeded()

        #expect(dock.writes == [true, false])  // exactly one restore
    }

    @Test("stop(restore: false) keeps the hide — the poll-restart path, not the quit path")
    func restartPathKeepsTheHide() {
        let dock = FakeDock(autoHide: false)
        let hider = makeHider(dock, settings: makeTestSettings("ScreenShareTeardown"))
        #expect(hider.evaluate(capturing: true) == .hide)

        hider.stop(restore: false)  // what start() does internally

        #expect(hider.weHidIt)
        #expect(dock.autoHide)
        #expect(dock.writes == [true])
    }

    @Test("The poll alone never un-poisons the next launch (why DK-FR-013 needs a record)")
    func missedRestorePoisonsTheNextLaunch() {
        // One `Settings` across both hiders — the record is the only thing that
        // crosses the process boundary, so it must be the same store.
        let settings = makeTestSettings("ScreenShareTeardown")
        let dock = FakeDock(autoHide: false)
        let killed = makeHider(dock, settings: settings)
        #expect(killed.evaluate(capturing: true) == .hide)
        // SIGKILL: no teardown runs, so auto-hide is left on and weHidIt dies
        // with the process.
        #expect(dock.autoHide)

        // Next launch: a fresh hider, in-memory flag false, auto-hide reads on.
        let relaunched = makeHider(dock, settings: settings)
        #expect(relaunched.evaluate(capturing: true) == .none)   // "user runs auto-hide"
        #expect(relaunched.evaluate(capturing: false) == .none)  // never restores
        #expect(dock.autoHide)                                   // stuck on via the poll alone

        // The steady-state poll is *correct* to refuse — it cannot tell our
        // leftover from a setting the user owns. Only the launch-time repair
        // has the provenance to break the cycle; see
        // `ScreenShareRepairIntegrationTests.repairsAfterAKill`.
        #expect(settings.screenShareHideRecord != nil)
    }
}

/// DK-FR-013 / ADR-013 — the pure launch-time repair rule.
///
/// `repair` answers a different question from `decide`: not "what is the right
/// steady state?" but "what does a hide record that outlived its process
/// actually prove?". Everything here is total and clock-injected, so no test
/// depends on the real `Date()` or touches a private symbol.
@Suite("ScreenShareHider.repair")
struct ScreenShareRepairTests {

    private typealias Repair = ScreenShareHider.Repair

    /// A fixed clock, so "age" is exact and the seven-day boundary is testable
    /// without a real wait.
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let window = ScreenShareHider.repairWindow

    /// A record stamped `age` seconds before `now`. Negative ages are records
    /// from the future — a clock that moved back, or a restored backup.
    private static func record(ageSeconds age: TimeInterval) -> ScreenShareHideRecord {
        ScreenShareHideRecord(hiddenAt: now.addingTimeInterval(-age))
    }

    /// One row of the rule table.
    private struct Case {
        let record: ScreenShareHideRecord?
        let currentAutoHide: Bool?
        let capturing: Bool
        let featureActive: Bool
        let expected: Repair
        let note: String
    }

    @Test("Full rule table over record × currentAutoHide × capturing × featureActive (all 10 branches)")
    func ruleTable() {
        let cases: [Case] = [
            Case(record: nil, currentAutoHide: true, capturing: false, featureActive: true,
                 expected: .none,
                 note: "No record → nothing was left behind, so nothing is ours to undo"),
            Case(record: Self.record(ageSeconds: 0), currentAutoHide: nil, capturing: false, featureActive: true,
                 expected: .none,
                 note: "CoreDock unreadable → we can neither read nor write; keep the record"),
            Case(record: Self.record(ageSeconds: 0), currentAutoHide: false, capturing: false, featureActive: true,
                 expected: .discard,
                 note: "Auto-hide already off → nothing of ours remains; drop the record, write nothing"),
            Case(record: Self.record(ageSeconds: -60), currentAutoHide: true, capturing: false, featureActive: true,
                 expected: .discard,
                 note: "Record stamped in the future → nonsense clock; never act on it"),
            Case(record: Self.record(ageSeconds: Self.window + 1), currentAutoHide: true, capturing: false, featureActive: true,
                 expected: .discard,
                 note: "Past the window → the user has lived with it; it is theirs by acquiescence"),
            Case(record: Self.record(ageSeconds: Self.window), currentAutoHide: true, capturing: false, featureActive: true,
                 expected: .restore,
                 note: "Exactly at the window → still ours (the bound is inclusive)"),
            Case(record: Self.record(ageSeconds: 0), currentAutoHide: true, capturing: false, featureActive: true,
                 expected: .restore,
                 note: "Zero-age record → the dev-loop SIGKILL, repaired immediately"),
            Case(record: Self.record(ageSeconds: 30), currentAutoHide: true, capturing: true, featureActive: true,
                 expected: .adopt,
                 note: "Capture still running and the poll will run → adopt, never flash the Dock mid-share"),
            Case(record: Self.record(ageSeconds: 30), currentAutoHide: true, capturing: true, featureActive: false,
                 expected: .restore,
                 note: "Capturing but the poll will NOT run → adopting would re-arm the bug; restore now"),
            Case(record: Self.record(ageSeconds: 3600), currentAutoHide: true, capturing: false, featureActive: false,
                 expected: .restore,
                 note: "The headline issue #29 case: killed mid-share, relaunched later, no capture"),
        ]

        #expect(cases.count == 10)  // guards against an accidentally dropped row
        for row in cases {
            let action = ScreenShareHider.repair(
                record: row.record,
                currentAutoHide: row.currentAutoHide,
                capturing: row.capturing,
                featureActive: row.featureActive,
                now: Self.now
            )
            #expect(action == row.expected, "\(row.note)")
        }
    }

    /// The false-restore safety property, stated as an exhaustive sweep rather
    /// than as prose: `repair` may not authorise a Dock write unless it has
    /// *observed* auto-hide as on. Everything else — the window, the capture
    /// check — is refinement on top of this floor.
    @Test("Never restores or adopts without observing auto-hide ON (all 48 combinations)")
    func neverActsWithoutObservingAutoHideOn() {
        let records: [ScreenShareHideRecord?] = [
            nil,
            Self.record(ageSeconds: 0),                    // fresh
            Self.record(ageSeconds: 24 * 3600),            // mid-window
            Self.record(ageSeconds: Self.window + 3600),   // stale
        ]
        var checked = 0
        for record in records {
            for autoHide in [nil, false, true] as [Bool?] {
                for capturing in [false, true] {
                    for featureActive in [false, true] {
                        checked += 1
                        let action = ScreenShareHider.repair(
                            record: record,
                            currentAutoHide: autoHide,
                            capturing: capturing,
                            featureActive: featureActive,
                            now: Self.now
                        )
                        if autoHide != true {
                            #expect(action != .restore, "wrote the Dock without observing auto-hide ON")
                            #expect(action != .adopt, "claimed a hide without observing auto-hide ON")
                        }
                        if record == nil {
                            #expect(action == .none, "acted with no record at all")
                        }
                        if autoHide == nil {
                            #expect(action == .none, "acted while the Dock was unreadable")
                        }
                    }
                }
            }
        }
        #expect(checked == 48)  // 4 records × 3 auto-hide × 2 capturing × 2 featureActive
    }

    /// The observable state a repair acts on, and what applying the repair does
    /// to it — the same two mutations `repairIfNeeded` performs, modelled here
    /// so convergence can be asserted on the *pure* function.
    private struct World {
        var record: ScreenShareHideRecord?
        var autoHide: Bool?

        mutating func apply(_ action: Repair) {
            switch action {
            case .none, .adopt:
                break                       // `.adopt` deliberately keeps the record
            case .discard:
                record = nil
            case .restore:
                autoHide = false
                record = nil
            }
        }
    }

    /// Applying a repair must settle in one step — a repair that re-fires every
    /// launch would be a slow-motion version of the bug it fixes.
    @Test("Converges in one step: applying a repair makes the next launch inert")
    func convergesInOneStep() {
        func settle(_ world: World, capturing: Bool, featureActive: Bool) -> (Repair, Repair) {
            var world = world
            let first = ScreenShareHider.repair(
                record: world.record, currentAutoHide: world.autoHide,
                capturing: capturing, featureActive: featureActive, now: Self.now
            )
            world.apply(first)
            let second = ScreenShareHider.repair(
                record: world.record, currentAutoHide: world.autoHide,
                capturing: capturing, featureActive: featureActive, now: Self.now
            )
            return (first, second)
        }

        // `.restore` clears the record *and* leaves auto-hide off, so both
        // guard 1 and guard 3 would fire on a re-run — doubly convergent.
        var outcome = settle(World(record: Self.record(ageSeconds: 0), autoHide: true),
                             capturing: false, featureActive: true)
        #expect(outcome == (.restore, .none))

        // `.discard` clears the record, so guard 1 fires even though auto-hide
        // is deliberately left exactly as the user has it.
        outcome = settle(World(record: Self.record(ageSeconds: Self.window + 1), autoHide: true),
                         capturing: false, featureActive: true)
        #expect(outcome == (.discard, .none))

        // `.adopt` keeps the record on purpose, so it is a *fixed point*: the
        // re-run returns `.adopt` again, whose application is a no-op
        // (`weHidIt = true` a second time, and the Dock write it authorises is
        // the one already in effect).
        outcome = settle(World(record: Self.record(ageSeconds: 0), autoHide: true),
                         capturing: true, featureActive: true)
        #expect(outcome == (.adopt, .adopt))

        // `.none` is a fixed point by definition.
        outcome = settle(World(record: nil, autoHide: true), capturing: false, featureActive: true)
        #expect(outcome == (.none, .none))
    }

    @Test("The attribution window is the documented seven days")
    func windowIsTheDocumentedSevenDays() {
        // The number is a contract (ADR-013), not an accident: it is sized
        // against the login-item relaunch path, so shrinking it silently would
        // leave the headline bug unfixed for the user who actually hits it.
        #expect(ScreenShareHider.repairWindow == 7 * 24 * 3600)
    }
}

/// DK-FR-013 / ADR-013 — the side-effecting half of the repair, driven through
/// the injected ports.
///
/// Two hiders over one `Settings` and one `FakeDock` model "process 1 was
/// killed, process 2 starts": the record is the only thing that crosses the
/// boundary, exactly as in production. No private symbol is called and the real
/// Dock never moves.
@Suite("ScreenShareHider launch repair (DK-FR-013)")
@MainActor
struct ScreenShareRepairIntegrationTests {

    /// Stand-in for the Dock's auto-hide bit. `writes` records only the writes
    /// that *landed*, so a test can assert "we did not touch it at all";
    /// `writeSucceeds` models the private symbol being unavailable.
    private final class FakeDock {
        var autoHide: Bool
        var writes: [Bool] = []
        var writeSucceeds = true
        var readable = true
        init(autoHide: Bool = false) { self.autoHide = autoHide }
    }

    private func makeHider(_ dock: FakeDock, settings: Settings, capturing: Bool = false) -> ScreenShareHider {
        ScreenShareHider(
            probe: { capturing },
            readAutoHide: { dock.readable ? dock.autoHide : nil },
            writeAutoHide: { value in
                guard dock.writeSucceeds else { return false }
                dock.autoHide = value
                dock.writes.append(value)
                return true
            },
            settings: settings
        )
    }

    @Test("A hide leaves a record; the matching restore clears it")
    func recordTracksTheHide() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        let hider = makeHider(dock, settings: settings)

        #expect(hider.evaluate(capturing: true) == .hide)
        #expect(settings.screenShareHideRecord != nil)
        #expect(dock.autoHide)

        #expect(hider.evaluate(capturing: false) == .restore)
        #expect(settings.screenShareHideRecord == nil)
        #expect(dock.autoHide == false)
    }

    /// The write-ahead *ordering* itself, observed from inside the Dock write.
    ///
    /// End-state assertions cannot see this: both orderings finish with a record
    /// and auto-hide on, so a "Dock first, record second" mutant passes every
    /// other test in this file. That mutant is exactly the unrecoverable state
    /// ADR-013 exists to prevent (killed between the two writes → auto-hide ON
    /// with no record), and it is the general rule the ADR mints for all future
    /// borrowed system state — so the interleaving needs its own assertion.
    @Test("Write-ahead: the record is already stored when the Dock write happens")
    func recordLandsBeforeTheDockWrite() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        // Double optional on purpose: `.none` means the write never happened,
        // `.some(nil)` means it happened with no record stored yet — the bug.
        var recordAtWriteTime: ScreenShareHideRecord??
        let hider = ScreenShareHider(
            probe: { true },
            readAutoHide: { dock.autoHide },
            writeAutoHide: { value in
                recordAtWriteTime = settings.screenShareHideRecord
                dock.autoHide = value
                dock.writes.append(value)
                return true
            },
            settings: settings
        )

        #expect(hider.evaluate(capturing: true) == .hide)
        #expect(dock.writes == [true])
        #expect((recordAtWriteTime ?? nil) != nil, "the Dock was written before the claim was stored")
    }

    /// The mirror of the above for the restore, so both halves of the ordering
    /// invariant are pinned rather than only the one an end state can show.
    @Test("Write-behind: the record still exists while the restoring write happens")
    func recordSurvivesUntilAfterTheDockWrite() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        var recordAtWriteTime: [ScreenShareHideRecord?] = []
        let hider = ScreenShareHider(
            probe: { false },
            readAutoHide: { dock.autoHide },
            writeAutoHide: { value in
                recordAtWriteTime.append(settings.screenShareHideRecord)
                dock.autoHide = value
                dock.writes.append(value)
                return true
            },
            settings: settings
        )

        #expect(hider.evaluate(capturing: true) == .hide)
        #expect(hider.evaluate(capturing: false) == .restore)
        #expect(dock.writes == [true, false])
        #expect(recordAtWriteTime.count == 2)
        #expect(recordAtWriteTime.last ?? nil != nil, "the claim was dropped before the Dock was back off")
        #expect(settings.screenShareHideRecord == nil)   // …and cleared only after
    }

    /// DK-FR-011's opt-in guarantee, as a regression test rather than a comment.
    /// Swift evaluates call arguments eagerly, so a `repairIfNeeded` that passed
    /// `readAutoHide()` / `probe()` straight into `repair` would call both
    /// private symbols on *every* launch — including for the majority of users
    /// who never turned the feature on.
    @Test("No record: the launch repair touches neither private port")
    func repairWithNoRecordTouchesNoPrivateAPI() {
        let settings = makeTestSettings("ScreenShareRepair")
        var probeCalls = 0
        var readCalls = 0
        let hider = ScreenShareHider(
            probe: { probeCalls += 1; return false },
            readAutoHide: { readCalls += 1; return true },
            writeAutoHide: { _ in Issue.record("wrote the Dock with no record"); return false },
            settings: settings
        )

        #expect(settings.screenShareHideRecord == nil)
        #expect(hider.repairIfNeeded(featureActive: true) == .none)
        #expect(probeCalls == 0)
        #expect(readCalls == 0)
    }

    /// The mirror of `repair` guard 2 on the *minting* side. An unreadable
    /// auto-hide means we cannot tell the user's setting from ours, so we must
    /// not hide — and in particular must not overwrite the record that
    /// `keepsTheRecordWhenAutoHideIsUnreadable` just proved we preserve.
    @Test("Unreadable auto-hide: evaluate acts on nothing and mints no record")
    func evaluateIsInertWhenAutoHideIsUnreadable() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        dock.readable = false
        let hider = makeHider(dock, settings: settings, capturing: true)

        #expect(hider.evaluate(capturing: true) == .none)
        #expect(hider.weHidIt == false)
        #expect(dock.writes.isEmpty)
        #expect(settings.screenShareHideRecord == nil)

        // And a record preserved by an earlier repair survives the tick that
        // follows it, instead of being re-stamped by a blind hide.
        settings.screenShareHideRecord = ScreenShareHideRecord(hiddenAt: Date(timeIntervalSince1970: 1))
        #expect(hider.evaluate(capturing: true) == .none)
        #expect(settings.screenShareHideRecord?.hiddenAt == Date(timeIntervalSince1970: 1))
    }

    @Test("Write-ahead: a failed hide write never leaves a claim behind")
    func writeAheadOrdering() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        dock.writeSucceeds = false          // the private symbol is gone
        let hider = makeHider(dock, settings: settings)

        #expect(hider.evaluate(capturing: true) == .hide)
        #expect(hider.weHidIt == false)
        #expect(settings.screenShareHideRecord == nil)   // never claim a hide we failed to make
        #expect(dock.writes.isEmpty)
    }

    @Test("Write-behind: a failed restore write keeps the claim alive")
    func writeBehindOrdering() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        let hider = makeHider(dock, settings: settings)
        #expect(hider.evaluate(capturing: true) == .hide)

        dock.writeSucceeds = false          // the restore write fails
        #expect(hider.evaluate(capturing: false) == .restore)

        // The claim outlives the failure instead of being dropped on the floor,
        // so the next launch can still repair.
        #expect(settings.screenShareHideRecord != nil)
        #expect(dock.autoHide)
    }

    @Test("Repairs a Dock left auto-hidden by a killed process (the issue #29 fix)")
    func repairsAfterAKill() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)

        // Process 1: hides for a capture, then is SIGKILLed — no teardown runs.
        let killed = makeHider(dock, settings: settings, capturing: true)
        #expect(killed.evaluate(capturing: true) == .hide)
        #expect(dock.autoHide)
        #expect(settings.screenShareHideRecord != nil)

        // Process 2: launches with no capture running.
        let relaunched = makeHider(dock, settings: settings, capturing: false)
        #expect(relaunched.repairIfNeeded(featureActive: true) == .restore)
        #expect(dock.autoHide == false)
        #expect(settings.screenShareHideRecord == nil)
        #expect(relaunched.weHidIt == false)

        // …and the feature is no longer poisoned: a later capture hides again.
        let later = makeHider(dock, settings: settings, capturing: true)
        #expect(later.evaluate(capturing: true) == .hide)
        #expect(dock.autoHide)
    }

    @Test("Adopts rather than un-hides when the capture is still running (no mid-share flash)")
    func adoptsAcrossAKillWhileCapturing() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)

        let killed = makeHider(dock, settings: settings, capturing: true)
        #expect(killed.evaluate(capturing: true) == .hide)

        // Relaunch mid-capture with the poll about to start.
        let relaunched = makeHider(dock, settings: settings, capturing: true)
        #expect(relaunched.repairIfNeeded(featureActive: true) == .adopt)
        #expect(dock.writes == [true])   // exactly the original hide — the Dock never flashes
        #expect(relaunched.weHidIt)
        #expect(settings.screenShareHideRecord != nil)

        // The ordinary capture-stop restore then puts it back.
        #expect(relaunched.evaluate(capturing: false) == .restore)
        #expect(dock.autoHide == false)
        #expect(settings.screenShareHideRecord == nil)
    }

    @Test("Never clobbers a setting the user has lived with (past the attribution window)")
    func neverClobbersASettledUserPreference() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: true)   // auto-hide is on, from eight days ago
        settings.screenShareHideRecord = ScreenShareHideRecord(
            hiddenAt: Date().addingTimeInterval(-8 * 24 * 3600)
        )
        let hider = makeHider(dock, settings: settings)

        #expect(hider.repairIfNeeded(featureActive: true) == .discard)
        #expect(dock.writes.isEmpty)          // not even a redundant write
        #expect(dock.autoHide)                // left exactly as the user has it
        #expect(settings.screenShareHideRecord == nil)
    }

    @Test("Discards for free when auto-hide is already back off")
    func discardsWhenAutoHideIsAlreadyOff() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        settings.screenShareHideRecord = ScreenShareHideRecord()
        let hider = makeHider(dock, settings: settings)

        #expect(hider.repairIfNeeded(featureActive: true) == .discard)
        #expect(dock.writes.isEmpty)
        #expect(settings.screenShareHideRecord == nil)
    }

    @Test("Keeps the record when auto-hide is unreadable, so a later macOS can still repair")
    func keepsTheRecordWhenAutoHideIsUnreadable() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: true)
        dock.readable = false                 // CoreDockGetAutoHideEnabled did not resolve
        settings.screenShareHideRecord = ScreenShareHideRecord()
        let hider = makeHider(dock, settings: settings)

        #expect(hider.repairIfNeeded(featureActive: true) == .none)
        #expect(dock.writes.isEmpty)
        #expect(settings.screenShareHideRecord != nil)
    }

    @Test("Manual recovery works with no record at all (the pre-fix rescue path)")
    func manualRestoreWorksWithNoRecord() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: true)   // poisoned by a build that predates the record
        let hider = makeHider(dock, settings: settings)
        #expect(settings.screenShareHideRecord == nil)
        #expect(hider.weHidIt == false)

        #expect(hider.restoreAutoHideByUserRequest())
        #expect(dock.autoHide == false)
        #expect(dock.writes == [false])
    }

    @Test("Manual recovery reports failure and claims nothing when the write can't land")
    func manualRestoreReportsFailure() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: true)
        settings.screenShareHideRecord = ScreenShareHideRecord()
        dock.writeSucceeds = false
        let hider = makeHider(dock, settings: settings)

        #expect(hider.restoreAutoHideByUserRequest() == false)
        #expect(settings.screenShareHideRecord != nil)   // untouched
        #expect(dock.autoHide)
    }

    /// The floor under the floor: DK-FR-013's Failure behavior notes that a
    /// manual restore taken *during* a live capture is re-hidden within one
    /// poll. Turning the feature off is the exit from that loop, and it restores
    /// on the way — so the user is never stuck without a recovery.
    @Test("Turning the feature off is the exit from a re-hide loop")
    func featureOffRestoresEvenWhileCapturing() {
        let settings = makeTestSettings("ScreenShareRepair")
        let dock = FakeDock(autoHide: false)
        let hider = makeHider(dock, settings: settings, capturing: true)
        #expect(hider.evaluate(capturing: true) == .hide)

        // What AppState.applyScreenShareHiderState() does when the toggle is
        // switched off while a capture is still running.
        hider.stop()

        #expect(dock.autoHide == false)
        #expect(hider.weHidIt == false)
        #expect(settings.screenShareHideRecord == nil)
    }

    @Test("The record round-trips through Settings and clears on nil")
    func recordRoundTrips() {
        let settings = makeTestSettings("ScreenShareRepair")
        #expect(settings.screenShareHideRecord == nil)

        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        settings.screenShareHideRecord = ScreenShareHideRecord(hiddenAt: stamp)
        #expect(settings.screenShareHideRecord?.hiddenAt == stamp)

        settings.screenShareHideRecord = nil
        #expect(settings.screenShareHideRecord == nil)
    }

    @Test("The record is not externally observed (ADR-011 coordinator-interaction claim)")
    func recordIsNotExternallyObserved() {
        // Observing it would turn every hide and every restore into a
        // `.settingsChanged` event and a full reconcile. Guards the claim
        // against a future edit that "helpfully" adds the key to the list.
        #expect(Settings.externallyObservedKeys.contains("screenShareHideRecord") == false)
    }

    @Test("The record is not a registered default — absence has to stay a real state")
    func recordIsNotARegisteredDefault() {
        // A registered default cannot be removed, so registering this key would
        // make "no record held" unrepresentable.
        #expect(makeTestSettings("ScreenShareRepair").screenShareHideRecord == nil)
    }
}
