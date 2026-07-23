import Testing
import Foundation
@testable import DockKeeperCore

// Convenience fixtures ------------------------------------------------------

private func fp(
    uuid: String? = nil,
    vendor: UInt32? = nil,
    model: UInt32? = nil,
    serial: UInt32? = nil,
    name: String? = nil,
    builtin: Bool = false
) -> DisplayFingerprint {
    DisplayFingerprint(
        uuid: uuid, vendorNumber: vendor, modelNumber: model,
        serialNumber: serial, localizedName: name, isBuiltin: builtin
    )
}

private func candidate(_ id: UInt32, _ fingerprint: DisplayFingerprint) -> FingerprintMatcher.Candidate {
    FingerprintMatcher.Candidate(displayID: id, fingerprint: fingerprint)
}

// MARK: - Score table (TDD §7.2)

@Suite("FingerprintMatcher.score")
struct FingerprintScoreTests {

    @Test("UUID exact match scores 100")
    func uuidWins() {
        #expect(FingerprintMatcher.score(
            stored: fp(uuid: "U", vendor: 1, model: 2),
            candidate: fp(uuid: "U")
        ) == 100)
    }

    @Test("Both built-in scores 95 (there is at most one built-in)")
    func builtinRule() {
        #expect(FingerprintMatcher.score(
            stored: fp(builtin: true),
            candidate: fp(uuid: "different", builtin: true)
        ) == 95)
        // One-sided builtin claims score nothing on this rule.
        #expect(FingerprintMatcher.score(stored: fp(builtin: true), candidate: fp()) == 0)
    }

    @Test("Vendor + model + non-zero serial scores 85")
    func serialRule() {
        #expect(FingerprintMatcher.score(
            stored: fp(vendor: 10, model: 20, serial: 30),
            candidate: fp(uuid: "changed", vendor: 10, model: 20, serial: 30)
        ) == 85)
    }

    @Test("Serial 0 is treated as absent, falling through to name or vendor+model")
    func zeroSerialIgnored() {
        #expect(FingerprintMatcher.score(
            stored: fp(vendor: 10, model: 20, serial: 0, name: "DELL U2720Q"),
            candidate: fp(vendor: 10, model: 20, serial: 0, name: "DELL U2720Q")
        ) == 70)
        #expect(FingerprintMatcher.score(
            stored: fp(vendor: 10, model: 20, serial: 0),
            candidate: fp(vendor: 10, model: 20, serial: 0)
        ) == 50)
    }

    @Test("Vendor + model + localizedName scores 70; vendor + model alone 50")
    func nameAndBareRules() {
        #expect(FingerprintMatcher.score(
            stored: fp(vendor: 10, model: 20, name: "LG HDR 4K"),
            candidate: fp(vendor: 10, model: 20, name: "LG HDR 4K")
        ) == 70)
        #expect(FingerprintMatcher.score(
            stored: fp(vendor: 10, model: 20, name: "LG HDR 4K"),
            candidate: fp(vendor: 10, model: 20, name: "Other")
        ) == 50)
    }

    @Test("Different hardware scores 0")
    func mismatch() {
        #expect(FingerprintMatcher.score(
            stored: fp(vendor: 10, model: 20),
            candidate: fp(vendor: 99, model: 20)
        ) == 0)
    }
}

// MARK: - Matching (unique max ≥ 70)

@Suite("FingerprintMatcher.match")
struct FingerprintMatchTests {

    @Test("Unique best candidate at or above 70 matches")
    func uniqueBest() {
        let stored = fp(uuid: "U", vendor: 10, model: 20)
        let winner = candidate(2, fp(uuid: "U"))
        let result = FingerprintMatcher.match(
            stored: stored,
            candidates: [candidate(1, fp(vendor: 10, model: 20)), winner]
        )
        #expect(result == .matched(winner, score: 100))
    }

    @Test("Identical twin externals (serial 0) tie → ambiguous, never guess")
    func twinsAreAmbiguous() {
        let twin = fp(vendor: 10, model: 20, serial: 0, name: "ACME 27")
        let result = FingerprintMatcher.match(
            stored: twin,
            candidates: [candidate(1, twin), candidate(2, twin)]
        )
        #expect(result == .ambiguous)
    }

    @Test("Vendor+model-only evidence (50) is below the acceptance threshold")
    func weakEvidenceNotFound() {
        let result = FingerprintMatcher.match(
            stored: fp(vendor: 10, model: 20),
            candidates: [candidate(1, fp(vendor: 10, model: 20))]
        )
        #expect(result == .notFound)
    }

    @Test("A UUID match disambiguates otherwise identical twins")
    func uuidBreaksTie() {
        let twin = fp(vendor: 10, model: 20, name: "ACME 27")
        let stored = fp(uuid: "U", vendor: 10, model: 20, name: "ACME 27")
        let target = candidate(2, fp(uuid: "U", vendor: 10, model: 20, name: "ACME 27"))
        let result = FingerprintMatcher.match(stored: stored, candidates: [candidate(1, twin), target])
        #expect(result == .matched(target, score: 100))
    }
}

// MARK: - Resolution + stale-preference repair (TDD §7.3)

