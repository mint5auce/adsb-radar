import Foundation
import Testing
import RadarCore
@testable import ADSBRadar

struct AircraftViewModelTests {
    @Test @MainActor func contactsExposeReceivedTotalBeforeTheFirstSweepCrossing() async throws {
        var settings = RadarSettings()
        settings.receiver = GeographicCoordinate(latitude: 0, longitude: 0); settings.sweepSeconds = 30; settings.enrichIdentities = false
        let source = ViewFixtureSource(observations: [AircraftObservation(address: "abc123", position: GeographicCoordinate(latitude: 0, longitude: -1), positionTime: .now)])
        let model = RadarModel(source: source, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.receivedPositionedCount == 1 }
        #expect(model.contacts.isEmpty && model.listedContacts.isEmpty)
        await model.shutdown()
    }
    @Test @MainActor func nonICAOCategoriesRetainTheirDateAndStayScopedToTheirFeed() async throws {
        var settings = RadarSettings()
        settings.source = .combined; settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate; settings.enrichIdentities = false
        let date = Date.now
        let local = ViewFixtureSource(observations: [AircraftObservation(address: "~abc123", position: settings.receiver,
            positionTime: date, category: .light, source: "LOCAL")])
        let online = ViewFixtureSource(observations: [AircraftObservation(address: "~abc123", position: settings.receiver,
            positionTime: date, category: .heavy, source: "adsb.fi")])
        let model = RadarModel(sources: [.local: local, .online: online], identityStorage: MemoryIdentityStorage(),
            initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.contacts.count == 2 }
        let localCategory = try #require(model.reportedCategory(for: model.contacts.first { $0.id == "local:~abc123" }!))
        let onlineCategory = try #require(model.reportedCategory(for: model.contacts.first { $0.id == "online:~abc123" }!))
        #expect(localCategory.value == .light && onlineCategory.value == .heavy)
        let later = date.addingTimeInterval(1)
        await local.setObservations([AircraftObservation(address: "~abc123", position: settings.receiver, positionTime: later, source: "LOCAL")])
        await online.setObservations([AircraftObservation(address: "~abc123", position: settings.receiver, positionTime: later, source: "adsb.fi")])
        try await eventually { model.contacts.allSatisfy { $0.observation.positionTime == later } }
        #expect(model.reportedCategory(for: model.contacts.first { $0.id == "local:~abc123" }!) == localCategory)
        #expect(model.reportedCategory(for: model.contacts.first { $0.id == "online:~abc123" }!) == onlineCategory)
        #expect(model.identities.isEmpty)
        await model.shutdown()
    }
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
        let farPosition = try #require(GeographicCoordinate(latitude: 1.6, longitude: 0))
        await source.setObservations([
            AircraftObservation(address: "aaa111", position: GeographicCoordinate(latitude: 0.1, longitude: 0), positionTime: .now, altitude: .feet(10000), source: "LOCAL"),
            AircraftObservation(address: "bbb222", position: farPosition, positionTime: .now, altitude: .feet(21000), source: "LOCAL")
        ])
        try await eventually { model.contacts.first { $0.id == "bbb222" }?.observation.position == farPosition }
        #expect(model.eligibleContacts.map(\.id) == ["aaa111"])
        #expect(model.contacts.first { $0.id == "bbb222" }?.trail.count == 2)
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

