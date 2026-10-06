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
    var camera: RadarCamera { didSet { if camera != oldValue { scheduleSearchUpdate() } } }
    private(set) var sweepStartedAt: Date

    @ObservationIgnored private let preferences: RadarPreferences
    @ObservationIgnored private let suppliedSource: (any AircraftDataSource)?
    @ObservationIgnored private var source: (any AircraftDataSource)?
    @ObservationIgnored private var session: RadarSession
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sourceLoop: Task<Void, Never>?
    @ObservationIgnored private var mapTask: Task<Void, Never>?
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var sourceRevision = 0
    @ObservationIgnored private var searchRevision = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private(set) var viewportWidth: Double = 800
    private(set) var viewportHeight: Double = 600

    init(source: (any AircraftDataSource)? = nil, initialSettings: RadarSettings? = nil,
         options: RadarLaunchOptions = RadarLaunchOptions(), defaults: UserDefaults = .standard) {
        suppliedSource = source
        preferences = RadarPreferences(defaults: defaults, options: options)
        let saved = initialSettings ?? preferences.load()
        var configured = saved.validated()
        let env = ProcessInfo.processInfo.environment
        if initialSettings == nil, let lat = env["ADSB_RADAR_LATITUDE"].flatMap(Double.init),
           let lon = env["ADSB_RADAR_LONGITUDE"].flatMap(Double.init) {
            configured.receiver = GeographicCoordinate(latitude: lat, longitude: lon)
        }
        settings = configured
        camera = RadarCamera(radiusNM: configured.initialRadiusNM)
        let startedAt = Date.now
        sweepStartedAt = startedAt
        session = RadarSession(startedAt: startedAt)
    }

    var selectedContact: PresentedContact? { contacts.first { $0.id == selectedAddress } }

    var origin: GeographicCoordinate? {
        settings.receiver ?? (settings.source == .synthetic ? SyntheticSource.exampleLocation : nil)
    }

    // The example origin is a presentation input, never a saved receiver preference.
    var displaySettings: RadarSettings {
        var result = settings
        result.receiver = origin
        return result
    }


    var onlineCoverage: OnlineCoverage? {
        guard settings.source == .online, let origin else { return nil }
        return OnlineCoverage(origin: origin, camera: camera, width: viewportWidth, height: viewportHeight, limitNM: settings.onlineRadiusNM)
    }

    func updateViewport(width: Double, height: Double) {
        guard width > 0, height > 0, width != viewportWidth || height != viewportHeight else { return }
        viewportWidth = width
        viewportHeight = height
        scheduleSearchUpdate()
    }

    private func scheduleSearchUpdate() {
        searchRevision += 1
        searchTask?.cancel()
        guard settings.source == .online, !shuttingDown else { return }
        let revision = searchRevision
        searchTask = Task {
            if let feed = source as? OnlineFeed { await feed.suspendSearch() }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard revision == searchRevision, !Task.isCancelled,
                  let coverage = onlineCoverage, let feed = source as? OnlineFeed else { return }
            await feed.update(search: coverage.search, interval: settings.onlineRefreshSeconds)
        }
    }

    func start() {
        guard loop == nil, !shuttingDown else { return }
        loadGeography()
        loop = Task {
            while !Task.isCancelled {
                contacts = session.advance(to: .now, settings: displaySettings)
                if let selectedAddress, !contacts.contains(where: { $0.id == selectedAddress }) {
                    self.selectedAddress = nil
                }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
            }
        }
        startSourceLoop()
    }

    private func startSourceLoop() {
        sourceLoop = Task {
            var activeRevision: Int?
            while !Task.isCancelled {
                if activeRevision != sourceRevision {
                    await source?.stop()
                    guard !Task.isCancelled else { break }
                    let revision = sourceRevision
                    let configured = settings
                    let replacement: any AircraftDataSource = suppliedSource ?? Self.makeSource(configured)
                    source = replacement
                    await replacement.start(location: origin)
                    if let feed = replacement as? OnlineFeed, let coverage = onlineCoverage {
                        await feed.update(search: coverage.search, interval: settings.onlineRefreshSeconds)
                    }
                    guard !Task.isCancelled else { break }
                    guard revision == sourceRevision else { continue }
                    activeRevision = revision
                    retrying = false
                }
                guard let source else { break }
                let searchRevision = self.searchRevision
                let reading = await source.poll()
                guard !Task.isCancelled else { break }
                guard activeRevision == sourceRevision else { continue }
                if settings.source == .online, searchRevision != self.searchRevision { continue }
                reception = reading.status
                if let snapshot = reading.snapshot {
                    heardWithoutPosition = snapshot.heardWithoutPosition
                    session.ingest(snapshot)
                }
                let interval = settings.source == .online ? 0.1 : settings.source == .synthetic ? min(1, settings.staleSeconds / 3) : 1
                do { try await Task.sleep(for: .seconds(interval)) } catch { break }
            }
        }
    }

    func retry() async {
        guard !shuttingDown else { return }
        requestRestart()
    }

    func shutdown() async {
        shuttingDown = true
        mapTask?.cancel()
        searchTask?.cancel()
        loop?.cancel()
        sourceLoop?.cancel()
        await loop?.value
        loop = nil
        await source?.stop()
        await sourceLoop?.value
        sourceLoop = nil
        source = nil
    }

    func apply(_ value: RadarSettings) {
        let previous = settings
        settings = value.validated()
        preferences.save(settings)
        if settings.initialRadiusNM != previous.initialRadiusNM { camera.radiusNM = settings.initialRadiusNM }
        let originChanged = settings.receiver != previous.receiver || settings.source != previous.source
        let syntheticChanged = settings.source == .synthetic &&
            (settings.scenario != previous.scenario || settings.demoCount != previous.demoCount ||
             settings.staleSeconds != previous.staleSeconds || settings.removalSeconds != previous.removalSeconds ||
             settings.sweepSeconds != previous.sweepSeconds)
        if originChanged || syntheticChanged {
            requestRestart()
        }
        if settings.onlineRefreshSeconds != previous.onlineRefreshSeconds || settings.onlineRadiusNM != previous.onlineRadiusNM {
            scheduleSearchUpdate()
        }
        if originChanged {
            camera.offset = RadarPoint()
            loadGeography()
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
        guard let origin else { mapMessage = nil; return }
        mapMessage = "LOADING GEOGRAPHY"
        mapTask = Task {
            do {
                let paths = try await GeographyPaths.load(origin: origin)
                guard !Task.isCancelled, self.origin == origin else { return }
                geography = paths
                mapMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                mapMessage = "OFFLINE GEOGRAPHY UNAVAILABLE"
            }
        }
    }

    private func clearContacts() {
        contacts = []
        heardWithoutPosition = 0
        selectedAddress = nil
        session = RadarSession(startedAt: sweepStartedAt)
    }

    private func requestRestart() {
        sourceRevision += 1
        retrying = true
        reception = .starting
        sweepStartedAt = .now
        clearContacts()
        // Cancel slow requests immediately; the replacement loop stops its predecessor first.
        let previousLoop = sourceLoop
        previousLoop?.cancel()
        sourceLoop = Task {
            await previousLoop?.value
            guard !Task.isCancelled, !shuttingDown else { return }
            startSourceLoop()
        }
    }

    private static func makeSource(_ settings: RadarSettings) -> any AircraftDataSource {
        switch settings.source {
        case .local: ReadsbReceiver()
        case .online: OnlineFeed(interval: settings.onlineRefreshSeconds, radiusNM: settings.onlineRadiusNM)
        case .synthetic: SyntheticSource(scenario: settings.scenario, demoCount: settings.demoCount, timing: settings)
        }
    }
}
