import Foundation

public struct RadarPoint: Equatable, Sendable {
    public var east: Double
    public var north: Double
    public init(east: Double = 0, north: Double = 0) { self.east = east; self.north = north }
    public var bearing: Double { atan2(east, north) < 0 ? atan2(east, north) + 2 * .pi : atan2(east, north) }
}

public struct ReceiverProjection: Sendable {
    public let origin: GeographicCoordinate
    public init(origin: GeographicCoordinate) { self.origin = origin }
    public func project(_ coordinate: GeographicCoordinate) -> RadarPoint {
        let latitude = coordinate.latitude * .pi / 180
        let originLatitude = origin.latitude * .pi / 180
        let deltaLongitude = (coordinate.longitude - origin.longitude) * .pi / 180
        let deltaLatitude = latitude - originLatitude
        let haversine = pow(sin(deltaLatitude / 2), 2) + cos(originLatitude) * cos(latitude) * pow(sin(deltaLongitude / 2), 2)
        let a = min(1, max(0, haversine))
        let distance = 3440.065 * 2 * atan2(sqrt(a), sqrt(1 - a))
        let bearing = atan2(sin(deltaLongitude) * cos(latitude), cos(originLatitude) * sin(latitude) - sin(originLatitude) * cos(latitude) * cos(deltaLongitude))
        return RadarPoint(east: distance * sin(bearing), north: distance * cos(bearing))
    }
}

public struct RadarCamera: Equatable, Sendable {
    public var offset = RadarPoint()
    public var radiusNM: Double
    public init(radiusNM: Double = 100) { self.radiusNM = radiusNM }
    public func screen(_ point: RadarPoint, width: Double, height: Double) -> (x: Double, y: Double) {
        let scale = pixelsPerNM(width: width, height: height)
        return (width / 2 + (point.east - offset.east) * scale,
                height / 2 - (point.north - offset.north) * scale)
    }
    public func pixelsPerNM(width: Double, height: Double) -> Double {
        max(1, min(width, height)) / (2 * max(1, radiusNM))
    }

    public func panned(dx: Double, dy: Double, width: Double, height: Double) -> RadarCamera {
        var camera = self
        let scale = pixelsPerNM(width: width, height: height)
        camera.offset.east -= dx / scale
        camera.offset.north += dy / scale
        return camera
    }

    public func zoomed(by factor: Double) -> RadarCamera {
        guard factor.isFinite, factor > 0 else { return self }
        var camera = self
        camera.radiusNM = min(3000, max(5, radiusNM / factor))
        return camera
    }
}
