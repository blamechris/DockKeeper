import Testing
import Foundation
@testable import DockKeeperCore

@Suite("InstanceGuard.decide (DK-FR-012)")
struct InstanceGuardTests {

    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    private func peer(_ pid: pid_t, _ date: Date?, path: String? = nil) -> InstancePeer {
        InstancePeer(pid: pid, launchDate: date, bundlePath: path)
    }

    /// Always pass explicit argv/environment: the defaults read the *test
    /// runner's* CommandLine and environment, which would make these tests
    /// depend on how they were invoked.
    private func decide(selfPID: pid_t, selfLaunchDate: Date?, peers: [InstancePeer],
                        arguments: [String] = ["DockKeeper"],
                        environment: [String: String] = [:]) -> InstanceDecision {
        InstanceGuard.decide(selfPID: selfPID, selfLaunchDate: selfLaunchDate, peers: peers,
                             arguments: arguments, environment: environment)
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

    /// The property the whole design rests on, over EVERY identity shape:
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
