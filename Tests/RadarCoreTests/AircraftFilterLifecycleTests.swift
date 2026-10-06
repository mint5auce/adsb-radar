import Foundation
import Testing
import RadarCore

struct AircraftFilterLifecycleTests {
    @Test func distanceBoundaryIncludesExactlyTheDisplayedDistanceWithoutABuffer() throws {
        let home = try #require(GeographicCoordinate(latitude: 0, longitude: 0))
        let position = try #require(GeographicCoordinate(latitude: 1, longitude: 0))
        let observation = AircraftObservation(address: "abc123", position: position)
        // Projection has separate geometry tests; this checks the filter's comparison at its exact distance.
        let point = ReceiverProjection(origin: home).project(position)
        let distance = hypot(point.east, point.north)
        #expect(AircraftViewFilters(homeDistanceNM: distance).matches(observation, home: home))
        #expect(!AircraftViewFilters(homeDistanceNM: distance.nextDown).matches(observation, home: home))
        #expect(AircraftViewFilters(homeDistanceNM: distance.nextUp).matches(observation, home: home))
        #expect(AircraftViewFilters(homeDistanceNM: 1).matches(observation, home: nil))
    }

    @Test func hiddenContactsMoveRetainHistoryAgeAndExpireWithoutFresheningOnClear() throws {
        let epoch = Date(timeIntervalSince1970: 1000)
        var settings = RadarSettings()
        settings.receiver = GeographicCoordinate(latitude: 0, longitude: 0); settings.mode = .immediate
        settings.aircraftFilters.homeDistanceNM = 50
        var session = RadarSession(startedAt: epoch)
        let first = AircraftObservation(address: "abc123", position: GeographicCoordinate(latitude: 1, longitude: 0), positionTime: epoch)
        session.ingest(ReceiverSnapshot(observations: [first]))
        let initial = try #require(session.advance(to: epoch, settings: settings).first)
        #expect(!settings.aircraftFilters.matches(initial.observation, home: settings.receiver))
        let second = AircraftObservation(address: "abc123", position: GeographicCoordinate(latitude: 1.1, longitude: 0), positionTime: epoch.addingTimeInterval(8))
        session.ingest(ReceiverSnapshot(observations: [second]))
        let hidden = try #require(session.advance(to: epoch.addingTimeInterval(8), settings: settings).first)
        #expect(!settings.aircraftFilters.matches(hidden.observation, home: settings.receiver))
        #expect(hidden.observation == second && hidden.trail.count == 2)
        settings.aircraftFilters = AircraftViewFilters()
        #expect(session.advance(to: epoch.addingTimeInterval(8), settings: settings).first == hidden)
        settings.aircraftFilters.homeDistanceNM = 50
        #expect(session.advance(to: epoch.addingTimeInterval(23), settings: settings).first?.stale == true)
        #expect(session.advance(to: epoch.addingTimeInterval(68), settings: settings).isEmpty)
        #expect(session.receivedPositionedCount == 0)
    }

    @Test func receivedTotalsIncludePositionsAwaitingTheFirstSweep() {
        let epoch = Date(timeIntervalSince1970: 1000)
        var settings = RadarSettings()
        settings.receiver = GeographicCoordinate(latitude: 0, longitude: 0)
        var session = RadarSession(startedAt: epoch)
        session.ingest(ReceiverSnapshot(observations: [AircraftObservation(address: "abc123",
            position: GeographicCoordinate(latitude: 0, longitude: 1), positionTime: epoch)]))
        #expect(session.advance(to: epoch.addingTimeInterval(0.5), settings: settings).isEmpty)
        #expect(session.receivedPositionedCount == 1)
        #expect(session.advance(to: epoch.addingTimeInterval(1), settings: settings).count == 1)
        #expect(session.receivedPositionedCount == 1)
    }
}
