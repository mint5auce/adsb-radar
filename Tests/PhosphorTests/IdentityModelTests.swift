import Foundation
import Testing
import RadarCore
@testable import Phosphor

struct IdentityModelTests {
    @Test @MainActor func localEnrichmentCannotChangePositionsOrIntroduceOtherContacts() async throws {
        let provider = IdentityFixtureProvider()
        let local = ControlledSource(addresses: ["abc123"], source: "LOCAL", fixedPositions: true)
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(sources: [.local: local], provider: provider, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 1 }
        let original = try #require(model.contacts.first?.observation)
        model.selectedAddress = "abc123"
        try await eventually { model.selectedIdentity?.aircraftType?.value == "A320" }
        #expect(model.selectedIdentity?.registration?.value == "G-TEST")
        #expect(model.selectedIdentity?.aircraftLabel == "Airbus A320")
        #expect(model.selectedIdentity?.ownerOperator?.value == "Example Airways")
        for query in ["Airbus", "A320", "Example Airways"] {
            model.contactsSearch = query
            #expect(model.listedContacts.map(\.id) == ["abc123"])
        }
        model.contactsSearch = "no such owner"
        #expect(model.listedContacts.isEmpty)
        #expect(model.contacts.count == 1 && model.contacts.first?.observation == original)
        #expect(model.identities["fff000"] == nil)
        #expect(await provider.positionRequests == 0)
        await model.shutdown()
    }

    @Test @MainActor func onlineSnapshotsSupplyDetailsWithDedicatedLookupsDisabled() async throws {
        let provider = IdentityFixtureProvider()
        var settings = RadarSettings()
        settings.source = .online
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        settings.enrichIdentities = false
        let model = RadarModel(sources: [.online: IdentitySnapshotSource()], provider: provider,
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.identities["abc123"] != nil && !model.contacts.isEmpty }
        model.selectedAddress = "abc123"
        #expect(model.selectedIdentity?.registration?.value == "G-SNAP")
        #expect(model.selectedIdentity?.aircraftLabel == "Boeing 737-800")
        #expect(model.selectedIdentity?.ownerOperator?.value == "Example Leasing Limited")
        #expect(await provider.requests.isEmpty)
        await model.shutdown()
    }

    @Test @MainActor func disablingEnrichmentCancelsLookupWithoutRestartingLocalReception() async throws {
        let provider = IdentityFixtureProvider(slow: true)
        let local = ControlledSource(addresses: ["abc123"], source: "LOCAL")
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(sources: [.local: local], provider: provider, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { await provider.requests.count == 1 }
        settings.enrichIdentities = false
        model.apply(settings)
        try await eventually { await provider.cancellations == 1 }
        #expect(await local.starts == 1)
        #expect(model.contacts.count == 1 && model.contacts.first?.observation.source == "LOCAL")
        #expect(model.identities.isEmpty)
        await model.shutdown()
    }

    @Test @MainActor func syntheticNeverLooksUpOrDisplaysCachedRealIdentity() async throws {
        let provider = IdentityFixtureProvider()
        let local = ControlledSource(addresses: ["f00001"], source: "LOCAL")
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(sources: [.local: local], provider: provider, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.identities["f00001"] != nil }
        let requests = await provider.requests.count
        settings.source = .synthetic
        model.apply(settings)
        try await eventually { model.contacts.contains { $0.id == "f00001" } }
        model.selectedAddress = "f00001"
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.selectedIdentity == nil)
        #expect(await provider.requests.count == requests)
        #expect(await provider.positionRequests == 0)
        await model.shutdown()
    }

    @Test @MainActor func enrichmentFailureLeavesLocalTrafficWorkingWithUnknownDetails() async throws {
        let provider = IdentityFixtureProvider(failing: true)
        let local = ControlledSource(addresses: ["abc123"], source: "LOCAL")
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(sources: [.local: local], provider: provider, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { await provider.requests.count == 1 }
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.statuses[.local] == .receiving && model.contacts.count == 1)
        #expect(model.identities.isEmpty)
        #expect(await provider.requests.count == 1)
        await model.shutdown()
    }
}

actor IdentityFixtureProvider: OnlineAircraftProvider, AircraftIdentityProvider {
    var requests: [[String]] = []
    var positionRequests = 0
    var cancellations = 0
    let slow: Bool
    let failing: Bool
    init(slow: Bool = false, failing: Bool = false) { self.slow = slow; self.failing = failing }
    func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot {
        positionRequests += 1
        return ReceiverSnapshot(observations: [])
    }
    func identities(for addresses: [String]) async throws -> [AircraftIdentityUpdate] {
        requests.append(addresses)
        if slow {
            do { try await Task.sleep(for: .seconds(20)) }
            catch { cancellations += 1; throw error }
        }
        if failing { throw URLError(.notConnectedToInternet) }
        return (addresses + ["fff000"]).map { AircraftIdentityUpdate(address: $0, registration: "G-TEST", aircraftType: "A320",
            modelDescription: "AIRBUS A320", ownerOperator: "Example Airways", category: .large) }
    }
}

private actor IdentitySnapshotSource: AircraftDataSource {
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: [
            AircraftObservation(address: "abc123", position: SyntheticSource.exampleLocation, positionTime: .now, source: "adsb.fi")
        ], identities: [AircraftIdentityUpdate(address: "abc123", registration: "G-SNAP", aircraftType: "B738",
            modelDescription: "BOEING 737-800", ownerOperator: "Example Leasing Limited")]))
    }
}

actor MemoryIdentityStorage: AircraftIdentityStorage {
    var values: [String: AircraftIdentity]
    let failing: Bool
    init(values: [String: AircraftIdentity] = [:], failing: Bool = false) { self.values = values; self.failing = failing }
    func load() throws -> [String: AircraftIdentity] {
        if failing { throw CocoaError(.fileReadNoPermission) }
        return values
    }
    func save(_ identities: [String: AircraftIdentity]) throws {
        if failing { throw CocoaError(.fileWriteNoPermission) }
        values = identities
    }
}
