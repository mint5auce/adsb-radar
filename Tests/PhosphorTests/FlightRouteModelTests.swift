import Foundation
import Testing
import RadarCore
@testable import Phosphor

struct FlightRouteModelTests {
    @Test @MainActor func freshCacheSurvivesDisabledEnrichmentButNotANewModel() async throws {
        let routes = RouteFixtureProvider()
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(source: RouteContactSource(), provider: IdentityFixtureProvider(), routeProvider: routes,
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        model.selectedAddress = "abc123"
        try await eventually { model.selectedRoute.match != nil }
        settings.enrichIdentities = false
        model.apply(settings)
        #expect(model.selectedRoute.match?.cached == true)
        model.selectedAddress = "def456"
        #expect(model.selectedRoute == .unknown)
        #expect(await routes.requests == ["BAW123"])
        await model.shutdown()
        let fresh = RadarModel(source: RouteContactSource(), provider: IdentityFixtureProvider(), routeProvider: routes,
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        fresh.start()
        try await eventually { fresh.contacts.count == 2 }
        fresh.selectedAddress = "abc123"
        #expect(fresh.selectedRoute == .unknown)
        #expect(await routes.requests == ["BAW123"])
        await fresh.shutdown()
    }

    @Test @MainActor func missingCallsignNeverMakesARouteRequest() async throws {
        let routes = RouteFixtureProvider()
        let source = RouteContactSource()
        await source.changeCallsign(" ")
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(source: source, provider: IdentityFixtureProvider(), routeProvider: routes,
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        model.selectedAddress = "abc123"
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.selectedRoute == .unknown)
        #expect(await routes.requests.isEmpty)
        await model.shutdown()
    }
    @Test @MainActor func callsignAndSelectionChangesDiscardLateResponses() async throws {
        let routes = RouteFixtureProvider(suspended: true)
        let source = RouteContactSource()
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(source: source, provider: IdentityFixtureProvider(), routeProvider: routes,
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        model.selectedAddress = "abc123"
        try await eventually { await routes.requests == ["BAW123"] }
        #expect(model.selectedRoute == .lookingUp)
        await source.changeCallsign("BAW456")
        try await eventually { await routes.requests.contains("BAW456") }
        await routes.complete("BAW456")
        try await eventually { model.selectedRoute.match?.route.callsign == "BAW456" }
        await routes.complete("BAW123")
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.selectedRoute.match?.route.callsign == "BAW456")
        model.selectedAddress = "def456"
        try await eventually { await routes.requests.contains("QFA31") }
        model.selectedAddress = nil
        await routes.complete("QFA31")
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.selectedRoute == .unknown)
        await model.shutdown()
    }

    @Test(arguments: [AircraftSourceKind.local, .online, .combined]) @MainActor
    func settingsStopLookupsInEveryRealModeAndSyntheticNeverRequests(sourceMode: AircraftSourceKind) async throws {
        let routes = RouteFixtureProvider(suspended: true)
        var settings = RadarSettings()
        settings.source = sourceMode
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(source: RouteContactSource(), provider: IdentityFixtureProvider(), routeProvider: routes,
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        model.selectedAddress = "abc123"
        try await eventually { await routes.requests == ["BAW123"] }
        settings.enrichIdentities = false
        model.apply(settings)
        await routes.complete("BAW123")
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.selectedRoute == .unknown)
        model.selectedAddress = "def456"
        #expect(model.selectedRoute == .unknown)
        #expect(await routes.requests == ["BAW123"])
        settings.source = .synthetic
        settings.enrichIdentities = true
        model.apply(settings)
        try await eventually { model.contacts.count == 2 }
        model.selectedAddress = "abc123"
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.selectedRoute == .unknown)
        #expect(await routes.requests == ["BAW123"])
        await model.shutdown()
    }

