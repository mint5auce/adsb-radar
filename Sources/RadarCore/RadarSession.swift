import Foundation

public struct PositionSample: Equatable, Sendable {
    public let position: GeographicCoordinate
    public let time: Date
}

public struct PresentedContact: Equatable, Identifiable, Sendable {
    public var id: String { observation.address }
    public let observation: AircraftObservation
    public let positionAge: Double
    public let stale: Bool
    public let trail: [PositionSample]
}

public struct RadarSession: Sendable {
    private var observations: [String: AircraftObservation] = [:]
    private var history: [String: [PositionSample]] = [:]
    private var presented: [String: AircraftObservation] = [:]
    private var lastAdvance: Date
    private let startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
        self.lastAdvance = startedAt
    }

    public mutating func ingest(_ snapshot: ReceiverSnapshot) {
        for incoming in snapshot.observations {
            let previous = observations[incoming.address]
            if incoming.position == nil, previous == nil { continue }
            if let incomingTime = incoming.positionTime, let oldTime = previous?.positionTime, incomingTime < oldTime { continue }
            if incoming.position == nil, let previous {
                observations[incoming.address] = AircraftObservation(
                    address: incoming.address, callsign: incoming.callsign ?? previous.callsign,
                    position: previous.position, positionTime: previous.positionTime,
                    altitude: incoming.altitude ?? previous.altitude,
                    speedKnots: incoming.speedKnots ?? previous.speedKnots,
                    directionDegrees: incoming.directionDegrees ?? previous.directionDegrees,
                    source: incoming.source
                )
            } else { observations[incoming.address] = incoming }
            if let position = incoming.position, let time = incoming.positionTime {
                let last = history[incoming.address]?.last
                if last?.time != time || last?.position != position {
                    history[incoming.address, default: []].append(PositionSample(position: position, time: time))
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
        for (address, observation) in observations {
            guard observation.position != nil, let positionTime = observation.positionTime else { continue }
            let age = max(0, date.timeIntervalSince(positionTime))
            if age >= settings.removalSeconds {
                observations.removeValue(forKey: address)
                history.removeValue(forKey: address)
                presented.removeValue(forKey: address)
                continue
            }
            let cutoff = date.addingTimeInterval(-settings.trailSeconds)
            history[address] = (history[address] ?? []).filter { $0.time >= cutoff }
            if settings.mode == .immediate {
                presented[address] = observation
            } else if let origin = settings.receiver, let position = observation.position {
                let bearing = ReceiverProjection(origin: origin).project(position).bearing
                if SweepTiming.crossed(bearing: bearing, from: from, elapsed: elapsed, period: settings.sweepSeconds) {
                    presented[address] = observation
                }
            }
            guard let displayed = presented[address], let displayedTime = displayed.positionTime else { continue }
            let visibleTrail = (history[address] ?? []).filter { $0.time <= displayedTime }
            result.append(PresentedContact(observation: displayed, positionAge: age, stale: age >= settings.staleSeconds, trail: visibleTrail))
        }
        return result.sorted { $0.id < $1.id }
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
