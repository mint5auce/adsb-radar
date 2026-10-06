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
        settings.staleSeconds = 1
        settings.removalSeconds = 2
        let model = RadarModel(source: fixture, initialSettings: settings)
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
        let model = RadarModel(source: feed, initialSettings: settings)
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

}

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
