import Foundation
import Observation
import RadarCore
import SwiftUI

@MainActor
@Observable
final class RadarModel {
    private(set) var settings: RadarSettings
    private(set) var contacts: [PresentedContact] = []
    private(set) var reception: ReceptionStatus = .starting
    private(set) var heardWithoutPosition = 0
    private(set) var geography: GeographyPaths?
    private(set) var mapMessage: String?
    private(set) var retrying = false
    var selectedAddress: String?
    var camera: RadarCamera
    let sweepStartedAt = Date.now

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let source: any AircraftDataSource
    @ObservationIgnored private var session: RadarSession
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var mapTask: Task<Void, Never>?
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var pendingRestart = false

    init(source: any AircraftDataSource = ReadsbReceiver(), initialSettings: RadarSettings? = nil) {
        self.source = source
        defaults = .standard
        let saved = initialSettings ?? defaults.data(forKey: "radar-settings")
            .flatMap { try? JSONDecoder().decode(RadarSettings.self, from: $0) } ?? RadarSettings()
        var configured = saved.validated()
        let env = ProcessInfo.processInfo.environment
        if initialSettings == nil, let lat = env["ADSB_RADAR_LATITUDE"].flatMap(Double.init),
           let lon = env["ADSB_RADAR_LONGITUDE"].flatMap(Double.init) {
            configured.receiver = GeographicCoordinate(latitude: lat, longitude: lon)
        }
        settings = configured
        camera = RadarCamera(radiusNM: configured.initialRadiusNM)
        session = RadarSession(startedAt: sweepStartedAt)
    }

    var selectedContact: PresentedContact? { contacts.first { $0.id == selectedAddress } }

    func start() {
        guard loop == nil, !shuttingDown else { return }
        loadGeography()
        loop = Task {
            await source.start(location: settings.receiver)
            var nextRead = Date.distantPast
            while !Task.isCancelled {
                let now = Date.now
                if now >= nextRead {
                    let reading = await source.poll()
                    guard !Task.isCancelled else { break }
                    reception = reading.status
                    if let snapshot = reading.snapshot {
                        heardWithoutPosition = snapshot.heardWithoutPosition
                        session.ingest(snapshot)
                    }
                    nextRead = now.addingTimeInterval(1)
                }
                contacts = session.advance(to: now, settings: settings)
                if let selectedAddress, !contacts.contains(where: { $0.id == selectedAddress }) {
                    self.selectedAddress = nil
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
            }
        }
    }

    func retry() async {
        guard !shuttingDown else { return }
        if retrying { pendingRestart = true; return }
        retrying = true
        reception = .starting
        repeat {
            pendingRestart = false
            await source.start(location: settings.receiver)
        } while pendingRestart && !shuttingDown
        retrying = false
    }

    func shutdown() async {
        shuttingDown = true
        mapTask?.cancel()
        loop?.cancel()
        await loop?.value
        loop = nil
        await source.stop()
    }

    func apply(_ value: RadarSettings) {
        let previous = settings
        settings = value.validated()
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "radar-settings") }
        if settings.initialRadiusNM != previous.initialRadiusNM { camera.radiusNM = settings.initialRadiusNM }
        if settings.receiver != previous.receiver {
            camera.offset = RadarPoint()
            session = RadarSession(startedAt: sweepStartedAt)
            contacts = []
            selectedAddress = nil
            loadGeography()
            Task { await retry() }
        }
    }

    func setMode(_ mode: UpdateMode) {
        var changed = settings
        changed.mode = mode
        apply(changed)
    }

    func returnToReceiver() {
        camera = RadarCamera(radiusNM: settings.initialRadiusNM)
    }

    private func loadGeography() {
        mapTask?.cancel()
        geography = nil
        guard let origin = settings.receiver else { mapMessage = nil; return }
        mapMessage = "LOADING GEOGRAPHY"
        mapTask = Task {
            do {
                let paths = try await GeographyPaths.load(origin: origin)
                guard !Task.isCancelled, settings.receiver == origin else { return }
                geography = paths
                mapMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                mapMessage = "OFFLINE GEOGRAPHY UNAVAILABLE"
            }
        }
    }
}
