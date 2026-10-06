#if DEBUG
import AppKit
import RadarCore
import SwiftUI

/// Offscreen visual verification only. Does not open or control a desktop window.
@MainActor
enum PreviewRenderer {
    static func render(to directory: String, options: RadarLaunchOptions = RadarLaunchOptions(), online: Bool = false, combined: Bool = false, localEnrichment: Bool = false, cachePreview: Bool = false) async throws {
        if cachePreview { try await renderCacheSequence(to: directory); return }
        var settings = options.applying(to: RadarSettings())
        let syntheticPlayback = options.source == .synthetic
        settings.receiver = syntheticPlayback && !CommandLine.arguments.contains("--preview-filters") ? nil : SyntheticSource.exampleLocation
        settings.source = localEnrichment ? .local : combined ? .combined : online ? .online : .synthetic
        settings.mode = .immediate
        let fixture: (any AircraftDataSource)? = syntheticPlayback ? nil : PreviewSource(origin: SyntheticSource.exampleLocation, source: online ? "adsb.fi" : "SYNTHETIC PREVIEW")
        let suite = "adsb-radar-preview-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let localFixture = PreviewSource(origin: SyntheticSource.exampleLocation, source: "LOCAL RTL-SDR")
        let onlineFixture = PreviewSource(origin: SyntheticSource.exampleLocation, source: "adsb.fi")
        let sources: [AircraftFeed: any AircraftDataSource] = combined ? [.local: localFixture, .online: onlineFixture] : localEnrichment ? [.local: localFixture] : [:]
        let model = RadarModel(source: combined || localEnrichment ? nil : fixture, sources: sources, provider: PreviewIdentityProvider(), identityStorage: FileAircraftIdentityStorage(url: URL(fileURLWithPath: directory).appendingPathComponent("preview-identities.json")), initialSettings: settings, defaults: defaults)
        model.start()
        for _ in 0..<100 {
            if model.geography != nil, !model.contacts.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await image(model, to: folder.appendingPathComponent("radar.png"), width: 1200, height: 800)
        model.selectedAddress = model.contacts.first?.id
        if online || combined || localEnrichment {
            for _ in 0..<50 {
                if model.selectedIdentity?.complete == true { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try await image(model, to: folder.appendingPathComponent("inspection.png"), width: 1200, height: 800)
        model.camera = model.camera.panned(dx: 180, dy: -90, width: 944, height: 680).zoomed(by: 1.5)
        try await image(model, to: folder.appendingPathComponent("panned.png"), width: 1000, height: 640)
        try await image(model, to: folder.appendingPathComponent("minimum-window.png"), width: 800, height: 560)
        try await image(RadarSettingsView(settings: model.settings, save: { _ in }),
            to: folder.appendingPathComponent("settings.png"), width: 560, height: 680)
        if localEnrichment {
            var offline = model.settings
            offline.enrichIdentities = false
            model.apply(offline)
            try await image(model, to: folder.appendingPathComponent("disabled-enrichment.png"), width: 800, height: 560)
        }
        if combined {
            var timing = model.settings
            timing.staleSeconds = 1
            model.apply(timing)
            try await image(model, to: folder.appendingPathComponent("local-source.png"), width: 1200, height: 800)
            await localFixture.fail()
            try await Task.sleep(for: .seconds(2.2))
            try await image(model, to: folder.appendingPathComponent("online-fallback.png"), width: 800, height: 560)
            await localFixture.recover()
            await model.retry(feed: .local)
            try await Task.sleep(for: .seconds(1.2))
            try await image(model, to: folder.appendingPathComponent("local-recovery.png"), width: 1200, height: 800)
        }
        if online {
            var wideSettings = model.settings
            wideSettings.onlineRadiusNM = 60
            wideSettings.distanceUnit = .kilometres
            model.apply(wideSettings)
            model.camera.radiusNM = 300
            try await image(model, to: folder.appendingPathComponent("search-limit.png"), width: 1200, height: 800)
            try await image(model, to: folder.appendingPathComponent("search-limit-minimum.png"), width: 800, height: 560)
            model.returnToReceiver()
            model.setMode(.sweep)
            try await Task.sleep(for: .seconds(4.1))
            try await image(model, to: folder.appendingPathComponent("sweep.png"), width: 1200, height: 800)
            if let fixture = fixture as? PreviewSource { await fixture.fail() }
            try await Task.sleep(for: .milliseconds(250))
            try await image(model, to: folder.appendingPathComponent("outage.png"), width: 800, height: 560)
        }
        if CommandLine.arguments.contains("--preview-filters") {
            var filters = model.settings.aircraftFilters
            filters.homeDistanceNM = 50
            model.setAircraftFilters(filters)
            try await image(model, to: folder.appendingPathComponent("home-filter.png"), width: 800, height: 560)
            try await image(AircraftFiltersView(model: model), to: folder.appendingPathComponent("filters.png"), width: 400, height: 460)
        }
        await model.shutdown()
        print("Rendered native previews in \(directory)")
    }

    private static func renderCacheSequence(to directory: String) async throws {
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storage = FileAircraftIdentityStorage(url: folder.appendingPathComponent("restart-identities-\(UUID()).json"))
        let suite = "adsb-cache-preview-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        let original = RadarModel(sources: [.local: PreviewSource(origin: SyntheticSource.exampleLocation, source: "LOCAL RTL-SDR")],
            provider: PreviewIdentityProvider(registration: "G-CACHED", aircraftType: "A319", updatedAt: Date.now.addingTimeInterval(-8 * 86400)),
            identityStorage: storage, initialSettings: settings, defaults: defaults)
        original.start()
        try await waitForIdentity(original)
        try await image(original, to: folder.appendingPathComponent("before-restart.png"), width: 1200, height: 800)
        await original.shutdown()

        let offline = RadarModel(sources: [.local: PreviewSource(origin: SyntheticSource.exampleLocation, source: "LOCAL RTL-SDR")],
            provider: PreviewIdentityProvider(failing: true), identityStorage: storage, initialSettings: settings, defaults: defaults)
        offline.start()
        try await waitForIdentity(offline)
        try await Task.sleep(for: .milliseconds(600))
        try await image(offline, to: folder.appendingPathComponent("restart-offline.png"), width: 1200, height: 800)
        settings.enrichIdentities = false
        offline.apply(settings)
        try await image(offline, to: folder.appendingPathComponent("restart-disabled.png"), width: 800, height: 560)
        await offline.shutdown()

        settings.enrichIdentities = true
        let refreshed = RadarModel(sources: [.local: PreviewSource(origin: SyntheticSource.exampleLocation, source: "LOCAL RTL-SDR")],
            provider: PreviewIdentityProvider(registration: "G-REFRESH", aircraftType: "B738"), identityStorage: storage,
            initialSettings: settings, defaults: defaults)
        refreshed.start()
        try await waitForIdentity(refreshed)
        for _ in 0..<60 {
            if refreshed.selectedIdentity?.registration?.value == "G-REFRESH" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await image(refreshed, to: folder.appendingPathComponent("refreshed.png"), width: 1200, height: 800)
        try await image(RadarSettingsView(settings: refreshed.settings, save: { _ in }),
            to: folder.appendingPathComponent("settings.png"), width: 560, height: 680)
        await refreshed.shutdown()
        print("Rendered cache restart / offline / refresh native views in \(directory)")
    }

    private static func waitForIdentity(_ model: RadarModel) async throws {
        for _ in 0..<100 {
            if model.geography != nil, !model.contacts.isEmpty {
                model.selectedAddress = model.contacts.first?.id
                if model.selectedIdentity?.complete == true { return }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CocoaError(.fileReadUnknown)
    }

    private static func image(_ model: RadarModel, to url: URL, width: Double, height: Double) async throws {
        try await image(RadarWindow(model: model), to: url, width: width, height: height)
    }

    private static func image<Content: View>(_ content: Content, to url: URL, width: Double, height: Double) async throws {
        let content = content.frame(width: width, height: height).environment(\.colorScheme, .dark)
        let view = NSHostingView(rootView: content)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
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
    func recover() { failed = false }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        if failed { return ReceptionReading(status: .failed("Source unavailable. Retrying automatically.")) }
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

#if DEBUG
private struct PreviewIdentityProvider: OnlineAircraftProvider, AircraftIdentityProvider {
    var registration = "G-TEST"
    var aircraftType = "A320"
    var updatedAt = Date.now
    var failing = false
    func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot { ReceiverSnapshot(observations: []) }
    func identities(for addresses: [String]) async throws -> [AircraftIdentityUpdate] {
        if failing { throw URLError(.notConnectedToInternet) }
        return addresses.map { AircraftIdentityUpdate(address: $0, registration: registration, aircraftType: aircraftType, updatedAt: updatedAt) }
    }
}
#endif
