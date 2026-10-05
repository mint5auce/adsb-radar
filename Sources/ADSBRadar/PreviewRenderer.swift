#if DEBUG
import AppKit
import RadarCore
import SwiftUI

/// Offscreen visual verification only. Does not open or control a desktop window.
@MainActor
enum PreviewRenderer {
    static func render(to directory: String) async throws {
        var settings = RadarSettings()
        settings.receiver = GeographicCoordinate(latitude: 51.5, longitude: -2.5)
        settings.mode = .immediate
        guard let origin = settings.receiver else { throw CocoaError(.coderInvalidValue) }
        let fixture = PreviewSource(origin: origin)
        let model = RadarModel(source: fixture, initialSettings: settings)
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
        await model.shutdown()
        print("Rendered native previews in \(directory)")
    }

    private static func image(_ model: RadarModel, to url: URL, width: Double, height: Double) throws {
        let content = RadarWindow(model: model).frame(width: width, height: height).environment(\.colorScheme, .dark)
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
    init(origin: GeographicCoordinate) { self.origin = origin }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
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
                directionDegrees: Double(index * 43), source: "SYNTHETIC PREVIEW")
            }
        }
        return ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: observations))
    }
}
#endif
