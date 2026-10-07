import Foundation
import Testing
@testable import RadarCore

struct GeometryTests {
    @Test(arguments: [1.1, 1 / 1.1, 1000, 0.001], [CGSize(width: 800, height: 600), CGSize(width: 600, height: 800)])
    func zoomKeepsOffCentreGeographyAtTheSamePixel(factor: Double, size: CGSize) {
        var camera = RadarCamera()
        camera.offset = RadarPoint(east: 35, north: -20)
        let point = RadarPoint(east: 75, north: 25)
        let anchor = camera.screen(point, width: size.width, height: size.height)
        let zoomed = camera.zoomed(by: factor, atX: anchor.x, y: anchor.y, width: size.width, height: size.height)
        let screen = zoomed.screen(point, width: size.width, height: size.height)
        #expect(abs(screen.x - anchor.x) < 0.000001)
        #expect(abs(screen.y - anchor.y) < 0.000001)
        #expect((5...3000).contains(zoomed.radiusNM))
    }

    @Test(arguments: [5.0, 3000.0])
    func repeatedZoomAtALimitDoesNotDrift(radius: Double) {
        var camera = RadarCamera(radiusNM: radius)
        camera.offset = RadarPoint(east: -40, north: 60)
        let factor = radius == 5 ? 1.1 : 1 / 1.1
        #expect(camera.zoomed(by: factor, atX: 160, y: 450, width: 800, height: 600) == camera)
    }

    @Test func centredZoomAndInvalidInputsPreserveTheCameraOffset() {
        var camera = RadarCamera()
        camera.offset = RadarPoint(east: 12, north: 30)
        #expect(camera.zoomed(by: 2, atX: 400, y: 300, width: 800, height: 600) == camera.zoomed(by: 2))
        for factor in [Double.nan, .infinity, 0, -1] {
            #expect(camera.zoomed(by: factor, atX: 150, y: 450, width: 800, height: 600) == camera)
        }
        #expect(camera.zoomed(by: 2, atX: .nan, y: 300, width: 800, height: 600) == camera)
        #expect(camera.zoomed(by: 2, atX: 150, y: 300, width: 0, height: 600) == camera)
    }

    @Test func directionVectorsFollowProjectedGeographyAwayFromTheReceiver() throws {
        let origin = try #require(GeographicCoordinate(latitude: 50, longitude: 0))
        let position = try #require(GeographicCoordinate(latitude: 60, longitude: 40))
        let northward = try #require(GeographicCoordinate(latitude: 60.01, longitude: 40))
        let projection = ReceiverProjection(origin: origin)
        let a = projection.project(position)
        let b = projection.project(northward)
        let direction = projection.direction(at: position, headingDegrees: 0)
        let length = hypot(b.east - a.east, b.north - a.north)
        #expect(abs(direction.east - (b.east - a.east) / length) < 0.001)
        #expect(abs(direction.north - (b.north - a.north) / length) < 0.001)
        #expect(abs(hypot(direction.east, direction.north) - 1) < 0.001)
    }

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
