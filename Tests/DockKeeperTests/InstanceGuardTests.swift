import Testing
import Foundation
@testable import DockKeeperCore

/// Two logged-in users, as the guard sees them.
enum TestUID {
    static let me: uid_t = 501
    static let otherUser: uid_t = 502
}

@Suite("InstanceGuard.decide (DK-FR-012)")
struct InstanceGuardTests {

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    /// Peers default to **our** uid, so every pre-existing seniority test keeps
    /// describing a single-session world and continues to test exactly what it
    /// always did. Cross-session behaviour is exercised deliberately, in
    /// `InstanceGuardSessionTests` below.
    private func peer(_ pid: pid_t, _ date: Date?, path: String? = nil,
                      uid: uid_t? = TestUID.me) -> InstancePeer {
        InstancePeer(pid: pid, launchDate: date, bundlePath: path, uid: uid)
    }

    /// Always pass explicit argv/environment: the defaults read the *test
    /// runner's* CommandLine and environment, which would make these tests
    /// depend on how they were invoked.
    private func decide(selfPID: pid_t, selfLaunchDate: Date?, peers: [InstancePeer],
                        selfUID: uid_t = TestUID.me,
                        arguments: [String] = ["DockKeeper"],
                        environment: [String: String] = [:]) -> InstanceDecision {
        InstanceGuard.decide(selfPID: selfPID, selfLaunchDate: selfLaunchDate, selfUID: selfUID,
                             peers: peers, arguments: arguments, environment: environment)
    }

    @Test("No peers — the only instance proceeds")
    func soleInstance() {
        #expect(decide(selfPID: 42, selfLaunchDate: newer, peers: []) == .proceed)
    }

    @Test("A peer list containing only ourselves proceeds")
    func selfIsNotAPeer() {
        #expect(decide(selfPID: 42, selfLaunchDate: newer, peers: [peer(42, newer)]) == .proceed)
    }