    @Test @MainActor func missingMatchesAreBrieflyCachedAndFailuresBackOffBeforeRecovery() async throws {
        let routes = RouteFixtureProvider(missing: true)
        var instant = Date.now
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(source: RouteContactSource(), provider: IdentityFixtureProvider(), routeProvider: routes,
                               routeNow: { instant }, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        model.selectedAddress = "abc123"
        try await eventually { await routes.requests.count == 1 && model.selectedRoute == .unknown }
        model.selectedAddress = nil
        model.selectedAddress = "abc123"
        try await Task.sleep(for: .milliseconds(150))
        #expect(await routes.requests.count == 1)
        await routes.fail()
        instant = instant.addingTimeInterval(300)
        try await eventually { await routes.requests.count == 2 && model.selectedRoute == .unknown }
        instant = instant.addingTimeInterval(29)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await routes.requests.count == 2)
        await routes.recover()
        instant = instant.addingTimeInterval(1)
        try await eventually { model.selectedRoute.match != nil }
        #expect(model.statuses[.local] == .receiving)
        await model.shutdown()
    }
    @Test @MainActor func reselectingUsesSessionCacheAndExpiryLeavesUnknownDuringAnOutage() async throws {
        let routes = RouteFixtureProvider()
        var instant = Date.now
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(source: RouteContactSource(), provider: IdentityFixtureProvider(), routeProvider: routes,
                               routeNow: { instant }, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        model.selectedAddress = "abc123"
        try await eventually { model.selectedRoute.match != nil }
        model.selectedAddress = nil
        model.selectedAddress = "abc123"
        #expect(model.selectedRoute.match?.cached == true)
        #expect(await routes.requests == ["BAW123"])
        await routes.fail()
        instant = instant.addingTimeInterval(1800)
        try await eventually { model.selectedRoute == .unknown }
        #expect(model.statuses[.local] == .receiving)
        await model.shutdown()
    }
    @Test @MainActor func selectedContactGetsLikelyRouteWithoutChangingReception() async throws {
        let routes = RouteFixtureProvider()
        let source = RouteContactSource()
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let model = RadarModel(source: source, provider: IdentityFixtureProvider(), routeProvider: routes,
                               identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.contacts.count == 2 }
        #expect(await routes.requests.isEmpty)
        model.selectedAddress = "abc123"
        try await eventually { model.selectedRoute.match?.route.callsign == "BAW123" }
        #expect(model.selectedRoute.match?.route.airports.last?.icao == "OTHH")
        #expect(model.contacts.count == 2 && model.contacts.first?.observation.source == "LOCAL")
        #expect(model.statuses[.local] == .receiving)
        await model.shutdown()
    }
}

actor RouteFixtureProvider: FlightRouteProvider {
    var requests: [String] = []
    var failing = false
    var missing: Bool
    let suspended: Bool
    var pending: [String: CheckedContinuation<FlightRoute?, any Error>] = [:]
    init(suspended: Bool = false, missing: Bool = false) { self.suspended = suspended; self.missing = missing }
    func fail() { failing = true }
    func recover() { failing = false; missing = false }
    func complete(_ callsign: String) { pending.removeValue(forKey: callsign)?.resume(returning: fixture(callsign)) }
    func route(for callsign: String) async throws -> FlightRoute? {
        requests.append(callsign)
        if failing { throw URLError(.notConnectedToInternet) }
        if missing { return nil }
        if suspended { return try await withCheckedThrowingContinuation { pending[callsign] = $0 } }
        return fixture(callsign)
    }
    private func fixture(_ callsign: String) -> FlightRoute {
        FlightRoute(callsign: callsign, airports: [
            FlightRouteAirport(name: "London Heathrow Airport", icao: "EGLL", iata: "LHR", coordinate: SyntheticSource.exampleLocation),
            FlightRouteAirport(name: "Hamad International Airport", icao: "OTHH", iata: "DOH", coordinate: GeographicCoordinate(latitude: 25.2731, longitude: 51.6081)!)
        ], provider: "Test routes", sourceURL: URL(string: "https://example.test/routes")!)
    }
}

actor RouteContactSource: AircraftDataSource {
    var callsign = "BAW123"
    func changeCallsign(_ value: String) { callsign = value }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: [
            AircraftObservation(address: "abc123", callsign: callsign, position: SyntheticSource.exampleLocation, positionTime: .now, source: "LOCAL"),
            AircraftObservation(address: "def456", callsign: "QFA31", position: SyntheticSource.exampleLocation, positionTime: .now, source: "LOCAL")
        ]))
    }
}
