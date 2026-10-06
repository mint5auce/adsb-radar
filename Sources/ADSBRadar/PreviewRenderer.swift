#if DEBUG
import AppKit
import RadarCore
import SwiftUI

/// Offscreen visual verification only. Does not open or control a desktop window.
@MainActor
enum PreviewRenderer {
    static func render(to directory: String, options: RadarLaunchOptions = RadarLaunchOptions(), online: Bool = false) async throws {
        var settings = options.applying(to: RadarSettings())
        let syntheticPlayback = options.source == .synthetic
        settings.receiver = syntheticPlayback ? nil : SyntheticSource.exampleLocation
        settings.source = online ? .online : .synthetic
        settings.mode = .immediate
        let fixture: (any AircraftDataSource)? = syntheticPlayback ? nil : PreviewSource(origin: SyntheticSource.exampleLocation, source: online ? "adsb.fi" : "SYNTHETIC PREVIEW")
        let suite = "adsb-radar-preview-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = RadarModel(source: fixture, initialSettings: settings, defaults: defaults)
        model.start()
        for _ in 0..<100 {
            if model.geography != nil, !model.contacts.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try image(model, to: folder.appendingPathComponent("radar.png"), width: 1200, height: 800)
        model.selectedAddress = model.contacts.first?.id
        try image(model, to: folder.appendingPathComponent("inspection.png"), width: 1200, height: 800)
        model.camera = model.camera.panned(dx: 180, dy: -90, width: 944, height: 680).zoomed(by: 1.5)
        try image(model, to: folder.appendingPathComponent("panned.png"), width: 1000, height: 640)
        try image(model, to: folder.appendingPathComponent("minimum-window.png"), width: 800, height: 560)
        try image(RadarSettingsView(settings: model.settings, save: { _ in }),
            to: folder.appendingPathComponent("settings.png"), width: 560, height: 680)
        if online {
            var wideSettings = model.settings
            wideSettings.onlineRadiusNM = 60
            wideSettings.distanceUnit = .kilometres
            model.apply(wideSettings)
            model.camera.radiusNM = 300
            try image(model, to: folder.appendingPathComponent("search-limit.png"), width: 1200, height: 800)
            try image(model, to: folder.appendingPathComponent("search-limit-minimum.png"), width: 800, height: 560)
            model.returnToReceiver()
            model.setMode(.sweep)
            try await Task.sleep(for: .seconds(4.1))
            try image(model, to: folder.appendingPathComponent("sweep.png"), width: 1200, height: 800)
            if let fixture = fixture as? PreviewSource { await fixture.fail() }
            try await Task.sleep(for: .milliseconds(250))
            try image(model, to: folder.appendingPathComponent("outage.png"), width: 800, height: 560)
        }
        await model.shutdown()
        print("Rendered native previews in \(directory)")
    }

    private static func image(_ model: RadarModel, to url: URL, width: Double, height: Double) throws {
        try image(RadarWindow(model: model), to: url, width: width, height: height)
    }

    private static func image<Content: View>(_ content: Content, to url: URL, width: Double, height: Double) throws {
        let content = content.frame(width: width, height: height).environment(\.colorScheme, .dark)
        let view = NSHostingView(rootView: content)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}

private actor PreviewSource: AircraftDataSource {
    let origin: GeographicCoordinate
    let source: String
    var failed = false
    init(origin: GeographicCoordinate, source: String) { self.origin = origin; self.source = source }
    func fail() { failed = true }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        if failed { return ReceptionReading(status: .failed("Online unavailable. Retrying automatically.")) }
        let now = Date.now
        let observations: [AircraftObservation] = (0..<8).flatMap { index in
            let latitude = origin.latitude + Double(index - 3) * 0.17
            let longitude = origin.longitude + sin(Double(index)) * 1.2
            let age: Double = index == 7 ? 20 : Double(index)
            let heading = Double(index * 43) * .pi / 180
            // Seed ordered synthetic history as well as each contact's current position.
            return (0..<6).map { sample in
            let behind = Double(5 - sample)
            let position = GeographicCoordinate(latitude: latitude - cos(heading) * behind * 0.02,
                longitude: longitude - sin(heading) * behind * 0.03)
            return AircraftObservation(address: String(format: "abc%03x", index), callsign: "TEST\(101 + index)",
                position: position, positionTime: now.addingTimeInterval(-age - behind * 10),
                altitude: .feet(Double(12000 + index * 3000)), speedKnots: Double(280 + index * 18),
                directionDegrees: Double(index * 43), source: source)
            }
        }
        return ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: observations))
    }
}
#endif
