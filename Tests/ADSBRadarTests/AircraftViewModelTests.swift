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

    @Test @MainActor func altitudeBoundsAreInclusiveAndGroundIsNotNumericZero() async throws {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation; settings.mode = .immediate; settings.enrichIdentities = false
        let observations: [AircraftObservation] = [("aaa111", AircraftAltitude.feet(10000)), ("bbb222", .feet(20000)),
            ("ccc333", .feet(9999)), ("ddd444", .ground), ("eee555", nil), ("fff666", .feet(0))].map {
                AircraftObservation(address: $0.0, position: SyntheticSource.exampleLocation, positionTime: .now, altitude: $0.1)
            }
        let model = RadarModel(source: ViewFixtureSource(observations: observations), identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.contacts.count == 6 }
        var filters = model.settings.aircraftFilters
        filters.minimumAltitudeFeet = 10000; filters.maximumAltitudeFeet = 20000
        model.setAircraftFilters(filters)
        #expect(Set(model.eligibleContacts.map(\.id)) == ["aaa111", "bbb222", "eee555"])
        filters.includeUnknownAltitude = false; model.setAircraftFilters(filters)
        #expect(Set(model.eligibleContacts.map(\.id)) == ["aaa111", "bbb222"])
        filters.minimumAltitudeFeet = 21000; model.setAircraftFilters(filters)
        #expect(model.settings.aircraftFilters.minimumAltitudeFeet == 10000)
        model.clearAircraftFilters()
        filters = model.settings.aircraftFilters; filters.hideGround = true; model.setAircraftFilters(filters)
        #expect(!model.eligibleContacts.contains { $0.id == "ddd444" })
        #expect(model.eligibleContacts.contains { $0.id == "fff666" })
        await model.shutdown()
    }

    @Test @MainActor func currentLocalCategoryWinsEvenWhenThePositionFallsBackOnline() async throws {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation; settings.source = .combined; settings.mode = .immediate; settings.enrichIdentities = false
        let local = AircraftObservation(address: "abc123", position: SyntheticSource.exampleLocation,
            positionTime: Date.now.addingTimeInterval(-20), category: .light, source: "LOCAL")
        let online = AircraftObservation(address: "abc123", position: SyntheticSource.exampleLocation,
            positionTime: .now, category: .heavy, source: "adsb.fi")
        let model = RadarModel(sources: [.local: ViewFixtureSource(observations: [local]), .online: ViewFixtureSource(observations: [online])],
            identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.contacts.count == 1 && model.identities["abc123"]?.category != nil }
        let contact = try #require(model.contacts.first)
        #expect(contact.observation.source == "adsb.fi")
        #expect(model.reportedCategory(for: contact)?.value == .light)
        #expect(model.reportedCategory(for: contact)?.provider == "LOCAL")
        await model.shutdown()
    }

    @Test @MainActor func largerAircraftUsesReportedSizeGroupsWithIndependentUnknownAndSelection() async throws {
        var settings = RadarSettings()
        settings.source = .synthetic; settings.receiver = SyntheticSource.exampleLocation; settings.mode = .immediate
        let categories: [AircraftCategory?] = [.light, .small, .large, .highVortexLarge, .heavy, .highPerformance, .helicopter, .glider, nil]
        let observations = categories.enumerated().map { index, category in
            AircraftObservation(address: String(format: "aaa%03x", index + 1), position: SyntheticSource.exampleLocation,
                positionTime: .now, altitude: .feet(10000), category: category, source: "SYNTHETIC TEST")
        }
        let model = RadarModel(source: ViewFixtureSource(observations: observations), identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.contacts.count == 9 }
        var filters = model.settings.aircraftFilters
        filters.categories = AircraftCategoryGroup.largerAircraft
        model.setAircraftFilters(filters)
        #expect(Set(model.eligibleContacts.map(\.id)) == ["aaa002", "aaa003", "aaa004", "aaa005", "aaa009"])
        filters.includeUnknownCategory = false; model.setAircraftFilters(filters)
        #expect(model.eligibleContacts.count == 4)
        model.selectedAddress = "aaa001"
        #expect(model.selectedOutsideFilters && model.eligibleContacts.count == 5)
        filters.minimumAltitudeFeet = 15000; model.setAircraftFilters(filters)
        #expect(model.eligibleContacts.map(\.id) == ["aaa001"])
        await model.shutdown()
    }

    @Test @MainActor func hiddenUnknownContactsCanBeEnrichedWithoutChangingTheirPositions() async throws {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation; settings.mode = .immediate
        settings.aircraftFilters.categories = AircraftCategoryGroup.largerAircraft
        settings.aircraftFilters.includeUnknownCategory = false
        let observation = AircraftObservation(address: "abc123", position: SyntheticSource.exampleLocation, positionTime: .now, source: "LOCAL")
        let model = RadarModel(source: ViewFixtureSource(observations: [observation]), provider: IdentityFixtureProvider(), identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.contacts.count == 1 }
        try await eventually { model.eligibleContacts.count == 1 }
        #expect(model.contacts.first?.observation == observation)
        #expect(model.identities["abc123"]?.category?.value == .large)
        await model.shutdown()
    }

}

actor ViewFixtureSource: AircraftDataSource {
    let observations: [AircraftObservation]?
    init(observations: [AircraftObservation]? = nil) { self.observations = observations }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: observations ?? [
            AircraftObservation(address: "aaa111", position: GeographicCoordinate(latitude: 0.1, longitude: 0), positionTime: .now, altitude: .feet(10000), source: "LOCAL"),
            AircraftObservation(address: "bbb222", position: GeographicCoordinate(latitude: 1.5, longitude: 0), positionTime: .now, altitude: .feet(20000), source: "LOCAL")
        ]))
    }
}
