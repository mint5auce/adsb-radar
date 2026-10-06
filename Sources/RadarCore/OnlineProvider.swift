import CoreFoundation
import Foundation

public struct OnlineSearch: Equatable, Sendable {
    public let centre: GeographicCoordinate
    public let radiusNM: Double

    public init(centre: GeographicCoordinate, radiusNM: Double) {
        self.centre = centre
        self.radiusNM = min(250, max(1, radiusNM.isFinite ? radiusNM : 250))
    }
}

public protocol OnlineAircraftProvider: Sendable {
    func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot
}

public struct OnlineHTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let retryAfter: Date?

    public init(data: Data, status: Int = 200, retryAfter: Date? = nil) {
        self.data = data
        self.status = status
        self.retryAfter = retryAfter
    }
}

public protocol OnlineHTTPTransport: Sendable {
    func get(_ url: URL) async throws -> OnlineHTTPResponse
}

public struct URLSessionOnlineTransport: OnlineHTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL) async throws -> OnlineHTTPResponse {
        var request = URLRequest(url: url)
        request.setValue("ADSB-Radar/0.1 (personal aircraft viewer)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OnlineProviderError.invalidResponse }
        let retryAfter = Self.retryDate(http.value(forHTTPHeaderField: "Retry-After"), now: .now)
        return OnlineHTTPResponse(data: data, status: http.statusCode, retryAfter: retryAfter)
    }

    static func retryDate(_ header: String?, now: Date) -> Date? {
        guard let header else { return nil }
        if let seconds = Double(header), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .gmt
        format.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return format.date(from: header)
    }
}

public enum OnlineProviderError: Error, LocalizedError, Sendable {
    case invalidResponse
    case http(Int, retryAfter: Date?)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "adsb.fi returned an unreadable response. Retrying automatically."
        case .http(let status, _): "adsb.fi unavailable (HTTP \(status)). Retrying automatically."
        }
    }
}

/// One allowance for the entire provider, including future identity lookups.
/// Queue selection happens after pacing, so position requests take precedence.
public actor OnlineRequestScheduler {
    public enum Priority: Int, Sendable { case identity, position }
    private struct Pending {
        let url: URL
        let priority: Priority
        let continuation: CheckedContinuation<OnlineHTTPResponse, any Error>
    }
    private let transport: any OnlineHTTPTransport
    private let clock = ContinuousClock()
    private var nextStart: ContinuousClock.Instant
    private var order: [UUID] = []
    private var pending: [UUID: Pending] = [:]
    private var worker: Task<Void, Never>?
    private var active: UUID?
    private var activeRequest: Task<OnlineHTTPResponse, any Error>?

    public init(transport: any OnlineHTTPTransport = URLSessionOnlineTransport()) {
        self.transport = transport
        nextStart = ContinuousClock().now
    }

    public func get(_ url: URL, priority: Priority = .position) async throws -> OnlineHTTPResponse {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = Pending(url: url, priority: priority, continuation: continuation)
                order.append(id)
                if worker == nil { worker = Task { await run() } }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        order.removeAll { $0 == id }
        pending.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
        if active == id { activeRequest?.cancel() }
    }

    private func run() async {
        while !order.isEmpty {
            try? await clock.sleep(until: nextStart)
            let candidates = order.compactMap { id in pending[id].map { (id, $0.priority) } }
            guard let id = candidates.max(by: { $0.1.rawValue < $1.1.rawValue })?.0,
                  let item = pending[id] else { continue }
            order.removeAll { $0 == id }
            active = id
            nextStart = clock.now.advanced(by: .seconds(1))
            let transport = transport
            let request = Task { try await transport.get(item.url) }
            activeRequest = request
            let result = await request.result
            if case .success(let response) = result, let retry = response.retryAfter {
                nextStart = max(nextStart, clock.now.advanced(by: .seconds(max(0, retry.timeIntervalSinceNow))))
            }
            pending.removeValue(forKey: id)?.continuation.resume(with: result)
            active = nil
            activeRequest = nil
        }
        worker = nil
    }
}

public struct ADSBFiProvider: OnlineAircraftProvider {
    private let scheduler: OnlineRequestScheduler
    private let baseURL: URL

    public init(scheduler: OnlineRequestScheduler = OnlineRequestScheduler(),
                baseURL: URL = URL(string: "https://opendata.adsb.fi/api")!) {
        self.scheduler = scheduler
        self.baseURL = baseURL
    }

