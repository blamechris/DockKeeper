import Foundation

/// A process's kernel identity — the triple that answers "is *that* process
/// still running?" without ever being fooled by a recycled pid.
///
/// A pid alone cannot answer it. pids wrap near 99999, which `InstanceGuard`
/// already reasons about when it ranks peers by start time rather than by pid
/// (see `rank(_:_:)`), and the same wrap is what makes a bare pid useless as a
/// liveness key for DK-FR-015: a snapshot naming pid 4242 reads as live the
/// moment any unrelated process is handed 4242.
///
/// **The start time is whole microseconds as an `Int64`, deliberately not a
/// `Date`.** The whole point of this type is that a comparison is exact, and a
/// `Date` is a `Double` of seconds — round-tripping one through JSON invites a
/// tolerance, and a tolerance is a place for a wrong answer to hide. The kernel
/// hands the value over as a `timeval` of whole seconds and whole microseconds,
/// so carrying it in the units the kernel used keeps `==` meaning what it says.
///
/// The uid rides along because `kinfo_proc` already carries it, so session
/// scoping costs no second syscall — the same argument `SingleInstance`
/// records for its own reader. Under fast user switching another account's
/// DockKeeper is a different app managing a different Dock, and its record must
/// never be reported as this user's live state.
public struct ProcessIdentity: Equatable, Sendable, Codable {

    public let pid: pid_t
    /// Kernel process start time, whole microseconds since the epoch.
    public let startedAtMicroseconds: Int64
    public let uid: uid_t

    public init(pid: pid_t, startedAtMicroseconds: Int64, uid: uid_t) {
        self.pid = pid
        self.startedAtMicroseconds = startedAtMicroseconds
        self.uid = uid
    }

    /// Read the identity of `pid` from the process table, or `nil` when there is
    /// no such process.
    ///
    /// `sysctl(KERN_PROC_PID)` is unprivileged for any pid on the machine — the
    /// same call `SingleInstance.processInfo(of:)` already makes for the
    /// single-instance guard, kept as a second small reader rather than a shared
    /// one on purpose. That reader lives in the app target, which neither the
    /// CLI nor the test bundle links, and promoting it would edit the guard that
    /// decides whether a launch is allowed to live in service of a reporting
    /// feature. The duplication is eleven lines; the coupling would be
    /// permanent. If the two ever disagree it is this one that is wrong, since
    /// the guard's is the older and the more load-bearing.
    ///
    /// `nil` here means "no process with that pid **right now**". It does not
    /// distinguish "never existed" from "exited", and it does not need to: both
    /// are the same verdict for a liveness question.
    public static func of(pid: pid_t) -> ProcessIdentity? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        // A zero-length answer with a zero status is the documented "no such
        // process" reply, and it leaves `info` zeroed rather than filled — so
        // the `size > 0` guard above is load-bearing, not defensive padding.
        let started = info.kp_proc.p_starttime
        return ProcessIdentity(
            pid: pid,
            startedAtMicroseconds: Int64(started.tv_sec) * 1_000_000 + Int64(started.tv_usec),
            uid: info.kp_eproc.e_ucred.cr_uid
        )
    }

    /// This process's own identity, for a writer stamping a record it publishes.
    public static func current() -> ProcessIdentity? {
        of(pid: getpid())
    }
}