    @Test("A later launch yields to the running instance")
    func newcomerYields() {
        let incumbent = peer(100, older)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [incumbent, peer(200, newer)])
                == .yield(to: incumbent))
    }

    @Test("A peer that started after us does not make us yield")
    func doesNotYieldToJuniors() {
        #expect(decide(selfPID: 100, selfLaunchDate: older, peers: [peer(200, newer), peer(100, older)])
                == .proceed)
    }

    @Test("Yields regardless of bundle path — cross-path duplicates are the point")
    func pathIndependence() {
        let sameCopy  = peer(100, older, path: "/Users/x/Projects/DockKeeper/dist/DockKeeper.app")
        let otherCopy = peer(101, older, path: "/Applications/DockKeeper.app")
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [sameCopy])  == .yield(to: sameCopy))
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [otherCopy]) == .yield(to: otherCopy))
    }

    @Test("A lower pid does not beat an earlier launch — pids wrap, dates don't")
    func pidWrapAround() {
        let incumbent = peer(99_998, older)
        #expect(decide(selfPID: 3, selfLaunchDate: newer, peers: [incumbent, peer(3, newer)])
                == .yield(to: incumbent))
    }

    /// The residual shape: this process's start time could not be obtained by
    /// any route, and self is absent from its own peer list (the direct-`exec`
    /// caller shape). Without the identity-known rank component, self sorts to
    /// `.distantPast` and wins — the guard becomes a silent no-op.
    @Test("A dateless newcomer yields to a dated incumbent")
    func directExecYields() {
        let incumbent = peer(1_662, older, path: "/Applications/DockKeeper.app")
        #expect(decide(selfPID: 40_763, selfLaunchDate: nil, peers: [incumbent])
                == .yield(to: incumbent))
    }

    /// The field invariant the simultaneous survivor sweep does **not** cover.
    /// The sweep models one population deciding at one instant; reality never
    /// does. A running instance decided in the past, against a smaller
    /// population, and never revisits — so for every settled incumbent, a
    /// newcomer that can see it must yield, with no simultaneity to appeal to.
    ///
    /// This is why `SingleInstance` substitutes the kernel start time for a
    /// missing LaunchServices `launchDate`: with a dateless class present, a
    /// directly-`exec`ed **incumbent** ranked below every dated newcomer and
    /// both ran. Every live peer now has a date, so the incumbent's shape here
    /// is `older` rather than `nil`.
    @Test("A newcomer yields to an already-settled incumbent, whatever the pid order")
    func newcomerYieldsToSettledIncumbent() {
        for (incumbentPID, newcomerPID) in [(pid_t(500), pid_t(900)), (pid_t(900), pid_t(500))] {
            let incumbent = peer(incumbentPID, older)
            for newcomerDate: Date? in [nil, newer] {
                #expect(decide(selfPID: newcomerPID, selfLaunchDate: newcomerDate, peers: [incumbent])
                        == .yield(to: incumbent))
            }
        }
    }

    @Test("A dated process outranks a dateless one regardless of pid")
    func knownIdentityBeatsUnknown() {
        let unregistered = peer(3, nil)
        #expect(decide(selfPID: 99_998, selfLaunchDate: older, peers: [unregistered]) == .proceed)
        #expect(decide(selfPID: 3, selfLaunchDate: nil, peers: [peer(99_998, older)])
                == .yield(to: peer(99_998, older)))
    }

    @Test("--diagnostics is never pre-empted, even against a live instance")
    func oneShotFlagProceeds() {
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [peer(100, older)],
                       arguments: ["DockKeeper", "--diagnostics"]) == .proceed)
    }

    @Test("The escape hatch is exact opt-in: only \"1\" stands the guard down")
    func escapeHatchIsExact() {
        let incumbent = peer(100, older)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [incumbent],
                       environment: [InstanceGuard.allowMultipleEnvironmentKey: "1"]) == .proceed)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [incumbent],
                       environment: [InstanceGuard.allowMultipleEnvironmentKey: "0"])
                == .yield(to: incumbent))
    }

    /// The property the whole design rests on, over every start-time shape, within one session:
    /// exactly one survivor — never two, and never zero. Two-element tests
    /// cannot catch a cyclic comparator; three can. A predicate that compares
    /// some pairs by date and others by pid is cyclic as soon as one date is
    /// absent, and every instance then picks a different incumbent and exits.
    @Test("Any group of simultaneous launches leaves exactly one survivor")
    func exactlyOneSurvivor() {
        let dates: [Date?] = [nil, older, newer]
        let pids: [pid_t] = [3, 500, 99_998]
        for a in dates {
            for b in dates {
                for c in dates {
                    let group = [peer(pids[0], a), peer(pids[1], b), peer(pids[2], c)]
                    let survivors = group.filter {
                        decide(selfPID: $0.pid, selfLaunchDate: $0.launchDate, peers: group) == .proceed
                    }
                    #expect(survivors.count == 1)
                }
            }
        }
    }
}


// MARK: - Session scoping (fast user switching — DK-FR-012, ADR-012)

/// Under fast user switching each logged-in user has their own Dock and
/// legitimately wants their own DockKeeper, so another user's instance is not a
/// duplicate — it is a different app managing a different Dock.
///
/// These exist because the alternative was trusting behaviour Apple does not
/// define across multiple GUI login sessions. The careful reading of that
/// evidence — including what it does and does not say about an app inside a GUI
/// session — lives in the ADR-012 amendment (`docs/decision-log.md`) and is
/// deliberately not restated here, so the two cannot drift. The point for these
/// tests: the guard filters by uid, so the property is true by construction and
/// testable with no second account and no logout.
@Suite("InstanceGuard session scoping")
struct InstanceGuardSessionTests {

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    private func decide(selfPID: pid_t, selfLaunchDate: Date?, peers: [InstancePeer],
                        selfUID: uid_t = TestUID.me) -> InstanceDecision {
        InstanceGuard.decide(selfPID: selfPID, selfLaunchDate: selfLaunchDate, selfUID: selfUID,
                             peers: peers, arguments: ["DockKeeper"], environment: [:])
    }

