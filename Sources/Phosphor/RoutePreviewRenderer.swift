#if DEBUG
import AppKit
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
        let model = RadarModel(source: RoutePreviewSource(), provider: provider, routeProvider: provider, photoProvider: PhotoPreviewProvider(),
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
            if let contact = model.selectedContact {
                try fullSidebar(ContactInspector(contact: contact, identity: model.selectedIdentity, settings: settings,
                                                 route: state, category: model.reportedCategory(for: contact), showOnMap: {}) {},
                                to: folder.appendingPathComponent(name + "-sidebar.png"))
            }
        }
        var callsignSettings = settings
        callsignSettings.aircraftIdentifier = .callsign
        model.apply(callsignSettings)
        if let contact = model.selectedContact {
            try fullSidebar(ContactInspector(contact: contact, identity: model.selectedIdentity, settings: callsignSettings,
                                             route: route, category: model.reportedCategory(for: contact), showOnMap: {}) {},
                            to: folder.appendingPathComponent("callsign-sidebar.png"))
        }
        model.apply(settings)
        model.selectedAddress = "def456"
        if let contact = model.selectedContact {
            try fullSidebar(ContactInspector(contact: contact, identity: nil, settings: settings, showOnMap: {}, outsideFilters: true) {},
                            to: folder.appendingPathComponent("missing-stale-sidebar.png"))
        }
        model.selectedAddress = nil
        model.selectedAddress = "abc123"
        try await image(FlightRouteInspector(state: model.selectedRoute).padding(24).background(RadarStyle.panel),
                        to: folder.appendingPathComponent("cached-route.png"), width: 256, height: 560)
        try await image(RadarSettingsView(model: model, updater: AppUpdater(), save: { _ in }),
                        to: folder.appendingPathComponent("settings.png"), width: 560, height: 680)
        await model.shutdown()
    }

    static func interactiveRouteModel() -> RadarModel {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.source = .local
        settings.mode = .immediate
        settings.controlVisibility = .alwaysVisible
        let provider = RoutePreviewProvider()
        let maps = MapLayerModel(store: MapSnapshotStore(directory: URL.temporaryDirectory.appendingPathComponent("phosphor-sidebar-map-data")),
                                 updater: MapUpdateService(download: { _ in throw URLError(.notConnectedToInternet) }))
        return RadarModel(source: RoutePreviewSource(), provider: provider, routeProvider: provider, photoProvider: PhotoPreviewProvider(),
                          identityStorage: FileAircraftIdentityStorage(url: URL.temporaryDirectory.appendingPathComponent("phosphor-sidebar-identities-\(UUID()).json")),
                          mapLayers: maps, initialSettings: settings, defaults: UserDefaults(suiteName: "phosphor-sidebar-ui-verification")!)
    }

    private static func fullSidebar(_ inspector: ContactInspector, to url: URL) throws {
        let renderer = ImageRenderer(content: inspector.content.frame(width: 256).background(RadarStyle.panel).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}

private struct RoutePreviewProvider: FlightRouteProvider, OnlineAircraftProvider, AircraftIdentityProvider {
    func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot { ReceiverSnapshot(observations: []) }
    func identities(for addresses: [String]) async throws -> [AircraftIdentityUpdate] { [] }
    func route(for callsign: String) async throws -> FlightRoute? {
        if callsign == "DELAY1" { try await Task.sleep(for: .seconds(6)) }
        guard callsign == "QFA31" || callsign == "DELAY1" else { return nil }
        return FlightRoute(callsign: callsign, airports: [
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
                                positionTime: .now, altitude: .feet(35000), speedKnots: 450, directionDegrees: 80, category: .heavy, source: "LOCAL FIXTURE"),
            AircraftObservation(address: "def456", callsign: "NOMATCH", position: GeographicCoordinate(latitude: 51.7, longitude: -2.2),
                                positionTime: Date.now.addingTimeInterval(-20), source: "LOCAL FIXTURE"),
            AircraftObservation(address: "4067ce", callsign: "DELAY1", position: GeographicCoordinate(latitude: 51.5, longitude: -2.5),
                                positionTime: .now, altitude: .feet(875), speedKnots: 115, directionDegrees: 233, category: .helicopter, source: "LOCAL FIXTURE")
        ], identities: [
            AircraftIdentityUpdate(address: "abc123", registration: "VH-LONG8", aircraftType: "A388", modelDescription: "AIRBUS A380-842",
                                   ownerOperator: "Example Airline and Aircraft Leasing Company Limited", category: .heavy),
            AircraftIdentityUpdate(address: "4067ce", registration: "G-WPDD", aircraftType: "EC35", category: .helicopter)
        ]))
    }
}
#endif
