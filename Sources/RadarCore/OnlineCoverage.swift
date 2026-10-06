import Foundation

public struct OnlineCoverage: Equatable, Sendable {
    public let search: OnlineSearch
    public let limited: Bool

    public init(origin: GeographicCoordinate, camera: RadarCamera, width: Double, height: Double, limitNM: Double) {
        let width = width.isFinite ? max(1, width) : 800
        let height = height.isFinite ? max(1, height) : 600
        let scale = camera.pixelsPerNM(width: width, height: height)
        let radius = hypot(width, height) / (2 * scale)
        let centre = ReceiverProjection(origin: origin).coordinate(at: camera.offset) ?? origin
        search = OnlineSearch(centre: centre, radiusNM: min(radius, limitNM))
        limited = radius > search.radiusNM
    }

    public func boundary(relativeTo origin: GeographicCoordinate) -> [RadarPoint] {
        let projection = ReceiverProjection(origin: origin)
        let circle = ReceiverProjection(origin: search.centre)
        return (0...120).compactMap { index in
            let bearing = Double(index) * 2 * .pi / 120
            return circle.coordinate(at: RadarPoint(east: sin(bearing) * search.radiusNM, north: cos(bearing) * search.radiusNM))
                .map(projection.project)
        }
    }
}
