import Foundation

/// One live DockKeeper process, as another one sees it.
///
/// `launchDate` is when the process started: its LaunchServices launch date, or
/// — for a directly-`exec`ed bundle binary, whose LaunchServices `launchDate` is
/// `nil` for its entire lifetime (measured) — the kernel's process start time.
/// The adapter supplies one or the other so that every live peer has a date; see
/// `SingleInstance.startTime(of:)` for why that substitution is load-bearing
/// rather than cosmetic.
///
/// `nil` therefore means "start time unobtainable by any route", which
/// `rank(_:_:)` sorts last. It is a residual case, not the direct-`exec` case.
public struct InstancePeer: Equatable, Sendable {
    public let pid: pid_t
    public let launchDate: Date?
    /// Carried for the bail message only. It embeds the user's home directory,
    /// so it goes to stderr and to the menu-free diagnostics report — never to
    /// `os.Logger` (DK-PRIV-001).
    public let bundlePath: String?

    /// The uid owning this process, or `nil` when it could not be read.
    ///
    /// This is what makes the guard **session-scoped by construction** instead
    /// of by assumption. Under fast user switching each logged-in user has their
    /// own Dock and legitimately wants their own DockKeeper, so another user's
    /// instance is not a duplicate at all — it is a different app managing a
    /// different Dock. The adapter reads this from the same
    /// `sysctl(KERN_PROC_PID)` it already makes for `launchDate`, so it costs
    /// no extra syscall.
    public let uid: uid_t?

    public init(pid: pid_t, launchDate: Date?, bundlePath: String?, uid: uid_t? = nil) {
        self.pid = pid
        self.launchDate = launchDate
        self.bundlePath = bundlePath
        self.uid = uid
    }
}

extension InstancePeer {

    /// Whether this peer is contending for the **same** Dock as a process
    /// running under `selfUID`.
    ///
    /// An unknown uid answers **`false`** — "do not yield to it" — and that
    /// direction is chosen from ADR-012's own cost asymmetry rather than by
    /// reflex. The guard trades away a *possible* duplicate to avoid a
    /// *silent* zero-instance launch: DockKeeper is `LSUIElement`, so a process
    /// that wrongly yields simply never appears, with no window, no Dock
    /// bounce, no Force Quit row and no error surface. Two instances are
    /// visible and recoverable; zero are neither. That is the same asymmetry
    /// that led ADR-012 to withhold `LSMultipleInstancesProhibited`.
    ///
    /// In practice the unknown case is nearly unreachable: the uid comes from
    /// the same `sysctl` as `launchDate`, so a failure that loses the uid also
    /// loses the date, and a dateless peer already ranks below every dated
    /// newcomer.
    func sameSession(as selfUID: uid_t) -> Bool {
        guard let uid else { return false }
        return uid == selfUID
    }
}

/// What a starting instance should do about the peers it found.
public enum InstanceDecision: Equatable, Sendable {
    /// No peer outranks us — start the engine.
    case proceed
    /// Someone else already owns this user's Dock — exit before touching anything.
    case yield(to: InstancePeer)
}

/// Decides whether a starting DockKeeper is the duplicate (DK-FR-012).
///
/// Pure and `Sendable`; the LaunchServices read and the `exit()` live in
/// `SingleInstance` in the app target (AGENTS rule 8 — system interactions
/// behind an adapter).
///
/// Scoped to the menu-bar app. `dockkeeper-cli` is a legitimate second process
/// driving the Dock, and `StatusSummary.live()` is documented to work with the
/// app not running — neither may ever call this.
public enum InstanceGuard {

    /// Flags that print and exit without starting the app. The guard must never
    /// pre-empt them: `DockKeeper --diagnostics` is the documented support flow
    /// (`README.md`) and is run *while* an instance is live. `Diagnostics`
    /// reads this same set, so the two cannot drift apart.
    public static let oneShotFlags: Set<String> = ["--diagnostics"]

