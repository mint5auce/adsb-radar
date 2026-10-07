#if DEBUG
import Foundation
import RadarCore
import SwiftUI

extension PreviewRenderer {
    static func renderRoutes(to directory: String) async throws {
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.source = .local
        settings.mode = .immediate
        settings.controlVisibility = .alwaysVisible
        let suite = "phosphor-route-preview-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = RoutePreviewProvider()
        let model = RadarModel(source: RoutePreviewSource(), provider: provider, routeProvider: provider,
                               identityStorage: FileAircraftIdentityStorage(url: folder.appendingPathComponent("preview-identities.json")),
                               initialSettings: settings, defaults: defaults)
        model.start()
        for _ in 0..<100 {
            if !model.contacts.isEmpty, model.geography != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        model.selectedAddress = "abc123"
        for _ in 0..<100 {
            if model.selectedRoute.match != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        for (name, width, height) in [("inspection", 1200.0, 800.0), ("minimum-window", 800, 560)] {
            try await image(RadarWindow(model: model), to: folder.appendingPathComponent(name + ".png"), width: width, height: height)
        }
        let route = model.selectedRoute
        for (name, state) in [("matched", route), ("unknown", .unknown), ("loading", .lookingUp)] {
            try await image(FlightRouteInspector(state: state).padding(24).background(RadarStyle.panel),
                            to: folder.appendingPathComponent(name + "-route.png"), width: 256, height: 560)
        }
        model.selectedAddress = nil
        model.selectedAddress = "abc123"
        try await image(FlightRouteInspector(state: model.selectedRoute).padding(24).background(RadarStyle.panel),
                        to: folder.appendingPathComponent("cached-route.png"), width: 256, height: 560)
        try await image(RadarSettingsView(model: model, updater: AppUpdater(), save: { _ in }),
                        to: folder.appendingPathComponent("settings.png"), width: 560, height: 680)
        await model.shutdown()
    }
}

private struct RoutePreviewProvider: FlightRouteProvider, OnlineAircraftProvider, AircraftIdentityProvider {
    func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot { ReceiverSnapshot(observations: []) }
    func identities(for addresses: [String]) async throws -> [AircraftIdentityUpdate] { [] }
    func route(for callsign: String) async throws -> FlightRoute? {
        FlightRoute(callsign: callsign, airports: [
            FlightRouteAirport(name: "Sydney Kingsford Smith International Airport", icao: "YSSY", iata: "SYD", coordinate: GeographicCoordinate(latitude: -33.9461, longitude: 151.177)!),
            FlightRouteAirport(name: "Singapore Changi Airport", icao: "WSSS", iata: "SIN", coordinate: GeographicCoordinate(latitude: 1.35019, longitude: 103.994)!),
            FlightRouteAirport(name: "London Heathrow Airport", icao: "EGLL", iata: "LHR", coordinate: GeographicCoordinate(latitude: 51.4706, longitude: -0.461941)!)
        ], provider: "Virtual Radar Server / adsb.lol", sourceURL: VirtualRadarRouteProvider.sourceURL)
    }
}

private actor RoutePreviewSource: AircraftDataSource {
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: [
            AircraftObservation(address: "abc123", callsign: "QFA31", position: SyntheticSource.exampleLocation,
                                positionTime: .now, altitude: .feet(35000), speedKnots: 450, directionDegrees: 80)
        ]))
    }
}
#endif