    @Test("Another user's senior instance is not a duplicate — we still start")
    func foreignSeniorIsIgnored() {
        // The exact fast-user-switching case. Before the uid filter this yielded,
        // and an LSUIElement app that yields simply never appears: user 2 would
        // get no DockKeeper and no error of any kind.
        let otherUsersApp = InstancePeer(pid: 100, launchDate: older, bundlePath: "/Applications/DockKeeper.app",
                                         uid: TestUID.otherUser)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [otherUsersApp]) == .proceed)
    }

    @Test("Our own senior instance still wins — seniority is unchanged within a session")
    func ownSeniorStillYields() {
        let mine = InstancePeer(pid: 100, launchDate: older, bundlePath: nil, uid: TestUID.me)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [mine]) == .yield(to: mine))
    }

    @Test("With one peer per user, we yield to ours and ignore theirs")
    func picksOwnSessionIncumbent() {
        // The foreign peer is the MOST senior, so a guard that ignored uid would
        // name it in the bail message and send the user to kill another user's
        // process — which they cannot even see.
        let theirs = InstancePeer(pid: 50, launchDate: Date(timeIntervalSince1970: 500),
                                  bundlePath: nil, uid: TestUID.otherUser)
        let mine = InstancePeer(pid: 100, launchDate: older, bundlePath: nil, uid: TestUID.me)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [theirs, mine]) == .yield(to: mine))
    }

    @Test("A peer whose uid could not be read is never yielded to")
    func unknownUIDIsNotYieldedTo() {
        // ADR-012's cost asymmetry decides this direction: two visible instances
        // are recoverable, a silent zero-instance launch is not.
        let unknown = InstancePeer(pid: 100, launchDate: older, bundlePath: nil, uid: nil)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [unknown]) == .proceed)
    }

    @Test("Only foreign peers means we are the sole instance for this user")
    func allForeignProceeds() {
        let peers = (1...5).map {
            InstancePeer(pid: pid_t($0), launchDate: older, bundlePath: nil, uid: TestUID.otherUser)
        }
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: peers) == .proceed)
    }

    @Test("uid is compared, not merely present — a third user is foreign too")
    func thirdUserIsAlsoForeign() {
        // Guards against a mutant that checks `uid != nil` instead of equality.
        let third = InstancePeer(pid: 100, launchDate: older, bundlePath: nil, uid: 503)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [third]) == .proceed)
    }

    @Test("Root-owned peers are foreign to a normal user")
    func rootPeerIsForeign() {
        let asRoot = InstancePeer(pid: 100, launchDate: older, bundlePath: nil, uid: 0)
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [asRoot]) == .proceed)
    }

    @Test("With two qualifying peers, the bail names the most senior — not just any")
    func namesTheMostSeniorPeer() {
        // Mutation-motivated: swapping `.min` for `.max` in `decide` passed the
        // entire suite, because every other yielding case has exactly one
        // qualifying peer and the 27-case sweep only counts `.proceed` results.
        // The wrong peer is not a wrong decision — it still yields — but the
        // stderr notice would name the wrong pid and bundle path and send the
        // user to quit the copy that should have survived.
        //
        // Reachable via the escape hatch that same notice advertises: with
        // DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES=1 two same-session instances are
        // live, so a third launch genuinely sees two seniors.
        let eldest = InstancePeer(pid: 300, launchDate: Date(timeIntervalSince1970: 1_000),
                                  bundlePath: "/Applications/DockKeeper.app", uid: TestUID.me)
        let middle = InstancePeer(pid: 100, launchDate: Date(timeIntervalSince1970: 1_500),
                                  bundlePath: "/dist/DockKeeper.app", uid: TestUID.me)
        // `eldest` deliberately carries the HIGHER pid, so a rule that fell back
        // to pid order would pick `middle` and this would fail.
        #expect(decide(selfPID: 200, selfLaunchDate: newer, peers: [middle, eldest])
                == .yield(to: eldest))
    }

    @Test("Session filtering never rescues a junior — ordering still governs")
    func juniorOwnPeerStillLoses() {
        let myJunior = InstancePeer(pid: 300, launchDate: newer, bundlePath: nil, uid: TestUID.me)
        #expect(decide(selfPID: 100, selfLaunchDate: older, peers: [myJunior]) == .proceed)
    }
}
