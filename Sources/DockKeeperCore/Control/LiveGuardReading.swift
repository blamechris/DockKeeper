import Foundation

/// How a stored `LiveGuardRecord` came back off disk.
///
/// Three cases, not `LiveGuardRecord?`, and the third is the reason. The
/// `pauseRecord` precedent degrades an undecodable value to `nil` — correct
/// there, because "not paused" is a true and safe reading of a broken pause
/// record. Here `nil` would mean "no instance is publishing", which is a
/// different claim from "an instance published something I could not read", and
/// collapsing the two is precisely the class of confident wrong answer
/// DK-FR-015 exists to remove.
public enum StoredLiveGuardRecord: Equatable, Sendable {
    case absent
    case unreadable(String)
    /// The stored value is a well-formed envelope naming a schema this build
    /// does not know.
    ///
    /// Distinguished from `.unreadable` because it is decided *before* the
    /// payload is parsed. A newer record may have moved the meaning of a field
    /// this build thinks it understands, so decoding it and reporting the
    /// resulting mismatch as corruption would be both wrong and unhelpful — the
    /// two halves are simply different versions, and that is an answer with an
    /// obvious user action attached.
    case wrongSchema(found: Int)
    case present(LiveGuardRecord)
}

/// Another DockKeeper process this machine can see, supplied by the reader as
/// *context* — never as the liveness verdict.
///
/// It comes from `NSRunningApplication`, which resolves by bundle identifier and
/// therefore cannot see an unbundled instance at all: a `swift run DockKeeper`
/// checks in with LaunchServices under a null bundle id (the same fact that puts
/// it outside the single-instance guard, DK-FR-012 S7). Using it as the liveness
/// test would reproduce the exact false negative this feature exists to kill, in
/// the dev loop where it costs the most. The record's own kernel identity is the
/// verdict; this only makes the *absence* of a record explicable.
public struct ObservedInstance: Equatable, Sendable {
    public let pid: pid_t
    public let bundlePath: String?
    public let version: String?

    public init(pid: pid_t, bundlePath: String?, version: String?) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.version = version
    }
}

/// This machine's on-disk settings, for comparison against what a running
/// instance holds.
///
/// A deliberately tiny value rather than a `Settings` handle. The renderer must
/// be structurally unable to re-derive anything, and the cheapest way to
/// guarantee that is to hand it three plain fields instead of the object that
/// could answer any question.
public struct DiskSettings: Equatable, Sendable {
    public let isEnabled: Bool
    public let lockEdge: DockOrientation
    public let lockBottomDockToDisplay: Bool

    public init(isEnabled: Bool, lockEdge: DockOrientation, lockBottomDockToDisplay: Bool) {
        self.isEnabled = isEnabled
        self.lockEdge = lockEdge
        self.lockBottomDockToDisplay = lockBottomDockToDisplay
    }
}

/// What a reader is entitled to say about a stored record.
///
/// **Only `.live` carries the record.** Every other case carries the writer's
/// identity and nothing else, which turns "never present a dead writer's state
/// as live" from a rule a reviewer has to police into one the compiler enforces:
/// a renderer handed a `.writerGone` has no decision, no zones and no counters
/// to print, because they are not reachable from the value.
public enum LiveGuardReading: Equatable, Sendable {
    /// The writer is alive and is the same process that wrote this.
    case live(LiveGuardRecord)
    /// Nothing has been published.
    case noRecord
    /// A record exists but this reader cannot interpret it.
    case unreadable(String)
    /// A record exists and names a schema this reader does not know. Named
    /// separately from `.unreadable` because it is the one failure with an
    /// obvious user action — the two halves are different versions.
    case futureSchema(found: Int, expected: Int)
    /// The pid named by the record is not running. The record outlived its
    /// writer, which means the writer died by a route that skipped its own
    /// cleanup: `SIGKILL`, Force Quit, a crash, or the logout kill.
    case writerGone(pid: pid_t, observedAt: Date)
    /// The pid is running, but it is a *different* process — the pid was reused.
    case writerReplaced(pid: pid_t, observedAt: Date)
    /// The record was published by another user's process. Under fast user
    /// switching that is a different app managing a different Dock, and it is
    /// not this session's live state.
    case otherUser(pid: pid_t, uid: uid_t)

    /// Classify a stored record against the live process table.
    ///
    /// Pure, with the kernel injected. That is what makes dead-writer, reused-pid
    /// and foreign-uid reachable from `swift test` in `DockKeeperCore` with no
    /// hardware, no running app, and no waiting — the three verdicts that matter
    /// most and that an on-device test could only produce by killing something.
    ///
    /// Liveness is decided against the process table and never against a clock.
    /// No timestamp in the record is consulted here, on purpose: an age
    /// threshold would need a tolerance, a tolerance is a guess, and a guess is
    /// how an instrument starts lying. `observedAt` is reported to the user as
    /// freshness; it is never evidence of life.
    public static func classify(
        stored: StoredLiveGuardRecord,
        writerIdentityNow: (pid_t) -> ProcessIdentity?,
        readerUID: uid_t
    ) -> LiveGuardReading {
        switch stored {
        case .absent:
            return .noRecord
        case .unreadable(let reason):
            return .unreadable(reason)
        case .wrongSchema(let found):
            return .futureSchema(found: found, expected: LiveGuardRecord.currentSchema)
        case .present(let record):
            guard let now = writerIdentityNow(record.writer.pid) else {
                return .writerGone(pid: record.writer.pid, observedAt: record.observedAt)
            }
            // Exact integer equality on whole microseconds. A recycled pid is a
            // live process with a *later* start time, so this is the whole of
            // the pid-reuse defence and it needs no window.
            guard now.startedAtMicroseconds == record.writer.startedAtMicroseconds else {
                return .writerReplaced(pid: record.writer.pid, observedAt: record.observedAt)
            }
            guard now.uid == readerUID else {
                return .otherUser(pid: record.writer.pid, uid: now.uid)
            }
            return .live(record)
        }
    }
}