    @Test @MainActor func selectedOutsideFiltersStillExpiresNormally() async throws {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation; settings.mode = .immediate
        settings.enrichIdentities = false; settings.staleSeconds = 1; settings.removalSeconds = 2
        settings.aircraftFilters.minimumAltitudeFeet = 20000
        let observation = AircraftObservation(address: "abc123", position: settings.receiver, positionTime: .now, altitude: .feet(10000))
        let model = RadarModel(source: ViewFixtureSource(observations: [observation]), identityStorage: MemoryIdentityStorage(),
            initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.contacts.count == 1 }
        model.selectedAddress = "abc123"
        #expect(model.selectedOutsideFilters && model.eligibleContacts.count == 1)
        try await eventually { model.contacts.first?.stale == true }
        try await eventually { model.contacts.isEmpty }
        #expect(model.selectedAddress == nil && model.receivedPositionedCount == 0)
        await model.shutdown()
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

    @Test @MainActor func contactsSearchAndOverlapCandidatesFollowFiltersWithoutChangingTheMap() async throws {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation; settings.mode = .immediate; settings.enrichIdentities = false
        let observations = [AircraftObservation(address: "aaa111", callsign: "SPEED123", position: SyntheticSource.exampleLocation, positionTime: .now, altitude: .feet(10000)),
            AircraftObservation(address: "bbb222", callsign: "OTHER456", position: SyntheticSource.exampleLocation, positionTime: .now, altitude: .feet(20000))]
        let identity = AircraftIdentity(registration: AircraftIdentityValue(value: "G-TEST", provider: "adsb.fi", updatedAt: .now),
            aircraftType: AircraftIdentityValue(value: "A320", provider: "adsb.fi", updatedAt: .now))
        let model = RadarModel(source: ViewFixtureSource(observations: observations), identityStorage: MemoryIdentityStorage(values: ["aaa111": identity]), initialSettings: settings, defaults: isolatedDefaults())
        model.start(); try await eventually { model.contacts.count == 2 && model.identities["aaa111"] != nil }
        #expect(model.aircraftCandidates(at: CGPoint(x: 400, y: 300)).count == 2)
        for query in ["speed", "AAA111", "g-test", "a320"] {
            model.contactsSearch = query
            #expect(model.listedContacts.map(\.id) == ["aaa111"])
            #expect(model.eligibleContacts.count == 2 && model.contactCounts.inView == 2)
        }
        var filters = model.settings.aircraftFilters; filters.maximumAltitudeFeet = 15000; model.setAircraftFilters(filters)
        #expect(model.aircraftCandidates(at: CGPoint(x: 400, y: 300)).map(\.id) == ["aaa111"])
        model.camera.offset = RadarPoint(east: 500, north: 100)
        let camera = model.camera; model.selectedAddress = "aaa111"
        #expect(model.camera == camera)
        model.showSelectedOnMap()
        #expect(model.camera.offset == RadarPoint())
        #expect(model.settings.receiver == settings.receiver)
        model.clearAircraftFilters()
        #expect(model.contactsSearch == "a320")
        await model.shutdown()
    }

    @Test @MainActor func presetsAreEditableAtomicCriteriaAndPreserveTheViewAcrossRelaunch() throws {
        let name = "preset-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation; settings.distanceUnit = .kilometres; settings.altitudeUnit = .metres
        settings.labelMode = .selectedOnly; settings.trailMode = .none; settings.directionVectors = false
        let model = RadarModel(identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: defaults)
        model.camera.offset = RadarPoint(east: 80, north: 60); model.camera.radiusNM = 200
        let camera = model.camera
        model.applyAircraftPreset(.largerNearHome)
        #expect(model.settings.aircraftFilters.homeDistanceNM == 50)
        #expect(model.settings.aircraftFilters.categories == [.small, .large, .heavy])
        #expect(model.settings.aircraftFilters.hideGround)
        #expect(abs(model.settings.distanceValue(model.settings.aircraftFilters.homeDistanceNM!) - 92.6) < 0.000000001)
        #expect(model.camera == camera && model.settings.labelMode == .selectedOnly && !model.settings.directionVectors)
        model.applyAircraftPreset(.higherTraffic)
        #expect(model.settings.aircraftFilters.homeDistanceNM == nil && model.settings.aircraftFilters.minimumAltitudeFeet == 10000)
        #expect(model.settings.aircraftFilters.maximumAltitudeFeet == nil && model.settings.aircraftFilters.includeUnknownAltitude)
        var filters = model.settings.aircraftFilters; filters.minimumAltitudeFeet = 12000; filters.includeUnknownCategory = false
        model.setAircraftFilters(filters)
        #expect(RadarPreferences(defaults: defaults).load().aircraftFilters == filters)
        model.applyAircraftPreset(.overview)
        #expect(!model.settings.aircraftFilters.isActive && !model.settings.aircraftFilters.hideGround)
        model.applyAircraftPreset(.nearHome)
        #expect(model.settings.aircraftFilters.homeDistanceNM == 50 && model.settings.aircraftFilters.minimumAltitudeFeet == nil)
        #expect(model.settings.aircraftFilters.categories == Set(AircraftCategoryGroup.allCases))
    }

}

actor ViewFixtureSource: AircraftDataSource {
    var observations: [AircraftObservation]?
    init(observations: [AircraftObservation]? = nil) { self.observations = observations }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func setObservations(_ values: [AircraftObservation]) { observations = values }
    func poll() async -> ReceptionReading {
        ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: observations ?? [
            AircraftObservation(address: "aaa111", position: GeographicCoordinate(latitude: 0.1, longitude: 0), positionTime: .now, altitude: .feet(10000), source: "LOCAL"),
            AircraftObservation(address: "bbb222", position: GeographicCoordinate(latitude: 1.5, longitude: 0), positionTime: .now, altitude: .feet(20000), source: "LOCAL")
        ]))
    }
}
