import AppKit
import Darwin
import DockKeeperCore

/// Exits immediately when another DockKeeper already owns this user's Dock, so
/// a second launch never starts a second engine (DK-FR-012, ADR-012).
///
/// Why an in-process check at all, when LaunchServices already dedupes: LS keys
/// its already-running test on the bundle's **inode identity**, and
/// `Scripts/build-app.sh` does `rm -rf` + rebuild, so every dev build — and
/// every in-place app upgrade — presents as a brand-new application. The same
/// applies to a second copy of the bundle at a second path.
///
/// There is deliberately no alert and no window: this is an `LSUIElement` agent
/// with nothing to show, and a modal at launch would be worse than the silence.
/// The bail is recorded to the unified log and to stderr, so `run-app.sh` and a
/// direct invocation both show *why* no menu-bar icon appeared.
enum SingleInstance {

    /// Called from `DockKeeperApp.init()`, strictly after
    /// `Diagnostics.runIfRequested()` and before the `@StateObject` autoclosure
    /// builds `AppState`. Returns only when this process should keep launching.
    @MainActor
    static func yieldIfDuplicate() {
        // An unbundled build (`swift run DockKeeper`, a bare `.build/debug`
        // binary) has no bundle identifier, so LaunchServices can neither see it
        // nor be asked about it. Leave the developer loop alone rather than
        // pretend to guard it — see ADR-012's Consequences.
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        // ProcessInfo, not NSRunningApplication.current: the latter reports
        // pid -1 and a nil launchDate at App.init() for a directly-exec'd
        // bundled binary (measured), and a -1 self rank outranks every peer.
        let selfPID = ProcessInfo.processInfo.processIdentifier

        let peers = otherRunningInstances(bundleID: bundleID, selfPID: selfPID)
            .map { app -> InstancePeer in
                let info = processInfo(of: app.processIdentifier)
                return InstancePeer(
                    pid: app.processIdentifier,
                    launchDate: info?.startTime ?? app.launchDate,
                    bundlePath: app.bundleURL?.path,
                    uid: info?.uid
                )
            }

        guard case .yield(let incumbent) = InstanceGuard.decide(
            selfPID: selfPID,
            selfLaunchDate: processInfo(of: selfPID)?.startTime ?? NSRunningApplication.current.launchDate,
            selfUID: getuid(),
            peers: peers
        ) else { return }

        let incumbentPath = incumbent.bundlePath ?? "unknown path"
        Log.app.notice("Duplicate launch: pid \(incumbent.pid, privacy: .public) already running; exiting")

        let notice = """
            DockKeeper is already running (pid \(incumbent.pid), \(incumbentPath)).
            This launch is exiting so the two cannot fight over the Dock.
            Quit the running copy first, or set \
            \(InstanceGuard.allowMultipleEnvironmentKey)=1 to run both anyway.

            """
        try? FileHandle.standardError.write(contentsOf: Data(notice.utf8))

        // EXIT_SUCCESS, matching Diagnostics.runIfRequested() — a login item
        // that correctly deferred to the incumbent must not read as a failed
        // launch. Never NSApp.terminate(nil): there is no NSApplication yet at
        // App.init(), and merely reading NSApplication.shared would create one.
        exit(EXIT_SUCCESS)
    }

    /// Every *other* live process claiming `bundleID`. One spelling, shared with
    /// `Diagnostics` so the guard and the support report can never disagree
    /// about who counts as a peer.
    ///
    /// `isTerminated` is checked because a peer can die between the
    /// LaunchServices query and the decision; yielding to a corpse would leave
    /// the user with no instance at all, and an `LSUIElement` agent has no
    /// surface on which to say so.
    @MainActor
    static func otherRunningInstances(bundleID: String, selfPID: pid_t) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier > 0 && $0.processIdentifier != selfPID && !$0.isTerminated }
    }

    /// Kernel process start time **and owning uid** — the one identity every
    /// live process has, and the one that says whose Dock it is contending for.
    ///
    /// This is load-bearing, not a nicety. `NSRunningApplication.launchDate` is
    /// `nil` for the whole lifetime of a directly-`exec`ed bundle binary
    /// (measured), *and it is nil in the peer's view too* — so ranking a
    /// missing date last (which a direct-`exec` newcomer needs, or it would
    /// outrank the registered incumbent) would simultaneously rank a
    /// direct-`exec`ed **incumbent** below every later registered launch, and
    /// both would run. The ordering cannot have it both ways with a `nil` class
    /// present, so the `nil` class is removed here instead: `sysctl` answers for
    /// every peer, from a single clock, and the answer is a pure function of the
    /// pid — identical in every process, so the total order stays global.
    ///
    /// `InstanceGuard`'s identity-known rank component survives as the fallback
    /// for the residual case where `sysctl` fails too.
    ///
    /// The **uid comes out of the same call**, which is why session scoping is
    /// free here: `kinfo_proc` already carries `kp_eproc.e_ucred.cr_uid`
    /// (measured — self reports 501 on this machine, launchd reports 0), so no
    /// second syscall and no new API is needed to tell another user's DockKeeper
    /// from a genuine duplicate. Both fields therefore share one lookup and one
    /// failure mode: if `sysctl` fails, neither is known, and `InstancePeer`
    /// answers `sameSession(as:)` with `false` for exactly that reason.
    static func processInfo(of pid: pid_t) -> (startTime: Date, uid: uid_t)? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        let date = Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
        return (date, info.kp_eproc.e_ucred.cr_uid)
    }
}
