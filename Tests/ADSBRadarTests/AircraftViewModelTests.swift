import Foundation
import Testing
import RadarCore
@testable import ADSBRadar

struct AircraftViewModelTests {
    @Test @MainActor func homeFiltersKeepReceivedContactsAndSelectionIndependentOfPanning() async throws {
        var settings = RadarSettings()
        settings.receiver = GeographicCoordinate(latitude: 0, longitude: 0)
        settings.mode = .immediate
        settings.enrichIdentities = false
        let source = ViewFixtureSource()
        let model = RadarModel(source: source, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        var filters = model.settings.aircraftFilters
        filters.homeDistanceNM = 50
        model.setAircraftFilters(filters)
        #expect(model.eligibleContacts.map(\.id) == ["aaa111"])
        #expect(model.contacts.count == 2 && model.contactCounts.filtered == 1)
        model.selectedAddress = "bbb222"
        #expect(model.selectedOutsideFilters)
        #expect(model.eligibleContacts.count == 2 && model.contactCounts.filtered == 0)
        model.camera.offset = RadarPoint(east: 500, north: 0)
        #expect(model.contactCounts.inView == 0 && model.contactCounts.outsideView == 2)
        model.selectedAddress = nil
        let retained = model.contacts.first { $0.id == "bbb222" }
        model.clearAircraftFilters()
        #expect(model.eligibleContacts.count == 2)
        #expect(model.contacts.first { $0.id == "bbb222" }?.observation == retained?.observation)
        #expect(model.contacts.first { $0.id == "bbb222" }?.trail == retained?.trail)
        #expect((model.contacts.first { $0.id == "bbb222" }?.positionAge ?? 0) >= (retained?.positionAge ?? 0))
        await model.shutdown()
    }
    @Test @MainActor func filterValidationAndPersistenceLeaveCameraAndPresentationPreferencesAlone() throws {
        let name = "aircraft-filter-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = RadarSettings()
        settings.source = .online
        settings.receiver = SyntheticSource.exampleLocation
        settings.labelMode = .all; settings.trailMode = .none; settings.directionVectors = false
        let model = RadarModel(identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: defaults)
        model.camera.offset = RadarPoint(east: 100, north: 20)
        let camera = model.camera
        let search = model.onlineCoverage?.search
        model.setAircraftFilters(AircraftViewFilters(homeDistanceNM: 500))
        #expect(model.settings.aircraftFilters.homeDistanceNM == 500)
        model.setAircraftFilters(AircraftViewFilters(homeDistanceNM: -1))
        #expect(model.settings.aircraftFilters.homeDistanceNM == 500)
        #expect(RadarPreferences(defaults: defaults).load().aircraftFilters.homeDistanceNM == 500)
        model.clearAircraftFilters()
        #expect(model.camera == camera && model.onlineCoverage?.search == search)
        #expect(model.settings.labelMode == .all && model.settings.trailMode == .none && !model.settings.directionVectors)
    }

}

actor ViewFixtureSource: AircraftDataSource {
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: [
            AircraftObservation(address: "aaa111", position: GeographicCoordinate(latitude: 0.1, longitude: 0), positionTime: .now, altitude: .feet(10000), source: "LOCAL"),
            AircraftObservation(address: "bbb222", position: GeographicCoordinate(latitude: 1.5, longitude: 0), positionTime: .now, altitude: .feet(20000), source: "LOCAL")
        ]))
    }
}
