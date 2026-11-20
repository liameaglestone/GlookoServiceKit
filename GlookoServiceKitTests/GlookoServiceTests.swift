import XCTest
import LoopKit
@testable import GlookoServiceKit

private final class MockStateDelegate: StatefulPluggableDelegate {
    var updated = 0
    var deletions = 0
    func pluginDidUpdateState(_ plugin: StatefulPluggable) { updated += 1 }
    func pluginWantsDeletion(_ plugin: StatefulPluggable) { deletions += 1 }
}

private final class MockBackend: GlookoBackend {
    let variant: GlookoVariant = .classic
    var isConfigured = true
    var snapshots = 0
    func prepare() async throws {}
    func uploadGlucose(_ samples: [StoredGlucoseSample]) async throws {}
    func uploadDoses(created: [DoseEntry], deleted: [DoseEntry]) async throws {}
    func uploadCarbs(created: [SyncCarbObject], updated: [SyncCarbObject], deleted: [SyncCarbObject]) async throws {}
    func uploadPumpEvents(_ events: [PersistedPumpEvent]) async throws {}
    func uploadPumpSnapshot(basal: [DoseEntry], boluses: [DoseEntry], carbs: [SyncCarbObject], now: Date) async throws {
        snapshots += 1
    }
}

final class GlookoServiceTests: XCTestCase {

    private func makeService() -> (GlookoService, MockStateDelegate) {
        let service = GlookoService(hostIdentifier: "test", hostVersion: "1")
        service.credentialStore = InMemoryCredentialStore()
        let delegate = MockStateDelegate()
        service.stateDelegate = delegate
        return (service, delegate)
    }

    func testTokenPersistsViaStore() {
        let (service, _) = makeService()
        XCTAssertNil(service.token)
        service.token = "jwt"
        XCTAssertEqual(service.token, "jwt")
    }

    func testRawStateRoundTrip() throws {
        let (service, _) = makeService()
        service.configuration.variant = .classic
        service.configuration.email = "a@b.com"
        service.configuration.classicRegion = .us
        let restored = try XCTUnwrap(GlookoService(rawState: service.rawState))
        XCTAssertEqual(restored.configuration.variant, .classic)
        XCTAssertEqual(restored.configuration.email, "a@b.com")
        XCTAssertEqual(restored.configuration.classicRegion, .us)
    }

    func testInitRejectsBadRawState() {
        XCTAssertNil(GlookoService(rawState: ["configuration": Data("nonsense".utf8)]))
    }

    func testIsAuthenticatedXT() {
        let (service, _) = makeService()
        service.configuration.variant = .xt
        XCTAssertFalse(service.isAuthenticated)
        service.token = "jwt"
        XCTAssertTrue(service.isAuthenticated)
    }

    func testIsAuthenticatedClassicNeedsEmailAndPassword() throws {
        let (service, _) = makeService()
        service.configuration.variant = .classic
        XCTAssertFalse(service.isAuthenticated)
        service.configuration.email = "a@b.com"
        XCTAssertFalse(service.isAuthenticated)
        try service.credentialStore.set("pw", for: service.classicPasswordKey)
        XCTAssertTrue(service.isAuthenticated)
    }

    func testSignOutClears() throws {
        let (service, _) = makeService()
        service.configuration.variant = .classic
        service.configuration.email = "a@b.com"
        try service.credentialStore.set("pw", for: service.classicPasswordKey)
        service.token = "cookie"
        service.signOut()
        XCTAssertNil(service.token)
        XCTAssertNil(service.configuration.email)
        XCTAssertFalse(service.isAuthenticated)
    }

    func testLifecycleCallbacks() {
        let (service, delegate) = makeService()
        service.completeCreate()
        service.completeUpdate()
        service.completeOnboard()
        XCTAssertTrue(service.isOnboarded)
        XCTAssertGreaterThanOrEqual(delegate.updated, 3)
        service.completeDelete()
        XCTAssertEqual(delegate.deletions, 1)
    }

    func testCompleteDeleteRemovingTokenPurges() {
        let (service, _) = makeService()
        service.token = "jwt"
        service.completeDeleteRemovingToken()
        XCTAssertNil(service.token)
    }

    func testDataLimits() {
        let (service, _) = makeService()
        XCTAssertEqual(service.glucoseDataLimit, 1000)
        XCTAssertEqual(service.doseDataLimit, 1000)
        XCTAssertEqual(service.carbDataLimit, 1000)
        XCTAssertEqual(service.pumpEventDataLimit, 1000)
        XCTAssertEqual(service.dosingDecisionDataLimit, 0)
        XCTAssertEqual(service.settingsDataLimit, 0)
        XCTAssertEqual(service.alertDataLimit, 0)
    }

    func testUnmappedUploadsSucceedImmediately() async {
        let (service, _) = makeService()
        await assertSuccess { try await service.uploadAlertData([]) }
        await assertSuccess { try await service.uploadTemporaryOverrideData(updated: [], deleted: []) }
        await assertSuccess { try await service.uploadDosingDecisionData([]) }
        await assertSuccess { try await service.uploadSettingsData([]) }
        await assertSuccess { try await service.uploadCgmEventData([]) }
        try? await service.remoteNotificationWasReceived([:])
    }

    func testMappedUploadsFailWhenNotConfigured() async {
        let (service, _) = makeService()
        await assertFailure { try await service.uploadGlucoseData([]) }
        await assertFailure { try await service.uploadDoseData(created: [], deleted: []) }
        await assertFailure { try await service.uploadCarbData(created: [], updated: [], deleted: []) }
        await assertFailure { try await service.uploadPumpEventData([]) }
    }

    func testRawStateKeepsHostIdentity() throws {
        let service = GlookoService(hostIdentifier: "org.nightscout.Trio", hostVersion: "2.0")
        let restored = try XCTUnwrap(GlookoService(rawState: service.rawState))
        XCTAssertEqual(restored.identity, GlookoClientIdentity(hostIdentifier: "org.nightscout.Trio", hostVersion: "2.0"))
    }

    func testCompleteDeleteClearsCredentials() throws {
        let (service, _) = makeService()
        service.token = "jwt"
        try service.credentialStore.set("pw", for: service.classicPasswordKey)
        service.completeDelete()
        XCTAssertNil(service.token)
        XCTAssertNil(try service.credentialStore.value(for: service.classicPasswordKey))
    }

    func testSnapshotStatsAccumulate() async {
        let (service, _) = makeService()
        let backend = MockBackend()
        service.backendOverride = backend
        service.reload()
        let now = Date()
        let bolus = DoseEntry(type: .bolus, startDate: now, endDate: now, value: 1, unit: .units, decisionId: nil)
        await assertSuccess { try await service.uploadPumpSnapshot(basal: [], boluses: [bolus, bolus], carbs: []) }
        await assertSuccess { try await service.uploadPumpSnapshot(basal: [], boluses: [bolus], carbs: []) }
        XCTAssertEqual(backend.snapshots, 2)
        XCTAssertEqual(service.stats.doses, 3)
        XCTAssertNotNil(service.stats.lastUploadDate)
    }

    private func assertSuccess(_ call: () async throws -> Void) async {
        do { try await call() } catch { XCTFail("expected success, got \(error)") }
    }

    private func assertFailure(_ call: () async throws -> Void) async {
        do { try await call(); XCTFail("expected failure") } catch {}
    }
}
