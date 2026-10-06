import Foundation

public struct PositionSample: Equatable, Sendable {
    public let position: GeographicCoordinate
    public let time: Date
}

public struct PresentedContact: Equatable, Identifiable, Sendable {
    public let id: String
    public let observation: AircraftObservation
    public let positionAge: Double
    public let stale: Bool
    public let trail: [PositionSample]
}

public struct RadarSession: Sendable {
    private var observations: [String: [AircraftFeed: AircraftObservation]] = [:]
    private var sourceHistory: [String: [AircraftFeed: [PositionSample]]] = [:]
    private var history: [String: [PositionSample]] = [:]
    private var presented: [String: AircraftObservation] = [:]
    private var presentedFeeds: [String: AircraftFeed] = [:]
    private var categories: [String: [AircraftFeed: AircraftCategoryValue]] = [:]
    private var enabledFeeds: Set<AircraftFeed>
    private var lastAdvance: Date
    private let startedAt: Date

    public init(startedAt: Date, enabledFeeds: Set<AircraftFeed> = [.local]) {
        self.startedAt = startedAt
        self.lastAdvance = startedAt
        self.enabledFeeds = enabledFeeds
    }

    public mutating func setEnabledFeeds(_ feeds: Set<AircraftFeed>) {
        enabledFeeds = feeds
        for id in Array(observations.keys) {
            observations[id] = observations[id]?.filter { feeds.contains($0.key) }
            sourceHistory[id] = sourceHistory[id]?.filter { feeds.contains($0.key) }
            categories[id] = categories[id]?.filter { feeds.contains($0.key) }
            if observations[id]?.isEmpty != false { remove(id) }
        }
    }

    /// Received positions include contacts waiting for their first sweep crossing.
    public var receivedPositionedCount: Int { observations.count }

    /// Category reports retain their own successful timestamp, scoped to the displayed feed.
    public func reportedCategory(for contactID: String) -> AircraftCategoryValue? {
        guard let feed = presentedFeeds[contactID] else { return nil }
        return categories[contactID]?[feed]
    }

    public mutating func ingest(_ snapshot: ReceiverSnapshot, from feed: AircraftFeed = .local) {
        guard enabledFeeds.contains(feed) else { return }
        for incoming in snapshot.observations {
            // Non-ICAO addresses are source-scoped because equal values need not identify the same aircraft.
            let id = incoming.address.hasPrefix("~") ? "\(feed.rawValue):\(incoming.address)" : incoming.address
            let previous = observations[id]?[feed]
            if incoming.position == nil, previous == nil { continue }
            let report = snapshot.identities.first { $0.address == incoming.address && $0.category != nil }
            if let category = report?.category ?? incoming.category {
                let updatedAt = report?.updatedAt ?? incoming.positionTime ?? .now
                if categories[id]?[feed].map({ $0.updatedAt <= updatedAt }) ?? true {
                    categories[id, default: [:]][feed] = AircraftCategoryValue(value: category,
                        provider: report?.provider ?? incoming.source, updatedAt: updatedAt)
                }
            }
            if let incomingTime = incoming.positionTime, let oldTime = previous?.positionTime, incomingTime < oldTime { continue }
            if incoming.position == nil, let previous {
                observations[id, default: [:]][feed] = AircraftObservation(
                    address: incoming.address, callsign: incoming.callsign ?? previous.callsign,
                    position: previous.position, positionTime: previous.positionTime,
                    altitude: incoming.altitude ?? previous.altitude,
                    speedKnots: incoming.speedKnots ?? previous.speedKnots,
                    directionDegrees: incoming.directionDegrees ?? previous.directionDegrees,
                    category: incoming.category ?? previous.category, source: previous.source
                )
            } else { observations[id, default: [:]][feed] = incoming }
            if let position = incoming.position, let time = incoming.positionTime {
                let last = sourceHistory[id]?[feed]?.last
                if last?.time != time || last?.position != position {
                    sourceHistory[id, default: [:]][feed, default: []].append(PositionSample(position: position, time: time))
                }
            }
        }
    }