    /// Developer escape hatch for running two on purpose (A/B-ing two builds).
    /// Checked before anything else, and before any side effect, so the
    /// override can never itself become the thing that blocks a real launch.
    public static let allowMultipleEnvironmentKey = "DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES"

    /// - Parameters:
    ///   - selfPID: **`ProcessInfo.processInfo.processIdentifier`**, never
    ///     `NSRunningApplication.current.processIdentifier` — the latter is `-1`
    ///     at `App.init()` for a directly-`exec`ed binary, and a `-1` self rank
    ///     silently outranks every real peer.
    ///   - selfLaunchDate: this process's start time. `nil` only when neither
    ///     LaunchServices nor the kernel could supply one; treated as
    ///     "no identity", which always loses.
    ///   - selfUID: `getuid()`. A peer is only a duplicate if it shares it —
    ///     see `InstancePeer.sameSession(as:)`.
    ///   - peers: other live processes claiming our bundle identifier. May or
    ///     may not include us (it does for a LaunchServices launch, it does not
    ///     for a direct `exec`); entries matching `selfPID` are dropped either way.
    ///   - arguments: pass explicitly from tests. The default reads the *host
    ///     process's* argv, which is the test runner's under `swift test`.
    ///   - environment: same caveat as `arguments`.
    ///
    /// Yields to the most senior peer, where seniority is the lexicographic
    /// tuple `(hasStartTime, startTime, pid)`.
    ///
    /// Three properties this ordering buys, each of which a simpler rule loses:
    ///
    /// 1. **It is a total order**, so `min(by:)` is well-defined and every
    ///    process independently agrees on the same incumbent. A predicate that
    ///    compares *some* pairs by date and *others* by pid is cyclic once any
    ///    date is absent, and a cycle means every instance picks a different
    ///    incumbent and they **all** exit.
    /// 2. **A process with no obtainable start time always loses**, so it can
    ///    never rank itself at `.distantPast` and beat a real incumbent. Note
    ///    that this component cuts both ways — a dateless *peer* is likewise
    ///    ranked below every dated newcomer, which is why the adapter removes
    ///    the dateless case at source (`SingleInstance.startTime(of:)`) rather
    ///    than relying on this component to handle a direct `exec`.
    /// 3. **Date before pid**, because pids wrap near 99999: a lowest-pid-wins
    ///    rule sends a fresh pid 3 past an incumbent pid 99998 and produces
    ///    exactly the duplicate this guard exists to prevent.
    public static func decide(
        selfPID: pid_t,
        selfLaunchDate: Date?,
        selfUID: uid_t,
        peers: [InstancePeer],
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> InstanceDecision {
        if arguments.contains(where: oneShotFlags.contains) { return .proceed }
        if environment[allowMultipleEnvironmentKey] == "1" { return .proceed }

        let mine = rank(selfLaunchDate, selfPID)
        let incumbent = peers
            .filter { $0.pid != selfPID && $0.sameSession(as: selfUID) && rank($0.launchDate, $0.pid) < mine }
            .min { rank($0.launchDate, $0.pid) < rank($1.launchDate, $1.pid) }

        guard let incumbent else { return .proceed }
        return .yield(to: incumbent)
    }

    /// Lower sorts more senior.
    ///
    /// The uid filter deliberately sits in `decide`'s `filter` rather than in
    /// this ordering: it is an identity question ("is this even my peer?"), not
    /// a seniority one, and folding a cross-session comparison into the rank
    /// would break the totality property documented above. Element 0 is 0 when a start time is known and 1
    /// when it is not, so "known" always beats "unknown" regardless of pid; the
    /// date is a placeholder in the unknown case.
    private static func rank(_ launchDate: Date?, _ pid: pid_t) -> (Int, Date, pid_t) {
        (launchDate == nil ? 1 : 0, launchDate ?? .distantPast, pid)
    }
}
