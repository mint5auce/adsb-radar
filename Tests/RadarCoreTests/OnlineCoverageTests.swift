import Foundation
import Testing
import RadarCore

struct OnlineCoverageTests {
    @Test func normalViewportFitsACircleAndWideViewsShowConfiguredLimit() throws {
        let origin = SyntheticSource.exampleLocation
        let camera = RadarCamera(radiusNM: 50)
        let coverage = OnlineCoverage(origin: origin, camera: camera, width: 800, height: 600, limitNM: 250)
        #expect(coverage.search.centre == origin && !coverage.limited)
        #expect(abs(coverage.search.radiusNM - 83.333333) < 0.001)
        let limited = OnlineCoverage(origin: origin, camera: camera, width: 800, height: 600, limitNM: 30)
        #expect(limited.limited && limited.search.radiusNM == 30)
        let projection = ReceiverProjection(origin: origin)
        for point in limited.boundary(relativeTo: origin) {
            #expect(abs(hypot(point.east, point.north) - 30) < 0.001)
        }
        for point in [RadarPoint(east: -66.666, north: 50), RadarPoint(east: 66.666, north: -50)] {
            let coordinate = try #require(projection.coordinate(at: point))
            let relative = ReceiverProjection(origin: coverage.search.centre).project(coordinate)
            #expect(hypot(relative.east, relative.north) <= coverage.search.radiusNM)
        }
    }

    @Test func panMovesSearchButKeepsHomeProjectionAndWrapsAtTheDateLine() throws {
        let home = try #require(GeographicCoordinate(latitude: 75, longitude: 179))
        var camera = RadarCamera(radiusNM: 50)
        camera.offset = RadarPoint(east: 200, north: 10)
        let coverage = OnlineCoverage(origin: home, camera: camera, width: 1200, height: 700, limitNM: 250)
        #expect(coverage.search.centre.longitude < 0)
        let roundTrip = ReceiverProjection(origin: home).project(coverage.search.centre)
        #expect(abs(roundTrip.east - 200) < 0.001 && abs(roundTrip.north - 10) < 0.001)
        #expect(home.longitude == 179)
        camera.radiusNM = 3000
        camera.offset = RadarPoint(east: 50000, north: -30000)
        let extreme = OnlineCoverage(origin: home, camera: camera, width: 800, height: 560, limitNM: 90)
        #expect(extreme.limited && extreme.search.radiusNM == 90)
        #expect((-90...90).contains(extreme.search.centre.latitude))
        #expect((-180...180).contains(extreme.search.centre.longitude))
        #expect(extreme.boundary(relativeTo: home).count == 121)
    }

    @Test func leavingSearchDoesNotEraseSelectedContactHistory() throws {
        let epoch = Date(timeIntervalSince1970: 1000)
        var settings = RadarSettings()
        settings.mode = .immediate
        var session = RadarSession(startedAt: epoch)
        session.ingest(ReceiverSnapshot(observations: [
            AircraftObservation(address: "abc123", position: SyntheticSource.exampleLocation, positionTime: epoch, source: "adsb.fi")
        ]))
        #expect(session.advance(to: epoch.addingTimeInterval(14), settings: settings).first?.trail.count == 1)
        session.ingest(ReceiverSnapshot(observations: []))
        #expect(session.advance(to: epoch.addingTimeInterval(15), settings: settings).first?.stale == true)
        #expect(session.advance(to: epoch.addingTimeInterval(60), settings: settings).isEmpty)
    }
}
