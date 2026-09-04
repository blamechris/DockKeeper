import CoreGraphics
import Foundation

/// What a *running* DockKeeper holds, published so another process can read it
/// (DK-FR-015, ADR-016).
///
/// Every other guard surface re-derives. `--diagnostics` builds a fresh
/// `Settings()`, re-enumerates displays and re-runs `BottomDockGuard.decide` in
/// a process that has never held a tap; the Preferences caption is live but is a
/// truncated string in a GUI. So the two halves could disagree, and twice they
/// did — a report saying `guarding 1 display(s)` while the tap had never armed
/// (#77), and a report saying `off — not enabled in Preferences` while the tap
/// was actively clamping the pointer to `y = -3`. Both halves behaved as built:
/// the app holds live state, the report re-derives from disk, and an external
/// `defaults write` the app never observed put them out of step.
///
/// This record is the observation the reports were missing. It is written by the
/// instance that owns the tap and read by anyone; nothing in it is derived by
/// the reader.
///
/// **It is a belief, not a proof.** The record says what the running app thinks;
/// it cannot say whether the tap is really filtering events, and a reader must
/// never present it as more than that. What it *can* do is make the app's belief
/// comparable with the disk, which is exactly the divergence nobody could see.
public struct LiveGuardRecord: Codable, Equatable, Sendable {

    /// Wire-format version. Bumped only for a change an older reader would
    /// misinterpret — never for an added optional field.
    ///
    /// A reader decodes this first and refuses a number it does not know, rather
    /// than best-effort parsing fields whose meaning may have moved. Failing
    /// closed matters more here than anywhere else in the app: the entire value
    /// of this feature is that it does not produce confident wrong answers.
    public static let currentSchema = 1

    public let schema: Int

    /// Who published this, as a kernel identity rather than a bare pid — the
    /// only thing that lets a reader prove the writer is still alive.
    public let writer: ProcessIdentity

    /// `CFBundleShortVersionString` of the *running* process, or `nil` when it
    /// is running unbundled (`swift run DockKeeper`, where there is no
    /// `Info.plist` to read and LaunchServices registers a null bundle id).
    public let appVersion: String?

    /// Where the running copy lives.
    ///
    /// It embeds the user's home directory, so it follows the same rule as
    /// `InstancePeer.bundlePath`: it may reach a report the user reads or
    /// chooses to paste, and it must never reach `os.Logger` (DK-PRIV-001).
    /// Carried here rather than looked up by the reader because
    /// `NSRunningApplication` cannot see an unbundled instance at all, and the
    /// unbundled dev loop is precisely where a wrong answer costs a session.
    public let bundlePath: String?

    /// When this record was last written.
    public let observedAt: Date

    /// When the *substantive* state last changed — the decision, the settings,
    /// the permission, or whether the tap is armed.
    ///
    /// Deliberately not refreshed by a counter-only write, and that separation
    /// is the whole reason there are two timestamps. `observedAt` answers "how
    /// fresh is this reading"; `stateChangedAt` answers "how long has it been
    /// like this". Folding them into one field makes the second question
    /// unanswerable the moment the guard starts clamping, because every clamp
    /// refreshes the write.
    public let stateChangedAt: Date

    /// The settings the running instance is actually holding, which is the half
    /// of the divergence the disk cannot supply.
    public let held: HeldSettings

    /// `AXIsProcessTrusted()` **as the running app sees it**.
    ///
    /// This is the fix for #77. TCC answers that call for the *responsible*
    /// process, so a `--diagnostics` run from a terminal that holds a grant gets
    /// `true` for the terminal while the GUI app has no grant at all — and the
    /// report then prints a guarding verdict for a tap that never armed. Only
    /// the app can answer this about the app.
    public let accessibilityTrusted: Bool

    /// The decision the running instance last computed.
    public let decision: DecisionRecord

    /// The live tap, or `nil` when nothing is armed.
    ///
    /// Optional rather than a flag beside the counters, because the counters are
    /// reset in `BottomDockGuardTap.start()` and **never** in `stop()` — so a
    /// released tap retains the previous run's totals, and a record that carried
    /// them beside an `armed: false` flag would invite exactly the reading the
    /// feature exists to prevent. Making them unreachable when nothing is armed
    /// turns that from a rule someone must remember into one the compiler keeps.
    public let tap: TapRecord?

    /// Dates are stored truncated to whole seconds.
    ///
    /// The wire format is ISO8601 without fractional seconds — chosen because
    /// `defaults read` output is meant to be readable — so a sub-second stamp
    /// does not survive the round trip. That matters more than it looks: the
    /// publisher compares a freshly built record against the one already stored
    /// to decide whether a write is worth making, and a field that changes on
    /// every round trip would defeat that comparison and write on every single
    /// reconcile forever. Truncating on the way in makes the stored form and the
    /// in-memory form the same value.
    public init(
        schema: Int = LiveGuardRecord.currentSchema,
        writer: ProcessIdentity,
        appVersion: String?,
        bundlePath: String?,
        observedAt: Date,
        stateChangedAt: Date,
        held: HeldSettings,
        accessibilityTrusted: Bool,
        decision: DecisionRecord,
        tap: TapRecord?
    ) {
        self.schema = schema
        self.writer = writer
        self.appVersion = appVersion
        self.bundlePath = bundlePath
        self.observedAt = Self.wholeSeconds(observedAt)
        self.stateChangedAt = Self.wholeSeconds(stateChangedAt)
        self.held = held
        self.accessibilityTrusted = accessibilityTrusted
        self.decision = decision
        self.tap = tap
    }

