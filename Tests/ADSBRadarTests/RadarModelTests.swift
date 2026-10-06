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
