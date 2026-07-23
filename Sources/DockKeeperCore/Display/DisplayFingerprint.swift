import Foundation
import CoreGraphics

/// Multi-identifier fingerprint of a display (ADR-004, TDD §7.2).
///
/// A bare UUID is not trustworthy across docks, adapters, and reconnects
/// (stability UNKNOWN — R-003), so the preference stores every identifier we
/// can capture and matching is scored, never assumed.
public struct DisplayFingerprint: Codable, Sendable, Hashable {
    public var uuid: String?
    public var vendorNumber: UInt32?
    public var modelNumber: UInt32?
    /// Frequently 0 on consumer panels — 0 is treated as absent when scoring.
    public var serialNumber: UInt32?
    public var localizedName: String?
    /// False also means "unknown" (e.g. migrated bare-UUID preferences):
    /// scoring only ever uses this field when BOTH sides are true.
    public var isBuiltin: Bool

    public init(
        uuid: String? = nil,
        vendorNumber: UInt32? = nil,
        modelNumber: UInt32? = nil,
        serialNumber: UInt32? = nil,
        localizedName: String? = nil,
        isBuiltin: Bool = false
    ) {
        self.uuid = uuid
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.localizedName = localizedName
        self.isBuiltin = isBuiltin
    }
}

/// Scored matching of a stored fingerprint against connected displays
/// (TDD §7.2). Pure — unit-tested without hardware.
public enum FingerprintMatcher {

    /// A connected display offered for matching.
    public struct Candidate: Sendable, Equatable {
        public let displayID: CGDirectDisplayID
        public let fingerprint: DisplayFingerprint

        public init(displayID: CGDirectDisplayID, fingerprint: DisplayFingerprint) {
            self.displayID = displayID
            self.fingerprint = fingerprint
        }
    }

    /// Minimum score to accept a match at all (TDD §7.2).
    public static let acceptanceThreshold = 70

    public enum MatchResult: Sendable, Equatable {
        /// Unique best candidate at or above the threshold.
        case matched(Candidate, score: Int)
        /// Two or more candidates tie at the best (≥ threshold) score —
        /// never guess; the user must re-pick (TDD §7.2).
        case ambiguous
        /// No candidate reaches the threshold.
        case notFound
    }

    /// Evidence table from TDD §7.2 — the best applicable rule wins.
    ///
    /// | Evidence | Score |
    /// |---|---|
    /// | UUID exact match | 100 |
    /// | isBuiltin both true | 95 |
    /// | vendor + model + serial (serial ≠ 0) | 85 |
    /// | vendor + model + localizedName | 70 |
    /// | vendor + model only | 50 |
    public static func score(stored: DisplayFingerprint, candidate: DisplayFingerprint) -> Int {
        if let uuid = stored.uuid, uuid == candidate.uuid { return 100 }
        if stored.isBuiltin && candidate.isBuiltin { return 95 }

        guard
            let vendor = stored.vendorNumber, vendor == candidate.vendorNumber,
            let model = stored.modelNumber, model == candidate.modelNumber
        else { return 0 }

        if let serial = stored.serialNumber, serial != 0, serial == candidate.serialNumber {
            return 85
        }
        if let name = stored.localizedName, name == candidate.localizedName {
            return 70
        }
        return 50
    }

    /// Accept the best candidate iff its score is ≥ the threshold **and** it
    /// is the unique maximum.
    public static func match(stored: DisplayFingerprint, candidates: [Candidate]) -> MatchResult {
        let scored = candidates.map { ($0, score(stored: stored, candidate: $0.fingerprint)) }
        guard let best = scored.map(\.1).max(), best >= acceptanceThreshold else {
            return .notFound
        }
        let winners = scored.filter { $0.1 == best }
        guard winners.count == 1, let winner = winners.first else {
            return .ambiguous
        }
        return .matched(winner.0, score: best)
    }
}

/// How the stored preference resolved against the current displays.
public enum PreferredDisplayResolution: Sendable, Equatable {
    /// No preference stored.
    case none
    /// Matched. `repaired` carries a refreshed fingerprint to persist when the
    /// match came from fallback evidence and stored identifiers went stale
    /// (TDD §7.3) — `nil` when the stored fingerprint is already current.
    case resolved(CGDirectDisplayID, repaired: DisplayFingerprint?)
    /// Preference stored, but no connected display matches (DK-FR-002 S3).
    case notConnected
    /// Two indistinguishable candidates — ask the user to re-pick, never guess.
    case ambiguous
}

/// Resolves the stored preference for a snapshot (TDD §7.2–7.3).
public enum DisplayIdentityResolver {

    public static func resolve(
        stored: DisplayFingerprint?,
        candidates: [FingerprintMatcher.Candidate]
    ) -> PreferredDisplayResolution {
        guard let stored else { return .none }
        switch FingerprintMatcher.match(stored: stored, candidates: candidates) {
        case .notFound:
            return .notConnected
        case .ambiguous:
            return .ambiguous
        case .matched(let candidate, _):
            // Stale-preference repair: the fingerprint heals instead of
            // rotting. Any identifier drift (a dock changed the UUID, a name
            // changed) rewrites the stored value with fresh evidence.
            let repaired = candidate.fingerprint == stored ? nil : candidate.fingerprint
            return .resolved(candidate.displayID, repaired: repaired)
        }
    }
}