    public mutating func advance(to date: Date, settings: RadarSettings) -> [PresentedContact] {
        let settings = settings.validated()
        var result: [PresentedContact] = []
        let elapsed = max(0, date.timeIntervalSince(lastAdvance))
        let from = SweepTiming.angle(at: lastAdvance, startedAt: startedAt, period: settings.sweepSeconds)
        defer { lastAdvance = date }
        for id in Array(observations.keys) {
            guard let candidates = observations[id], let (feed, observation) = preferred(candidates, at: date, staleAfter: settings.staleSeconds),
                  let position = observation.position, let positionTime = observation.positionTime else { continue }
            let age = max(0, date.timeIntervalSince(positionTime))
            if age >= settings.removalSeconds { remove(id); continue }
            let cutoff = date.addingTimeInterval(-settings.trailSeconds)
            sourceHistory[id] = sourceHistory[id]?.mapValues { $0.filter { $0.time >= cutoff } }
            history[id] = (history[id] ?? []).filter { $0.time >= cutoff }
            // Only the active source contributes new trail points, in chronological order.
            for sample in sourceHistory[id]?[feed] ?? [] {
                if let last = history[id]?.last, sample.time <= last.time { continue }
                history[id, default: []].append(sample)
            }
            let sourceChanged = presentedFeeds[id] != nil && presentedFeeds[id] != feed
            if settings.mode == .immediate || sourceChanged {
                presented[id] = observation
                presentedFeeds[id] = feed
            } else if let origin = settings.receiver {
                let bearing = ReceiverProjection(origin: origin).project(position).bearing
                if SweepTiming.crossed(bearing: bearing, from: from, elapsed: elapsed, period: settings.sweepSeconds) {
                    presented[id] = observation
                    presentedFeeds[id] = feed
                }
            }
            guard let displayed = presented[id], let displayedTime = displayed.positionTime else { continue }
            let visibleTrail = (history[id] ?? []).filter { $0.time <= displayedTime }
            result.append(PresentedContact(id: id, observation: displayed, positionAge: age,
                stale: age >= settings.staleSeconds, trail: visibleTrail))
        }
        return result.sorted { $0.id < $1.id }
    }

    private func preferred(_ candidates: [AircraftFeed: AircraftObservation], at date: Date, staleAfter: Double) -> (AircraftFeed, AircraftObservation)? {
        if let local = candidates[.local], local.position != nil, let time = local.positionTime,
           date.timeIntervalSince(time) < staleAfter { return (.local, local) }
        var latest: (AircraftFeed, AircraftObservation)?
        for feed in AircraftFeed.allCases {
            guard let candidate = candidates[feed], candidate.position != nil, let time = candidate.positionTime else { continue }
            if let previousTime = latest?.1.positionTime, time <= previousTime { continue }
            latest = (feed, candidate)
        }
        return latest
    }

    private mutating func remove(_ id: String) {
        observations.removeValue(forKey: id)
        sourceHistory.removeValue(forKey: id)
        history.removeValue(forKey: id)
        presented.removeValue(forKey: id)
        presentedFeeds.removeValue(forKey: id)
        categories.removeValue(forKey: id)
    }
}

public enum SweepTiming {
    public static func angle(at date: Date, startedAt: Date, period: Double) -> Double {
        let turns = max(0, date.timeIntervalSince(startedAt)) / max(0.5, period)
        return turns.truncatingRemainder(dividingBy: 1) * 2 * .pi
    }

    public static func crossed(bearing: Double, from: Double, elapsed: Double, period: Double) -> Bool {
        if elapsed >= period { return true }
        let rotation = 2 * Double.pi
        let offset = (bearing - from + rotation).truncatingRemainder(dividingBy: rotation)
        return offset > 0.000001 && offset <= elapsed / max(0.5, period) * rotation + 0.000001
    }
}
