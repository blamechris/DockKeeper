import Foundation

/// Whether a candidate record is worth writing, and what to write (DK-FR-015).
///
/// This is the only branching logic on the feature's *write* path, which is why
/// it is here rather than in `AppState` beside the code that calls it. The app
/// target has no test coverage and cannot be given any, so policy left there is
/// policy nobody can check — the standing rule that moved every string derived
/// from a guard decision into Core (#84). What remains in the app is the
/// gathering of live values and one call to this function.
public enum LiveGuardPublisher {

    public enum Action: Equatable, Sendable {
        /// Write this record. It may differ from the candidate: an unchanged
        /// state carries its original `stateChangedAt` forward.
        case write(LiveGuardRecord)
        /// Leave the store alone.
        case skip
    }

    /// Decide what to publish.
    ///
    /// Compared against what is actually **stored**, never against a
    /// process-local memo of the last write. A memo cannot see a record that
    /// something else cleared or overwrote, so it would suppress the very
    /// republish that repairs it, and a reader would go on reporting that no
    /// instance had published while this one was running and healthy.
    ///
    /// Three rules, in order:
    ///
    /// 1. **Anything not ours, or not there, is replaced.** A record written by
    ///    another process, a cleared key, an unreadable value and an unknown
    ///    schema all mean the same thing to a publisher: what is stored does not
    ///    describe this instance, so publish.
    /// 2. **A substantive change is written.** `describesSameStateAs` is the
    ///    predicate, and it deliberately ignores the counters — see there.
    /// 3. **Unchanged: write only while a tap is armed, or when a counter moved.**
    ///    The armed case is a heartbeat, and it is scoped that narrowly on
    ///    purpose. `observedAt` is the only staleness signal a reader has, and
    ///    with writes suppressed it silently stops meaning "when this was last
    ///    observed" and starts meaning "when it last changed" — at which point a
    ///    healthy idle instance and one whose run loop has wedged are
    ///    byte-identical, while the wedged one has had its tap disabled by macOS
    ///    and is guarding nothing. Refreshing while armed is exactly the window
    ///    where that difference can hurt someone. An idle instance — every
    ///    install with the feature off, which is the default — settles into
    ///    writing nothing at all, which is what DK-NFR-001 asks of a record with
    ///    nothing new to say.
    public static func next(
        candidate: LiveGuardRecord,
        stored: StoredLiveGuardRecord
    ) -> Action {
        guard
            case .present(let stored) = stored,
            stored.writer == candidate.writer,
            stored.describesSameStateAs(candidate)
        else {
            return .write(candidate)
        }
        let countersMoved = stored.tap?.clampCount != candidate.tap?.clampCount
            || stored.tap?.reenableCount != candidate.tap?.reenableCount
        guard candidate.tap != nil || countersMoved else { return .skip }
        // The original change stamp is carried forward, so `stateChangedAt` keeps
        // answering "how long has it been like this" rather than decaying into a
        // second copy of `observedAt` once the guard starts clamping.
        return .write(candidate.withStateChangedAt(stored.stateChangedAt))
    }

    /// Whether a quitting instance may withdraw the stored record.
    ///
    /// **Ownership-checked, and that is not a nicety.** DK-FR-012 documents two
    /// supported modes in which a second instance runs — an unbundled
    /// `swift run`, and `DOCKKEEPER_ALLOW_MULTIPLE_INSTANCES=1` — and both share
    /// this one key. An unconditional retraction would let one instance's quit
    /// delete a *live* instance's record, after which the reader would report
    /// that nothing had published about an app that is running and guarding.
    /// That is the class of wrong answer this requirement exists to remove.
    ///
    /// A record that cannot be read is likewise left alone. It is not ours to
    /// delete, and destroying it would take the evidence with it.
    public static func shouldRetract(
        stored: StoredLiveGuardRecord,
        writer: ProcessIdentity
    ) -> Bool {
        guard case .present(let stored) = stored else { return false }
        return stored.writer == writer
    }
}
