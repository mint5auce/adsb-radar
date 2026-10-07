import Foundation
import Testing
import RadarCore
@testable import Phosphor

struct MapLayerModelTests {
    @Test @MainActor func airportFiltersClearSelectionAndHitTargetsWhilePreservingCameraAndSettings() async throws {
        let suite = "airport-filter-model-\(UUID())"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let maps = MapLayerModel(store: MapSnapshotStore(directory: folder))
        var settings = RadarSettings(); settings.mode = .immediate; settings.enrichIdentities = false
        settings.receiver = GeographicCoordinate(latitude: 51.47, longitude: -0.4543)
        settings.mapLayers.routes = false; settings.mapLayers.airspace = false
        let source = ViewFixtureSource(observations: [AircraftObservation(address: "abc123", position: settings.receiver, positionTime: .now)])
        let model = RadarModel(source: source, identityStorage: MemoryIdentityStorage(), mapLayers: maps, initialSettings: settings, defaults: defaults)
        // Await the bundled fixture instead of imposing a two-second disk-load deadline.
        await maps.load(origin: settings.receiver)
        model.start()
        try await eventually(timeout: .seconds(15)) {
            !maps.loading && !maps.projected.isEmpty && !model.contacts.isEmpty
        }
        #expect(model.contacts.map(\.id) == ["abc123"])
        let airport = try #require(maps.snapshots.flatMap(\.features).first { $0.label == "EGLL" })
        #expect(airport.airportSize == .large && airport.scheduledService == true)
        let point = try #require(airport.paths.first?.first)
        let projected = ReceiverProjection(origin: try #require(settings.receiver)).project(point)
        let camera = model.camera
        let screen = camera.screen(projected, width: model.viewportWidth, height: model.viewportHeight)
        let hit = CGPoint(x: screen.x, y: screen.y)
        #expect(model.mapChoices(at: hit).contains { $0.id == .map(airport.id) })
        model.selection = .map(airport.id)
        var changed = model.settings
        changed.mapLayers.airportFilters.sizes = [.medium]
        model.apply(changed)
        #expect(model.selectedMapFeature == nil && model.selection == nil)
        #expect(!model.mapChoices(at: hit).contains { $0.id == .map(airport.id) })
        changed.mapLayers.airportFilters.sizes = [.large]
        model.apply(changed)
        model.selection = .map(airport.id)
        changed.mapLayers.airportFilters.service = .withoutScheduledService
        model.apply(changed)
        #expect(model.selection == nil)
        #expect(!model.mapChoices(at: hit).contains { $0.id == .map(airport.id) })
        #expect(model.camera == camera && model.settings.receiver == settings.receiver)
        #expect(model.settings.aircraftFilters == settings.aircraftFilters)
        #expect(model.contacts.map(\.id) == ["abc123"])
        #expect(RadarPreferences(defaults: defaults).load().mapLayers == changed.mapLayers)
        await model.shutdown()
    }

    @Test @MainActor func bundledMapsSelectAndHideWithoutDisturbingAircraftOrCamera() async throws {
        let suite = "map-tests-\(UUID())", folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let maps = MapLayerModel(store: MapSnapshotStore(directory: folder))
        var settings = RadarSettings(); settings.source = .synthetic; settings.mode = .immediate
        settings.receiver = GeographicCoordinate(latitude: 51.47, longitude: -0.4543)
        let model = RadarModel(mapLayers: maps, initialSettings: settings, defaults: defaults)
        await maps.load(origin: settings.receiver)
        #expect(maps.projected.count > 2000)
        let airport = try #require(maps.snapshots.flatMap(\.features).first { $0.label == "EGLL" })
        model.selection = .map(airport.id)
        #expect(model.selectedMapFeature == airport)
        model.selectedAddress = "abc123"
        #expect(model.selectedMapFeature == nil)
        model.selection = .map(airport.id)
        #expect(model.selectedAddress == nil)
        var changed = model.settings; changed.mapLayers.flightLevel = 400
        let camera = model.camera
        model.apply(changed)
        #expect(model.selection == .map(airport.id))
        changed.mapLayers.airports = false; model.apply(changed)
        #expect(model.selection == nil)
        #expect(model.camera == camera)
        let route = try #require(maps.snapshots.flatMap(\.features).first { $0.kind == .route && $0.lower.description == "FL 245" })
        model.selection = .map(route.id)
        changed.mapLayers.flightLevel = 0; model.apply(changed)
        #expect(model.selection == nil)
        #expect(RadarPreferences(defaults: defaults).load().mapLayers.flightLevel == 0)
        await model.shutdown()
    }

    @Test @MainActor func aircraftWinsPrimaryClickAndSecondaryClickIncludesUnderlyingMaps() async throws {
        let name = "map-selection-\(UUID())", folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        let maps = MapLayerModel(store: MapSnapshotStore(directory: folder))
        let origin = GeographicCoordinate(latitude: 51.47, longitude: -0.4543)!
        var settings = RadarSettings(); settings.receiver = origin; settings.mode = .immediate; settings.enrichIdentities = false
        let source = ViewFixtureSource(observations: [AircraftObservation(address: "abc123", position: origin, positionTime: .now)])
        let model = RadarModel(source: source, identityStorage: MemoryIdentityStorage(), mapLayers: maps, initialSettings: settings, defaults: defaults)
        // Await the bundled fixture instead of imposing a two-second disk-load deadline.
        await maps.load(origin: settings.receiver)
        model.start()
        try await eventually(timeout: .seconds(15)) {
            !maps.loading && !maps.projected.isEmpty && !model.contacts.isEmpty
        }
        let point = CGPoint(x: model.viewportWidth / 2, y: model.viewportHeight / 2)
        #expect(model.objectChoices(at: point).map(\.id) == [.aircraft("abc123")])
        #expect(model.objectChoices(at: point, secondary: true).contains { if case .map = $0.id { return true }; return false })
        await model.shutdown()
    }
    @Test @MainActor func failedRefreshKeepsMapGenerationAndSelectionWhileRadarRuns() async throws {
        let name = "map-failure-\(UUID())", folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: folder) }
        let store = MapSnapshotStore(directory: folder)
        let maps = MapLayerModel(store: store, updater: MapUpdateService(download: { _ in throw URLError(.notConnectedToInternet) }))
        var settings = RadarSettings(); settings.source = .synthetic; settings.mapLayers.flightLevel = 100
        let model = RadarModel(mapLayers: maps, initialSettings: settings, defaults: defaults)
        await maps.load(origin: SyntheticSource.exampleLocation)
        let old = maps.snapshots
        for snapshot in old { try await store.install(snapshot) }
        let uncertain = try #require(old.flatMap(\.features).first { $0.kind == .airspace && $0.slice(at: 100) == .uncertain })
        model.selection = .map(uncertain.id)
        let camera = model.camera
        await model.checkForMapUpdates()
        #expect(maps.snapshots == old)
        #expect(model.selection == .map(uncertain.id))
        #expect(model.camera == camera && model.settings.mapLayers.flightLevel == 100)
        #expect(maps.messages.values.allSatisfy { $0.hasPrefix("Kept existing data.") })
        let restarted = MapLayerModel(store: store)
        await restarted.load(origin: SyntheticSource.exampleLocation)
        #expect(restarted.snapshots == old)
    }

    @Test @MainActor func rowBoundaryTruncationCannotReplaceTheAirportSnapshot() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let csv = """
        id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,iso_country,icao_code,iata_code,gps_code,local_code
        1,GB-1,small_airport,Partial field,52,-1,,GB,,,,ABC
        """
        let service = MapUpdateService(download: { url in
            url.pathExtension == "csv" ? Data(csv.utf8) : Data("<a href='/EG_AIP_DS_20261001_XML.zip'>dataset</a>".utf8)
        })
        let store = MapSnapshotStore(directory: folder)
        let maps = MapLayerModel(store: store, updater: service)
        await maps.load(origin: SyntheticSource.exampleLocation)
        let old = maps.snapshots
        for snapshot in old { try await store.install(snapshot) }
        await maps.checkForUpdates()
        #expect(maps.snapshots == old)
        #expect(maps.messages[.ourAirports]?.contains("unexpectedly incomplete") == true)
        let restarted = MapLayerModel(store: store)
        await restarted.load(origin: SyntheticSource.exampleLocation)
        #expect(restarted.snapshots == old)
    }

    @Test @MainActor func airportHitTestingTracksProjectionPanAndZoom() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let maps = MapLayerModel(store: MapSnapshotStore(directory: folder))
        let origin = GeographicCoordinate(latitude: 52, longitude: -1)!
        await maps.load(origin: origin)
        let airport = try #require(maps.snapshots.flatMap(\.features).first { $0.label == "EGLL" })
        let point = try #require(airport.paths.first?.first)
        var preferences = MapLayerPreferences(); preferences.airspace = false; preferences.routes = false
        var camera = RadarCamera(radiusNM: 100)
        for _ in 0..<3 {
            let screen = camera.screen(ReceiverProjection(origin: origin).project(point), width: 1000, height: 600)
            let found = maps.candidates(at: CGPoint(x: screen.x, y: screen.y), camera: camera, size: CGSize(width: 1000, height: 600), preferences: preferences)
            #expect(found.contains { $0.id == airport.id })
            camera = camera.panned(dx: 50, dy: 20, width: 1000, height: 600).zoomed(by: 1.5)
        }
    }
}
