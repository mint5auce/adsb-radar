import Foundation
import Testing
@testable import RadarCore

struct SessionTests {
    let epoch = Date(timeIntervalSince1970: 1000)

    func observation(at seconds: Double = 0, latitude: Double = 1, longitude: Double = 0) -> AircraftObservation {
        AircraftObservation(address: "abc123", position: GeographicCoordinate(latitude: latitude, longitude: longitude), positionTime: epoch.addingTimeInterval(seconds))
    }

    @Test func contactAgesWhileReceptionIsSilentAndRecoversWithAFreshPosition() throws {
        var settings = RadarSettings()
        settings.mode = .immediate
        var session = RadarSession(startedAt: epoch)
        session.ingest(ReceiverSnapshot(observations: [observation()]))
        #expect(session.advance(to: epoch.addingTimeInterval(14.9), settings: settings).first?.stale == false)
        #expect(session.advance(to: epoch.addingTimeInterval(15), settings: settings).first?.stale == true)
        session.ingest(ReceiverSnapshot(observations: [AircraftObservation(address: "abc123", callsign: "NEW")]))
        #expect(session.advance(to: epoch.addingTimeInterval(59), settings: settings).first?.positionAge == 59)
        #expect(session.advance(to: epoch.addingTimeInterval(60), settings: settings).isEmpty)
        session.ingest(ReceiverSnapshot(observations: [observation(at: 61)]))
        #expect(session.advance(to: epoch.addingTimeInterval(61), settings: settings).first?.stale == false)
    }

    @Test func trailsRetainOnlyDistinctObservationsInsideConfiguredDuration() throws {
        var settings = RadarSettings()
        settings.mode = .immediate
        settings.trailSeconds = 10
        var session = RadarSession(startedAt: epoch)
        session.ingest(ReceiverSnapshot(observations: [observation()]))
        session.ingest(ReceiverSnapshot(observations: [observation()]))
        session.ingest(ReceiverSnapshot(observations: [observation(at: 8, latitude: 1.1)]))
        #expect(session.advance(to: epoch.addingTimeInterval(8), settings: settings).first?.trail.count == 2)
        let trail = try #require(session.advance(to: epoch.addingTimeInterval(11), settings: settings).first?.trail)
        #expect(trail.count == 1)
        #expect(trail.first?.time == epoch.addingTimeInterval(8))
    }

    @Test func sweepLatchesContactsOnBearingCrossingsWithoutChangingSourceAge() throws {
        var settings = RadarSettings()
        settings.receiver = GeographicCoordinate(latitude: 0, longitude: 0)
        var session = RadarSession(startedAt: epoch)
        session.ingest(ReceiverSnapshot(observations: [observation(latitude: 0, longitude: 1)]))
        #expect(session.advance(to: epoch.addingTimeInterval(0.5), settings: settings).isEmpty)
        #expect(session.advance(to: epoch.addingTimeInterval(1), settings: settings).first?.observation.positionTime == epoch)
        session.ingest(ReceiverSnapshot(observations: [observation(at: 1.1, latitude: 0, longitude: 1.1)]))
        #expect(session.advance(to: epoch.addingTimeInterval(4.9), settings: settings).first?.observation.positionTime == epoch)
        let refreshed = try #require(session.advance(to: epoch.addingTimeInterval(5), settings: settings).first)
        #expect(refreshed.observation.positionTime == epoch.addingTimeInterval(1.1))
        #expect(abs(refreshed.positionAge - 3.9) < 0.001)
        settings.mode = .immediate
        session.ingest(ReceiverSnapshot(observations: [observation(at: 5.1, latitude: 0, longitude: 1.2)]))
        #expect(session.advance(to: epoch.addingTimeInterval(5.1), settings: settings).first?.observation.positionTime == epoch.addingTimeInterval(5.1))
        #expect(session.advance(to: epoch.addingTimeInterval(20.1), settings: settings).first?.stale == true)
    }
}