    /// Where this record disagrees with **itself**.
    ///
    /// The record carries both what the app decided and what its tap actually
    /// holds, and those are set one line apart in `applyBottomDockGuard()`. They
    /// should never differ — which is exactly why a reader that can compare them
    /// is worth more than an argument that they cannot.
    ///
    /// This is the half of #77 that a settings comparison cannot reach. That bug
    /// was not a settings disagreement: the app and the disk agreed completely,
    /// and the report still printed `guarding 1 display(s)` for a tap that had
    /// never armed, because TCC answered `AXIsProcessTrusted()` for the terminal
    /// that launched the report rather than for the app. A record that says
    /// "guarding" while carrying no tap states that contradiction outright, from
    /// its own fields, with nothing to compare against.
    ///
    /// Empty is the healthy answer, and a non-empty result is never merely
    /// cosmetic — every entry describes a state in which the guard is not doing
    /// what some surface is claiming it does.
    public var selfContradictions: [String] {
        var out: [String] = []
        switch (decision.kind, tap) {
        case (.guarding, nil):
            out.append("the decision says guarding but no tap is armed")
        case (.idle, .some):
            out.append("the decision is idle but a tap is still armed")
        default:
            break
        }
        if let tap {
            if !tap.systemEnabled {
                // Invisible before this record existed: `isActive` is `tap != nil`,
                // so a tap macOS has disabled reads as armed and filters nothing.
                out.append("the tap is armed but macOS has disabled it, so nothing is being filtered")
            }
            if decision.kind == .guarding, tap.installedZoneCount != decision.zones.count {
                out.append(
                    "the tap holds \(tap.installedZoneCount) span(s) but the decision names \(decision.zones.count)"
                )
            }
        }
        return out
    }

    /// This record with a different `stateChangedAt`.
    ///
    /// Used to carry the original change stamp forward across writes that move
    /// only the counters, so `stateChangedAt` keeps answering "how long has it
    /// been like this" instead of decaying into a second copy of `observedAt`
    /// the moment the guard starts clamping.
    public func withStateChangedAt(_ date: Date) -> LiveGuardRecord {
        LiveGuardRecord(
            schema: schema,
            writer: writer,
            appVersion: appVersion,
            bundlePath: bundlePath,
            observedAt: observedAt,
            stateChangedAt: date,
            held: held,
            accessibilityTrusted: accessibilityTrusted,
            decision: decision,
            tap: tap
        )
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// The fields whose change is *substantive* — everything a user or a
    /// maintainer would call a state change, and nothing that merely counts.
    ///
    /// Used both to decide whether a write is worth making (DK-NFR-001: an
    /// unchanged rewrite spends the quietness budget to say nothing new) and to
    /// carry `stateChangedAt` forward across the writes that only move counters.
    /// The two uses are the same predicate on purpose: a field that does not
    /// force a write must not claim to have changed the state either.
    public func describesSameStateAs(_ other: LiveGuardRecord) -> Bool {
        held == other.held
            && accessibilityTrusted == other.accessibilityTrusted
            && decision == other.decision
            && tap?.armedAt == other.tap?.armedAt
            && tap?.installedZoneCount == other.tap?.installedZoneCount
            && tap?.systemEnabled == other.tap?.systemEnabled
    }

    // MARK: - Nested wire types

    /// The settings the running instance holds in memory.
    ///
    /// Three fields, not the whole of `Settings`, and the choice is the point:
    /// these are the inputs to `BottomDockGuard.decide` that a user can change
    /// from outside the app. `lockBottomDockToDisplay` is the one that caused
    /// the false negative — it is absent from `Settings.externallyObservedKeys`,
    /// so an external `defaults write` to it is invisible to a running app, and
    /// nothing could see the resulting disagreement until this record existed.
    public struct HeldSettings: Codable, Equatable, Sendable {
        public let isEnabled: Bool
        public let lockEdge: DockOrientation
        public let lockBottomDockToDisplay: Bool

        public init(isEnabled: Bool, lockEdge: DockOrientation, lockBottomDockToDisplay: Bool) {
            self.isEnabled = isEnabled
            self.lockEdge = lockEdge
            self.lockBottomDockToDisplay = lockBottomDockToDisplay
        }
    }

    /// A `BottomDockGuard.Decision` projected onto the wire.
    ///
    /// **Not** `Decision: Codable`. Synthesised `Decodable` on `ClampZone` would
    /// restore `clampY` memberwise and bypass `ClampZone(displayID:frame:)`,
    /// which derives it as `frame.maxY - guardBand` — so a hand-edited or
    /// version-skewed record could mint a zone whose band contradicts its own
    /// frame. Carrying the frame and rebuilding through the real initialiser
    /// makes that unrepresentable.
    ///
    /// The idle reason travels as its **rendered sentence** rather than as a
    /// case. `IdleReason` has eleven cases today and gains more as the guard
    /// learns new refusals; an older CLI reading a newer app's record would have
    /// to report "corrupt" for a reason it simply had not heard of, which is a
    /// confident wrong answer about the one thing this feature promises to get
    /// right. A string lets it print the newer app's reason verbatim.
    public struct DecisionRecord: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case idle
            case guarding
        }

