import Foundation

/// Presentation criteria never alter the received contact catalogue.
public struct AircraftViewFilters: Equatable, Codable, Sendable {
    public var homeDistanceNM: Double?
    public init(homeDistanceNM: Double? = nil) { self.homeDistanceNM = homeDistanceNM }
    public var isActive: Bool { homeDistanceNM != nil }
    public var validationMessage: String? {
        if let homeDistanceNM, !homeDistanceNM.isFinite || homeDistanceNM <= 0 { return "Enter a positive Home distance." }
        return nil
    }
    public func matches(_ observation: AircraftObservation, home: GeographicCoordinate?) -> Bool {
        if let limit = homeDistanceNM, let home, let position = observation.position {
            let point = ReceiverProjection(origin: home).project(position)
            if hypot(point.east, point.north) > limit { return false }
        }
        return true
    }
}
