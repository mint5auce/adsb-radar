import Foundation
import Observation
import RadarCore
import SwiftUI

@MainActor
@Observable
final class RadarModel {
    private(set) var settings: RadarSettings
    private(set) var contacts: [PresentedContact] = []
    private(set) var identities: [String: AircraftIdentity] = [:]
    private(set) var statuses: [AircraftFeed: ReceptionStatus] = [:]
    private(set) var heardWithoutPosition = 0
    private(set) var geography: GeographyPaths?
    private(set) var mapMessage: String?
    var selectedAddress: String? { didSet { if selectedAddress != oldValue { cancelIdentityRequest() } } }
    var camera: RadarCamera { didSet { if camera != oldValue { scheduleSearchUpdate() } } }
    private(set) var sweepStartedAt: Date
    private(set) var viewportWidth: Double = 800
    private(set) var viewportHeight: Double = 600

    @ObservationIgnored private let provider: any OnlineAircraftProvider & AircraftIdentityProvider
    @ObservationIgnored private let identityStorage: any AircraftIdentityStorage
    @ObservationIgnored private var cacheLoad: Task<Void, Never>?
    @ObservationIgnored private var cacheLoop: Task<Void, Never>?
    @ObservationIgnored private var savedIdentities: [String: AircraftIdentity] = [:]
    @ObservationIgnored private var catalogue = AircraftIdentityCatalogue()
    @ObservationIgnored private var identityLoop: Task<Void, Never>?
    @ObservationIgnored private var identityRequest: Task<[AircraftIdentityUpdate], any Error>?
    @ObservationIgnored private var identityRevision = 0
    @ObservationIgnored private let preferences: RadarPreferences
    @ObservationIgnored private let suppliedSource: (any AircraftDataSource)?
    @ObservationIgnored private let suppliedSources: [AircraftFeed: any AircraftDataSource]
    @ObservationIgnored private var runs: [AircraftFeed: FeedRun] = [:]
    @ObservationIgnored private var session: RadarSession
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var mapTask: Task<Void, Never>?
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var transitionRevision = 0
    @ObservationIgnored private var searchRevision = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    private final class FeedRun {
        let id = UUID()
        let source: any AircraftDataSource
        var task: Task<Void, Never>?
        init(source: any AircraftDataSource) { self.source = source }
    }

    init(source: (any AircraftDataSource)? = nil, sources: [AircraftFeed: any AircraftDataSource] = [:],
         provider: any OnlineAircraftProvider & AircraftIdentityProvider = ADSBFiProvider(),
         identityStorage: any AircraftIdentityStorage = FileAircraftIdentityStorage(),
         initialSettings: RadarSettings? = nil, options: RadarLaunchOptions = RadarLaunchOptions(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.identityStorage = identityStorage
        suppliedSource = source
        suppliedSources = sources
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
        session = RadarSession(startedAt: startedAt, enabledFeeds: configured.source.feeds)
    }

    struct FeedHealth: Identifiable {
        var id: AircraftFeed { feed }
        let feed: AircraftFeed
        let status: ReceptionStatus
    }

    var feedHealth: [FeedHealth] {
        AircraftFeed.allCases.filter { settings.source.feeds.contains($0) }.map {
            FeedHealth(feed: $0, status: statuses[$0] ?? .starting)
        }
    }

    var eligibleContacts: [PresentedContact] {
        contacts.filter { $0.id == selectedAddress || matchesFilters($0) }
    }
    func matchesFilters(_ contact: PresentedContact) -> Bool {
        settings.aircraftFilters.matches(contact.observation, home: settings.receiver)
    }
    var selectedOutsideFilters: Bool { selectedContact.map { !matchesFilters($0) } ?? false }
    func isInView(_ contact: PresentedContact) -> Bool {
        guard let origin, let position = contact.observation.position else { return false }
        let point = camera.screen(ReceiverProjection(origin: origin).project(position), width: viewportWidth, height: viewportHeight)
        return (0...viewportWidth).contains(point.x) && (0...viewportHeight).contains(point.y)
    }
    struct ContactCounts {
        let inView: Int
        let outsideView: Int
        let filtered: Int
    }
    var contactCounts: ContactCounts {
        let eligible = eligibleContacts
        let inView = eligible.filter { isInView($0) }.count
        return ContactCounts(inView: inView, outsideView: eligible.count - inView, filtered: contacts.count - eligible.count)
    }
    func setAircraftFilters(_ filters: AircraftViewFilters) {
        guard filters.validationMessage == nil else { return }
        var changed = settings
        changed.aircraftFilters = filters
        apply(changed)
    }
    func clearAircraftFilters() { setAircraftFilters(AircraftViewFilters()) }
    var filterSummary: String {
        guard settings.aircraftFilters.isActive else { return "Unrestricted aircraft" }
        if let distance = settings.aircraftFilters.homeDistanceNM {
            return settings.receiver == nil ? "Home distance unavailable" : "Within \(settings.distance(distance)) of Home"
        }
        return "Aircraft filters active"
    }

    var selectedContact: PresentedContact? { contacts.first { $0.id == selectedAddress } }
    var selectedIdentity: AircraftIdentity? {
        guard settings.source != .synthetic, let contact = selectedContact else { return nil }
        return identities[contact.observation.address]
    }
    var showsOnlineAttribution: Bool {
        settings.source != .synthetic && (settings.source.usesOnline || settings.enrichIdentities || !identities.isEmpty)
    }
    var retrying: Bool { statuses.values.contains(.starting) }
    var reception: ReceptionStatus {
        statuses[settings.source == .online ? .online : settings.source == .synthetic ? .synthetic : .local] ?? .starting
    }
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
        guard settings.source.usesOnline, let origin else { return nil }
        return OnlineCoverage(origin: origin, camera: camera, width: viewportWidth, height: viewportHeight, limitNM: settings.onlineRadiusNM)
    }

