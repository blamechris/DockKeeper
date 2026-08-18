import AppKit
import Darwin
import DockKeeperCore

/// Routes the termination signals a menu-bar agent actually receives into the
/// ordinary AppKit quit, so `applicationWillTerminate` — and therefore the Dock
/// auto-hide restore (DK-FR-013) — is not skipped.
///
/// **Why this is needed at all.** AppKit installs no handler for `SIGTERM`, so
/// the default disposition applies and the process dies with no delegate
/// callback. Measured on this rig (macOS 26 / Darwin 25.6, minimal
/// `NSApplication` + delegate): a bare `kill -TERM` exits *without* running
/// `applicationWillTerminate`; the same app with the source below runs it ~3 ms
/// after the signal and exits cleanly. That path is not academic — it is how
/// `Scripts/run-app.sh` stops the previous build on every dev iteration, and it
/// is the shape of a session teardown at logout.
///
/// **Why a dispatch source and not `signal(2)`.** A real signal handler runs in
/// signal context, where only async-signal-safe functions are legal —
/// `NSApp.terminate`, `os.Logger`, and anything main-actor are all off limits,
/// and calling them is undefined behavior, not merely bad style. A
/// `DispatchSourceSignal` is *not* a signal handler: libdispatch catches the
/// signal and then submits the event handler as ordinary work on the queue it
/// was created with. Pinning that queue to `.main` makes the handler
/// main-thread — and therefore main-actor — code that may call anything, which
/// is what `MainActor.assumeIsolated` asserts below (same pattern as
/// `ScreenShareHider`'s timer callback).
///
/// `signal(_, SIG_IGN)` first is mandatory, not belt-and-braces: without it the
/// default terminate-now disposition wins the race and the process never lives
/// long enough for the source to fire.
///
/// **Trade-off, stated plainly (kickoff rule 20).** While this is installed, a
/// wedged main run loop no longer dies on `SIGTERM`. Both senders that matter
/// already escalate — `Scripts/run-app.sh` sends `SIGKILL` 2 s later, and a
/// session teardown does the same — so the degraded case is today's behavior,
/// not a new hang. `SIGKILL` remains untrappable by design and is covered by
/// persisting the hide across launches, not from here.
///
/// One inherited consequence worth knowing: a `SIG_IGN` disposition survives
/// `execve`, so any child this process spawns starts with SIGTERM/SIGINT
/// ignored. Harmless for the millisecond-lived `killall Dock` in
/// `DefaultsDockAdapter.restartDock()`, but a future `Process` that expects
/// `terminate()` (which sends SIGTERM) to stop it must reset the disposition in
/// the child itself.
@MainActor
final class TerminationSignals {

    /// The signals worth converting. `SIGTERM` is the tooling/session-teardown
    /// path; `SIGINT` is Ctrl-C against an unbundled `swift run DockKeeper` in
    /// the dev loop. Nothing else is touched — in particular `SIGHUP` and the
    /// fatal fault signals keep their default behavior, because a crash must
    /// stay a crash.
    private static let handled: [Int32] = [SIGTERM, SIGINT]

    /// Sources must be retained or they are cancelled on deinit.
    private var sources: [DispatchSourceSignal] = []

    /// Install the sources. Idempotent; call once from
    /// `applicationWillFinishLaunching` — the earliest delegate hook, so the
    /// window in which a SIGTERM still exits 143 is as small as AppKit allows.
    func install() {
        guard sources.isEmpty else { return }
        for signalNumber in Self.handled {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    Log.app.notice("Signal \(signalNumber, privacy: .public) received; quitting cleanly")
                    // Converge on the one quit path. The restore lives in
                    // applicationWillTerminate and has exactly one
                    // implementation, reached from every trappable exit.
                    NSApp.terminate(nil)
                }
            }
            source.resume()
            sources.append(source)
        }
    }
}
