import Foundation

public enum SyntheticScenario: String, Codable, CaseIterable, Sendable { case test, demo }

/// Repeatable traffic, with time injected only at the clock boundary.
public actor SyntheticSource: AircraftDataSource {
    public static let exampleLocation = GeographicCoordinate(latitude: 51.5, longitude: -2.5)!
    private let scenario: SyntheticScenario
    private let demoCount: Int
    private let timing: RadarSettings
    private let now: @Sendable () -> Date
    private var startedAt: Date?
    private var origin = exampleLocation

    public init(scenario: SyntheticScenario = .test, demoCount: Int = 100, timing: RadarSettings = RadarSettings(),
                now: @escaping @Sendable () -> Date = { .now }) {
        self.scenario = scenario
        self.demoCount = min(250, max(25, demoCount))
        self.timing = timing.validated()
        self.now = now
    }

    public func start(location: GeographicCoordinate?) async {
        origin = location ?? Self.exampleLocation
        startedAt = now()
    }

    public func stop() async { startedAt = nil }

    public func poll() async -> ReceptionReading {
        guard let startedAt else { return ReceptionReading(status: .stopped) }
        let date = now()
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let count = scenario == .demo ? demoCount : 12
        let observations = (0..<count).map { index in
            // Keep movement visible for two sweeps, then continue messages with a frozen position.
            // Leave at least two sweeps after removal before recovery, then repeat the cycle.
            let movingSeconds = max(8, timing.sweepSeconds * 2)
            let cycle = movingSeconds + timing.removalSeconds + max(5, timing.sweepSeconds * 2)
            let phase = elapsed.truncatingRemainder(dividingBy: cycle)
            let frozen = scenario == .test && index == 0 && phase > movingSeconds
            let positionElapsed = frozen ? elapsed - phase + movingSeconds : elapsed
            let positionDate = startedAt.addingTimeInterval(positionElapsed)
            let position = route(index: index, count: count, elapsed: positionElapsed)
            let next = route(index: index, count: count, elapsed: positionElapsed + 1)
            let unknown = scenario == .test && index == 10
            let unpositioned = scenario == .test && index == 11
            return AircraftObservation(address: String(format: "f%05x", index + 1),
                callsign: unknown ? nil : String(format: "%@%03d", scenario == .demo ? "DEMO" : "TEST", index + 1),
                position: unpositioned ? nil : position, positionTime: unpositioned ? nil : positionDate,
                altitude: unknown ? nil : .feet(Double(10000 + (index * 1700) % 29000)),
                speedKnots: unknown ? nil : speed(index: index), directionDegrees: unknown ? nil : heading(from: position, to: next),
                source: scenario == .demo ? "SYNTHETIC DEMO" : "SYNTHETIC TEST")
        }
        return ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: observations))
    }

    private func speed(index: Int) -> Double { Double(260 + (index * 37) % 220) }

    private func route(index: Int, count: Int, elapsed: Double) -> GeographicCoordinate {
        // Equal-area radial spacing and a golden angle spread the initial picture across the map.
        let radius = 12 + 72 * sqrt((Double(index) + 0.5) / Double(count))
        let rotation = index.isMultiple(of: 2) ? 1.0 : -1.0
        let bearing = Double(index) * 2.3999632297 + rotation * elapsed * speed(index: index) / (3600 * radius)
        let arc = radius / 3440.065
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180
        let destinationLatitude = asin(min(1, max(-1, sin(latitude) * cos(arc) + cos(latitude) * sin(arc) * cos(bearing))))
        let destinationLongitude = longitude + atan2(sin(bearing) * sin(arc) * cos(latitude), cos(arc) - sin(latitude) * sin(destinationLatitude))
        let normalizedLongitude = (destinationLongitude * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeographicCoordinate(latitude: destinationLatitude * 180 / .pi, longitude: normalizedLongitude)!
    }

    private func heading(from a: GeographicCoordinate, to b: GeographicCoordinate) -> Double {
        let latitudeA = a.latitude * .pi / 180
        let latitudeB = b.latitude * .pi / 180
        let delta = (b.longitude - a.longitude) * .pi / 180
        let bearing = atan2(sin(delta) * cos(latitudeB),
            cos(latitudeA) * sin(latitudeB) - sin(latitudeA) * cos(latitudeB) * cos(delta))
        return (bearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