    func updateViewport(width: Double, height: Double) {
        guard width > 0, height > 0, width != viewportWidth || height != viewportHeight else { return }
        viewportWidth = width
        viewportHeight = height
        scheduleSearchUpdate()
    }

    private func scheduleSearchUpdate() {
        cancelIdentityRequest()
        searchRevision += 1
        searchTask?.cancel()
        guard settings.source.usesOnline, !shuttingDown else { return }
        let revision = searchRevision
        searchTask = Task {
            if let feed = runs[.online]?.source as? OnlineFeed { await feed.suspendSearch() }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard revision == searchRevision, !Task.isCancelled,
                  let coverage = onlineCoverage, let feed = runs[.online]?.source as? OnlineFeed else { return }
            await feed.update(search: coverage.search, interval: settings.onlineRefreshSeconds)
        }
    }

    func start() {
        guard loop == nil, !shuttingDown else { return }
        loadGeography()
        loop = Task {
            while !Task.isCancelled {
                advanceDisplay()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
            }
        }
        reconcileFeeds()
        startIdentityCache()
        startIdentityLoop()
    }

    private func startIdentityCache() {
        cacheLoad = Task {
            do {
                let saved = try await identityStorage.load()
                catalogue.restore(saved)
                savedIdentities = saved
                identities = catalogue.identities
            } catch {
                // Missing, corrupt or unreadable storage never prevents reception or enrichment.
            }
        }
        cacheLoop = Task {
            await cacheLoad?.value
            var retryAfter = Date.distantPast
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                guard !Task.isCancelled, identities != savedIdentities, Date.now >= retryAfter else { continue }
                let snapshot = identities
                do {
                    try await identityStorage.save(snapshot)
                    savedIdentities = snapshot
                } catch { retryAfter = Date.now.addingTimeInterval(30) }
            }
        }
    }

    private func cancelIdentityRequest() {
        identityRevision += 1
        identityRequest?.cancel()
    }

    private func relevantIdentityAddresses() -> [String] {
        guard let origin else { return [] }
        let projection = ReceiverProjection(origin: origin)
        return contacts.compactMap { contact in
            guard let position = contact.observation.position else { return nil }
            let screen = camera.screen(projection.project(position), width: viewportWidth, height: viewportHeight)
            guard (0...viewportWidth).contains(screen.x), (0...viewportHeight).contains(screen.y) else { return nil }
            return contact.observation.address
        }
    }

    private func startIdentityLoop() {
        identityLoop = Task {
            await cacheLoad?.value
            while !Task.isCancelled {
                if settings.enrichIdentities, settings.source != .synthetic {
                    let batch = catalogue.begin(visible: relevantIdentityAddresses(),
                        selected: selectedContact?.observation.address, at: .now, refreshAge: settings.identityRefreshDays * 86400)
                    if !batch.isEmpty {
                        let revision = identityRevision
                        let provider = provider
                        let request = Task { try await provider.identities(for: batch) }
                        identityRequest = request
                        do {
                            let updates = try await withTaskCancellationHandler { try await request.value }
                                onCancel: { request.cancel() }
                            if revision == identityRevision, !Task.isCancelled, settings.enrichIdentities, settings.source != .synthetic {
                                catalogue.finish(batch, updates: updates, at: .now, refreshAge: settings.identityRefreshDays * 86400)
                                identities = catalogue.identities
                            } else { catalogue.cancel(batch) }
                        } catch {
                            if revision != identityRevision || Task.isCancelled || error is CancellationError {
                                catalogue.cancel(batch)
                            } else { catalogue.finish(batch, updates: [], at: .now, refreshAge: settings.identityRefreshDays * 86400) }
                        }
                        identityRequest = nil
                    }
                }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
            }
        }
    }

    private func advanceDisplay() {
        contacts = session.advance(to: .now, settings: displaySettings)
        if let selectedAddress, !contacts.contains(where: { $0.id == selectedAddress }) { self.selectedAddress = nil }
    }

    /// Retires only disabled or explicitly restarted sources; shared sources keep polling.
    /// Cleanup transitions serialize so a rapid toggle cannot start a replacement before stop completes.
    private func reconcileFeeds(restarting: Set<AircraftFeed> = []) {
        guard loop != nil, !shuttingDown else { return }
        transitionRevision += 1
        let revision = transitionRevision
        let enabled = settings.source.feeds
        let retired = runs.filter { !enabled.contains($0.key) || restarting.contains($0.key) }
        for (feed, run) in retired {
            runs.removeValue(forKey: feed)
            run.task?.cancel()
            statuses.removeValue(forKey: feed)
            if feed == .local { heardWithoutPosition = 0 }
        }
        let preceding = transition
        transition = Task {
            await preceding?.value
            for (_, run) in retired {
                await run.source.stop()
                await run.task?.value
            }
            guard revision == transitionRevision, !shuttingDown else { return }
            for feed in AircraftFeed.allCases where enabled.contains(feed) && runs[feed] == nil {
                let source = suppliedSources[feed] ?? suppliedSource ?? makeSource(feed)
                let run = FeedRun(source: source)
                runs[feed] = run
                statuses[feed] = .starting
                run.task = Task { await poll(feed: feed, run: run) }
            }
        }
    }

    private func poll(feed: AircraftFeed, run: FeedRun) async {
        var restart = true
        var retry = OnlineRefreshPolicy()
        while !Task.isCancelled {
            if restart {
                if Date.now < retry.nextAttempt {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                    continue
                }
                await run.source.stop()
                guard !Task.isCancelled else { break }
                await run.source.start(location: origin)
                if feed == .online, let online = run.source as? OnlineFeed, let coverage = onlineCoverage {
                    await online.update(search: coverage.search, interval: settings.onlineRefreshSeconds)
                }
                guard isCurrent(feed: feed, run: run) else { break }
                restart = false
            }
            let searchRevision = self.searchRevision
            let reading = await run.source.poll()
            guard isCurrent(feed: feed, run: run) else { break }
            if feed == .online, searchRevision != self.searchRevision { continue }
            statuses[feed] = reading.status
            if let snapshot = reading.snapshot {
                if feed == .local || feed == .synthetic { heardWithoutPosition = snapshot.heardWithoutPosition }
                session.ingest(snapshot, from: feed)
                if feed != .synthetic, !snapshot.identities.isEmpty {
                    catalogue.merge(snapshot.identities)
                    identities = catalogue.identities
                }
            }
            if feed == .local {
                if case .failed = reading.status {
                    retry.failed(at: .now, interval: 1)
                    restart = true
                } else if reading.status == .waiting || reading.status == .receiving {
                    retry.succeeded(at: .now, interval: 1)
                }
            }
            let interval = feed == .online ? 0.1 : feed == .synthetic ? min(1, settings.staleSeconds / 3) : 1
            do { try await Task.sleep(for: .seconds(interval)) } catch { break }
        }
    }

    private func isCurrent(feed: AircraftFeed, run: FeedRun) -> Bool {
        !Task.isCancelled && !shuttingDown && runs[feed]?.id == run.id && settings.source.feeds.contains(feed)
    }

    func retry(feed: AircraftFeed? = nil) async {
        guard !shuttingDown else { return }
        if settings.source == .synthetic { clearContacts() }
        let failed = Set(statuses.compactMap { key, value in if case .failed = value { key } else { nil } })
        let restarted = feed.map { Set([$0]) } ?? (failed.isEmpty ? settings.source.feeds : failed)
        reconcileFeeds(restarting: restarted)
    }

    func shutdown() async {
        shuttingDown = true
        transitionRevision += 1
        mapTask?.cancel()
        searchTask?.cancel()
        cancelIdentityRequest()
        identityLoop?.cancel()
        cacheLoop?.cancel()
        loop?.cancel()
        let active = runs
        runs = [:]
        for run in active.values { run.task?.cancel() }
        await transition?.value
        for run in active.values {
            await run.source.stop()
            await run.task?.value
        }
        await loop?.value
        await identityLoop?.value
        await cacheLoad?.value
        await cacheLoop?.value
        if identities != savedIdentities {
            do { try await identityStorage.save(identities); savedIdentities = identities }
            catch { /* In-memory identities remain useful even when persistence fails. */ }
        }
        cacheLoop = nil
        cacheLoad = nil
        identityLoop = nil
        loop = nil
        statuses = [:]
    }

    func apply(_ value: RadarSettings) {
        let previous = settings
        settings = value.validated()
        preferences.save(settings)
        if settings.enrichIdentities != previous.enrichIdentities || settings.source != previous.source ||
           settings.identityRefreshDays != previous.identityRefreshDays { cancelIdentityRequest() }
        if settings.initialRadiusNM != previous.initialRadiusNM { camera.radiusNM = settings.initialRadiusNM }
        let locationChanged = settings.receiver != previous.receiver
        let syntheticTransition = settings.source != previous.source && (settings.source == .synthetic || previous.source == .synthetic)
        let syntheticChanged = settings.source == .synthetic &&
            (settings.scenario != previous.scenario || settings.demoCount != previous.demoCount ||
             settings.staleSeconds != previous.staleSeconds || settings.removalSeconds != previous.removalSeconds ||
             settings.sweepSeconds != previous.sweepSeconds)
        if locationChanged || syntheticTransition || syntheticChanged { clearContacts() }
        else {
            session.setEnabledFeeds(settings.source.feeds)
            advanceDisplay()
        }
        if locationChanged || syntheticTransition || syntheticChanged || settings.source != previous.source {
            reconcileFeeds(restarting: locationChanged || syntheticChanged ? settings.source.feeds : [])
        }
        if settings.onlineRefreshSeconds != previous.onlineRefreshSeconds || settings.onlineRadiusNM != previous.onlineRadiusNM {
            scheduleSearchUpdate()
        }
        if locationChanged || syntheticTransition {
            camera.offset = RadarPoint()
            loadGeography()
        }
    }

    func setMode(_ mode: UpdateMode) {
        var changed = settings
        changed.mode = mode
        apply(changed)
    }

    func returnToReceiver() { camera = RadarCamera(radiusNM: settings.initialRadiusNM) }

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
        sweepStartedAt = .now
        contacts = []
        heardWithoutPosition = 0
        selectedAddress = nil
        session = RadarSession(startedAt: sweepStartedAt, enabledFeeds: settings.source.feeds)
    }

    private func makeSource(_ feed: AircraftFeed) -> any AircraftDataSource {
        switch feed {
        case .local: ReadsbReceiver()
        case .online: OnlineFeed(provider: provider, interval: settings.onlineRefreshSeconds, radiusNM: settings.onlineRadiusNM)
        case .synthetic: SyntheticSource(scenario: settings.scenario, demoCount: settings.demoCount, timing: settings)
        }
    }
}