        public let kind: Kind
        /// Present exactly when `kind == .idle`.
        public let idleExplanation: String?
        public let zones: [ZoneRecord]
        public let skippedDisplayIDs: [UInt32]
        public let partiallyGuardedDisplayIDs: [UInt32]

        public init(
            kind: Kind,
            idleExplanation: String?,
            zones: [ZoneRecord],
            skippedDisplayIDs: [UInt32],
            partiallyGuardedDisplayIDs: [UInt32]
        ) {
            self.kind = kind
            self.idleExplanation = idleExplanation
            self.zones = zones
            self.skippedDisplayIDs = skippedDisplayIDs
            self.partiallyGuardedDisplayIDs = partiallyGuardedDisplayIDs
        }

        /// Project a live decision onto the wire.
        public init(_ decision: BottomDockGuard.Decision) {
            switch decision {
            case .idle(let reason):
                self.init(
                    kind: .idle,
                    idleExplanation: reason.explanation,
                    zones: [],
                    skippedDisplayIDs: [],
                    partiallyGuardedDisplayIDs: []
                )
            case .guarding(let zones, let skipped, let partial):
                self.init(
                    kind: .guarding,
                    idleExplanation: nil,
                    zones: zones.map(ZoneRecord.init),
                    skippedDisplayIDs: skipped,
                    partiallyGuardedDisplayIDs: partial
                )
            }
        }

        /// Rebuild a `Decision` for the *guarding* case, so the reader can render
        /// through `BottomDockGuard.diagnosticsLine(for:paused:)` — the function
        /// that already encodes #83's displays-versus-spans lesson — rather than
        /// a parallel renderer that would have to learn it again.
        ///
        /// `nil` for an idle record, because an idle `Decision` would need an
        /// `IdleReason` case and this record deliberately carries only the
        /// sentence. The reader prints that sentence directly; there is nothing
        /// to reconstruct and nothing to count.
        public var guardingDecision: BottomDockGuard.Decision? {
            guard kind == .guarding else { return nil }
            return .guarding(
                zones: zones.map(\.clampZone),
                skipped: skippedDisplayIDs,
                partiallyGuarded: partiallyGuardedDisplayIDs
            )
        }
    }

    /// One guarded span, as frame and display id only.
    public struct ZoneRecord: Codable, Equatable, Sendable {
        public let displayID: UInt32
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(displayID: UInt32, x: Double, y: Double, width: Double, height: Double) {
            self.displayID = displayID
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public init(_ zone: BottomDockGuard.ClampZone) {
            self.init(
                displayID: zone.displayID,
                x: Double(zone.frame.origin.x),
                y: Double(zone.frame.origin.y),
                width: Double(zone.frame.size.width),
                height: Double(zone.frame.size.height)
            )
        }

        /// Rebuilt through `ClampZone`'s only initialiser, so `clampY` is
        /// derived here exactly as it was derived in the app.
        public var clampZone: BottomDockGuard.ClampZone {
            BottomDockGuard.ClampZone(
                displayID: displayID,
                frame: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    /// The armed tap's vitals.
    public struct TapRecord: Codable, Equatable, Sendable {
        /// When this arming began — the window the counters below are counted
        /// over, carried inside the same value so a count can never be rendered
        /// without it.
        public let armedAt: Date
        /// Spans the tap is actually holding.
        ///
        /// Read off the tap rather than off the decision, so the two can be
        /// compared. They are set one line apart in `applyBottomDockGuard()` and
        /// should never differ — which is exactly why a reader that can see both
        /// is worth more than an argument that they cannot.
        public let installedZoneCount: Int
        /// `CGEvent.tapIsEnabled` — whether macOS currently has the tap
        /// *filtering*, which is a different question from whether it exists.
        ///
        /// The app's own `isActive` is `tap != nil` and nothing more, so between
        /// a `tapDisabledByTimeout` and the next event that re-enables it the
        /// guard looks armed and is not filtering anything. Nothing in the
        /// codebase could see that state before this field.
        public let systemEnabled: Bool
        public let clampCount: Int
        public let reenableCount: Int

        public init(
            armedAt: Date,
            installedZoneCount: Int,
            systemEnabled: Bool,
            clampCount: Int,
            reenableCount: Int
        ) {
            self.armedAt = Date(timeIntervalSince1970: armedAt.timeIntervalSince1970.rounded(.down))
            self.installedZoneCount = installedZoneCount
            self.systemEnabled = systemEnabled
            self.clampCount = clampCount
            self.reenableCount = reenableCount
        }
    }
}
