import Foundation
import Testing
import RadarCore
@testable import ADSBRadar

struct RadarModelTests {
    @Test @MainActor func slowPollingDoesNotFreezeAgeingAndSwitchingStopsTheOldSource() async throws {
        let fixture = SlowSource()
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.source = .online
        settings.mode = .immediate
        settings.enrichIdentities = false
        settings.staleSeconds = 1
        settings.removalSeconds = 2
        let model = RadarModel(source: fixture, initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 1 }
        model.selectedAddress = model.contacts.first?.id
        try await eventually { model.contacts.first?.stale == true }
        try await eventually { model.contacts.isEmpty }
        #expect(model.selectedAddress == nil)
        settings.source = .synthetic
        model.apply(settings)
        try await eventually { await fixture.starts >= 2 }
        #expect(await fixture.stops >= 1)
        await model.shutdown()
        #expect(await fixture.stops >= 2)
    }
    @Test @MainActor func settledPansUseOnlyTheLatestSearchAndPreserveSelection() async throws {
        let provider = SearchRecordingProvider()
        let feed = OnlineFeed(provider: provider)
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.source = .online
        settings.mode = .immediate
        settings.enrichIdentities = false
        let model = RadarModel(source: feed, initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 1 }
        model.selectedAddress = "abc123"
        for index in 1...5 {
            model.camera.offset = RadarPoint(east: Double(index) * 20, north: 10)
            try await Task.sleep(for: .milliseconds(30))
        }
        try await eventually { await provider.searches.count == 2 }
        let searches = await provider.searches
        #expect(searches.count == 2)
        let expected = try #require(model.onlineCoverage?.search)
        #expect(searches.last == expected)
        #expect(model.selectedAddress == "abc123" && model.contacts.first?.trail.count == 1)
        settings.onlineRadiusNM = 40
        model.apply(settings)
        try await eventually { await provider.searches.last?.radiusNM == 40 }
        #expect(model.selectedAddress == "abc123")
        model.returnToReceiver()
        try await eventually { await provider.searches.last?.centre == settings.receiver }
        await model.shutdown()
    }

    @Test @MainActor func realModeChangesKeepSharedSourcesContactsAndTrails() async throws {
        let local = ControlledSource(addresses: ["abc123", "aaa111"], source: "LOCAL")
        let online = ControlledSource(addresses: ["abc123", "bbb222"], source: "adsb.fi")
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.source = .combined
        settings.mode = .immediate
        settings.enrichIdentities = false
        let model = RadarModel(sources: [.local: local, .online: online], initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 3 }
        #expect(model.contacts.first { $0.id == "abc123" }?.observation.source == "LOCAL")
        model.selectedAddress = "abc123"
        let initialOnlineStarts = await online.starts
        settings.source = .online
        model.apply(settings)
        try await eventually { await local.stops >= 2 }
        #expect(model.selectedAddress == "abc123" && model.contacts.count == 2)
        #expect(model.selectedContact?.trail.isEmpty == false)
        #expect(await online.starts == initialOnlineStarts)
        settings.source = .combined
        model.apply(settings)
        try await eventually { await local.starts == 2 }
        #expect(await online.starts == initialOnlineStarts)
        settings.source = .synthetic
        model.apply(settings)
        #expect(model.selectedAddress == nil && model.contacts.isEmpty)
        await model.shutdown()
        #expect(await online.stops >= 2)
    }

    @Test @MainActor func localFailureRetriesWhileOnlineKeepsWorking() async throws {
        let local = ControlledSource(addresses: [], source: "LOCAL", failed: true)
        let online = ControlledSource(addresses: ["abc123"], source: "adsb.fi")
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.source = .combined
        settings.mode = .immediate
        settings.enrichIdentities = false
        let model = RadarModel(sources: [.local: local, .online: online], initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 1 }
        if case .failed = model.statuses[.local] {} else { Issue.record("Local health did not report the failure") }
        #expect(model.statuses[.online] == .receiving)
        try await eventually { await local.starts >= 2 }
        #expect(model.contacts.first?.observation.source == "adsb.fi")
        #expect(await online.starts == 1)
        await model.shutdown()
    }

}

@MainActor
func isolatedDefaults() -> UserDefaults { UserDefaults(suiteName: "adsb-model-tests-\(UUID())")! }

@MainActor
func eventually(_ condition: () async -> Bool) async throws {
    for _ in 0..<150 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    Issue.record("Condition did not become true within 3.75 seconds")
}

private actor SlowSource: AircraftDataSource {
    var starts = 0
    var stops = 0
    private var sent = false
    func start(location: GeographicCoordinate?) async { starts += 1; sent = false }
    func stop() async { stops += 1 }
    func poll() async -> ReceptionReading {
        if !sent {
            sent = true
            return ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: [
                AircraftObservation(address: "abc123", position: SyntheticSource.exampleLocation, positionTime: .now, source: "adsb.fi")
            ]))
        }
        try? await Task.sleep(for: .seconds(20))
        return ReceptionReading(status: .waiting)
    }
}

private actor SearchRecordingProvider: OnlineAircraftProvider {
    var searches: [OnlineSearch] = []
    func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot {
        searches.append(search)
        let contacts = searches.count == 1 ? [AircraftObservation(address: "abc123", position: SyntheticSource.exampleLocation, positionTime: .now, source: "adsb.fi")] : []
        return ReceiverSnapshot(observations: contacts)
    }
}

actor ControlledSource: AircraftDataSource {
    var starts = 0
    var stops = 0
    let addresses: [String]
    let source: String
    let failed: Bool
    let fixedPositions: Bool
    private var positionTime = Date.now
    init(addresses: [String], source: String, failed: Bool = false, fixedPositions: Bool = false) {
        self.addresses = addresses; self.source = source; self.failed = failed; self.fixedPositions = fixedPositions
    }
    func start(location: GeographicCoordinate?) async { starts += 1; positionTime = .now }
    func stop() async { stops += 1 }
    func poll() async -> ReceptionReading {
        if failed { return ReceptionReading(status: .failed("Receiver unavailable")) }
        return ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: addresses.map {
            AircraftObservation(address: $0, position: SyntheticSource.exampleLocation, positionTime: fixedPositions ? positionTime : .now, source: source)
        }))
    }
}
