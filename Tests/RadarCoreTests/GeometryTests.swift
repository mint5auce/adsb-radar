import Foundation
import Testing
@testable import RadarCore

struct GeometryTests {
    @Test func projectsCompassDirectionsAndKeepsReceiverAnchoredWhilePanning() throws {
        let origin = try #require(GeographicCoordinate(latitude: 0, longitude: 0))
        let east = try #require(GeographicCoordinate(latitude: 0, longitude: 1))
        let north = try #require(GeographicCoordinate(latitude: 1, longitude: 0))
        let projection = ReceiverProjection(origin: origin)
        #expect(abs(projection.project(east).east - 60.04) < 0.01)
        #expect(abs(projection.project(north).north - 60.04) < 0.01)
        #expect(abs(projection.project(east).bearing - .pi / 2) < 0.001)
        let camera = RadarCamera().panned(dx: 60, dy: -30, width: 800, height: 600)
        let receiver = camera.screen(projection.project(origin), width: 800, height: 600)
        #expect(abs(receiver.x - 460) < 0.001)
        #expect(abs(receiver.y - 270) < 0.001)
    }

    @Test func aviationUnitsHaveKnownConversionsAndMissingValuesRemainUnknown() {
        var settings = RadarSettings()
        settings.altitudeUnit = .metres
        settings.speedUnit = .kilometresPerHour
        settings.distanceUnit = .kilometres
        #expect(settings.altitude(.feet(10000)) == "3048 M")
        #expect(settings.speed(100) == "185 KM/H")
        #expect(abs(settings.distanceValue(100) - 185.2) < 0.000001)
        #expect(settings.altitude(nil) == "UNKNOWN")
        #expect(settings.altitude(.ground) == "GROUND")
    }
}