    public func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot {
        let path = "v3/lat/\(search.centre.latitude)/lon/\(search.centre.longitude)/dist/\(search.radiusNM)"
        let response = try await scheduler.get(baseURL.appendingPathComponent(path))
        guard (200..<300).contains(response.status) else {
            throw OnlineProviderError.http(response.status, retryAfter: response.retryAfter)
        }
        return try Self.decode(response.data)
    }

    public static func decode(_ data: Data) throws -> ReceiverSnapshot {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = json["now"] as? NSNumber,
              CFGetTypeID(timestamp) != CFBooleanGetTypeID(), timestamp.doubleValue.isFinite,
              let aircraft = (json["ac"] ?? json["aircraft"]) as? [Any] else {
            throw OnlineProviderError.invalidResponse
        }
        if let message = json["msg"] as? String, !["No error", ""].contains(message) {
            throw OnlineProviderError.invalidResponse
        }
        // ADSBexchange-compatible timestamps are milliseconds; tolerate seconds too.
        json["now"] = timestamp.doubleValue > 100_000_000_000 ? timestamp.doubleValue / 1000 : timestamp.doubleValue
        json["aircraft"] = aircraft
        let snapshot = try ReceiverSnapshot.decode(JSONSerialization.data(withJSONObject: json))
        return ReceiverSnapshot(observations: snapshot.observations.map {
            AircraftObservation(address: $0.address, callsign: $0.callsign, position: $0.position,
                positionTime: $0.positionTime, altitude: $0.altitude, speedKnots: $0.speedKnots,
                directionDegrees: $0.directionDegrees, source: "adsb.fi")
        })
    }
}

/// Date-based policy is independently testable without waiting for real outages.
public struct OnlineRefreshPolicy: Sendable {
    public private(set) var nextAttempt = Date.distantPast
    private var failures = 0
    public init() {}
    public mutating func succeeded(at now: Date, interval: Double) {
        failures = 0
        nextAttempt = now.addingTimeInterval(max(1, interval))
    }
    public mutating func failed(at now: Date, interval: Double, retryAfter: Date? = nil) {
        failures = min(failures + 1, 8)
        nextAttempt = max(now.addingTimeInterval(max(interval, min(300, pow(2, Double(failures))))), retryAfter ?? now)
    }
    public mutating func requestUpdate() { nextAttempt = .distantPast }
}

public actor OnlineFeed: AircraftDataSource {
    private let provider: any OnlineAircraftProvider
    private var search: OnlineSearch?
    private var interval: Double
    private var policy = OnlineRefreshPolicy()
    private var status: ReceptionStatus = .stopped
    private var generation = 0

    public init(provider: any OnlineAircraftProvider = ADSBFiProvider(), interval: Double = 5, radiusNM: Double = 250) {
        self.provider = provider
        self.interval = max(1, interval)
        self.radiusNM = radiusNM
    }
    private var radiusNM: Double

    public func start(location: GeographicCoordinate?) async {
        generation += 1
        search = location.map { OnlineSearch(centre: $0, radiusNM: radiusNM) }
        policy = OnlineRefreshPolicy()
        status = search == nil ? .failed("Enter a Home location in Settings to start Online mode.") : .starting
    }

    public func poll() async -> ReceptionReading {
        guard let search, Date.now >= policy.nextAttempt else { return ReceptionReading(status: status) }
        let revision = generation
        do {
            let snapshot = try await provider.positions(in: search)
            try Task.checkCancellation()
            guard revision == generation else { return ReceptionReading(status: status) }
            policy.succeeded(at: .now, interval: interval)
            status = snapshot.observations.isEmpty ? .waiting : .receiving
            return ReceptionReading(status: status, snapshot: snapshot)
        } catch {
            guard revision == generation, !Task.isCancelled else { return ReceptionReading(status: status) }
            let retryAfter: Date?
            if case OnlineProviderError.http(_, let retry) = error { retryAfter = retry } else { retryAfter = nil }
            policy.failed(at: .now, interval: interval, retryAfter: retryAfter)
            status = .failed("Online: \(error.localizedDescription)")
            return ReceptionReading(status: status)
        }
    }

    public func stop() async {
        generation += 1
        search = nil
        status = .stopped
    }
}