@Suite("DisplayIdentityResolver")
struct DisplayIdentityResolverTests {

    @Test("No stored preference resolves to none")
    func noPreference() {
        #expect(DisplayIdentityResolver.resolve(stored: nil, candidates: []) == .none)
    }

    @Test("Exact fingerprint match needs no repair")
    func exactMatchNoRepair() {
        let current = fp(uuid: "U", vendor: 10, model: 20, serial: 30)
        let resolution = DisplayIdentityResolver.resolve(stored: current, candidates: [candidate(7, current)])
        #expect(resolution == .resolved(7, repaired: nil))
    }

    @Test("Fallback-evidence match with a changed UUID repairs the stored fingerprint")
    func staleUUIDRepaired() {
        let stored = fp(uuid: "OLD", vendor: 10, model: 20, serial: 30)
        let fresh = fp(uuid: "NEW", vendor: 10, model: 20, serial: 30)  // dock/adapter changed the UUID
        let resolution = DisplayIdentityResolver.resolve(stored: stored, candidates: [candidate(7, fresh)])
        #expect(resolution == .resolved(7, repaired: fresh))
    }

    @Test("No acceptable candidate resolves to notConnected")
    func notConnected() {
        let stored = fp(uuid: "U", vendor: 10, model: 20)
        let other = fp(uuid: "X", vendor: 99, model: 1)
        #expect(DisplayIdentityResolver.resolve(stored: stored, candidates: [candidate(1, other)]) == .notConnected)
    }

    @Test("Ties resolve to ambiguous")
    func ambiguous() {
        let twin = fp(vendor: 10, model: 20, name: "ACME 27")
        let stored = fp(uuid: "GONE", vendor: 10, model: 20, name: "ACME 27")
        let resolution = DisplayIdentityResolver.resolve(
            stored: stored,
            candidates: [candidate(1, twin), candidate(2, twin)]
        )
        #expect(resolution == .ambiguous)
    }
}

// MARK: - Persistence, mirror key, and migration (ADR-004)

@Suite("Settings display preference")
struct SettingsDisplayPreferenceTests {

    private func makeSuite() -> (UserDefaults, String) {
        let name = "com.dockkeeper.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return (suite, name)
    }

    @Test("Storing a preference persists the fingerprint and mirrors the legacy UUID key")
    func storeAndMirror() {
        let (suite, _) = makeSuite()
        let settings = Settings(defaults: suite)
        settings.setPreferredDisplay(fingerprint: fp(uuid: "U", vendor: 10, model: 20))

        #expect(settings.preferredDisplayFingerprint == fp(uuid: "U", vendor: 10, model: 20))
        #expect(suite.string(forKey: "preferredDisplayUUID") == "U", "legacy key must stay usable for rollback")

        settings.setPreferredDisplay(fingerprint: nil)
        #expect(settings.preferredDisplayFingerprint == nil)
        #expect(suite.string(forKey: "preferredDisplayUUID") == nil)
    }

    @Test("A v0.1 bare-UUID preference migrates into a fingerprint once")
    func migratesLegacyUUID() {
        let (suite, _) = makeSuite()
        suite.set("LEGACY-UUID", forKey: "preferredDisplayUUID")

        let settings = Settings(defaults: suite)
        #expect(settings.preferredDisplayFingerprint == fp(uuid: "LEGACY-UUID"))
        #expect(suite.string(forKey: "preferredDisplayUUID") == "LEGACY-UUID")
    }

    @Test("Unstable cg- pseudo-UUIDs are discarded on migration, never persisted (TDD §7.1)")
    func discardsPseudoUUID() {
        let (suite, _) = makeSuite()
        suite.set("cg-5", forKey: "preferredDisplayUUID")

        let settings = Settings(defaults: suite)
        #expect(settings.preferredDisplayFingerprint == nil)
        #expect(suite.string(forKey: "preferredDisplayUUID") == nil)
    }

    @Test("Migration never overwrites an existing fingerprint")
    func migrationIsWriteOnce() {
        let (suite, _) = makeSuite()
        let settings = Settings(defaults: suite)
        settings.setPreferredDisplay(fingerprint: fp(uuid: "CURRENT"))

        // A stale legacy value from some older sync must not win on re-init.
        suite.set("STALE", forKey: "preferredDisplayUUID")
        let reloaded = Settings(defaults: suite)
        #expect(reloaded.preferredDisplayFingerprint == fp(uuid: "CURRENT"))
    }

    @Test("Repair rewrites the stored fingerprint with fresh evidence (TDD §7.3)")
    func repairRewrites() {
        let (suite, _) = makeSuite()
        let settings = Settings(defaults: suite)
        settings.setPreferredDisplay(fingerprint: fp(uuid: "OLD", vendor: 10, model: 20, serial: 30))

        let fresh = fp(uuid: "NEW", vendor: 10, model: 20, serial: 30, name: "ACME 27")
        settings.repairPreferredDisplay(fresh)
        #expect(settings.preferredDisplayFingerprint == fresh)
        #expect(suite.string(forKey: "preferredDisplayUUID") == "NEW")
    }
}
