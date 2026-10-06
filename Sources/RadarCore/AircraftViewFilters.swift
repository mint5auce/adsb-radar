import Foundation

/// Presentation criteria never alter the received contact catalogue.
public struct AircraftViewFilters: Equatable, Codable, Sendable {
    public var homeDistanceNM: Double?
    public var minimumAltitudeFeet: Double?
    public var maximumAltitudeFeet: Double?
    public var includeUnknownAltitude = true
    public var hideGround = false

    private enum CodingKeys: String, CodingKey { case homeDistanceNM, minimumAltitudeFeet, maximumAltitudeFeet, includeUnknownAltitude, hideGround }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        homeDistanceNM = try values.decodeIfPresent(Double.self, forKey: .homeDistanceNM)
        minimumAltitudeFeet = try values.decodeIfPresent(Double.self, forKey: .minimumAltitudeFeet)
        maximumAltitudeFeet = try values.decodeIfPresent(Double.self, forKey: .maximumAltitudeFeet)
        includeUnknownAltitude = try values.decodeIfPresent(Bool.self, forKey: .includeUnknownAltitude) ?? true
        hideGround = try values.decodeIfPresent(Bool.self, forKey: .hideGround) ?? false
    }
    public init(homeDistanceNM: Double? = nil) { self.homeDistanceNM = homeDistanceNM }
    public var hasAltitudeRange: Bool { minimumAltitudeFeet != nil || maximumAltitudeFeet != nil }
    public var isActive: Bool { homeDistanceNM != nil || hasAltitudeRange || hideGround || !includeUnknownAltitude }
    public var validationMessage: String? {
        if let homeDistanceNM, !homeDistanceNM.isFinite || homeDistanceNM <= 0 { return "Enter a positive Home distance." }
        if [minimumAltitudeFeet, maximumAltitudeFeet].compactMap({ $0 }).contains(where: { !$0.isFinite }) { return "Enter a valid reported altitude." }
        if let minimumAltitudeFeet, let maximumAltitudeFeet, minimumAltitudeFeet > maximumAltitudeFeet { return "Minimum altitude must not exceed maximum." }
        return nil
    }
    public func matches(_ observation: AircraftObservation, home: GeographicCoordinate?) -> Bool {
        if let limit = homeDistanceNM, let home, let position = observation.position {
            let point = ReceiverProjection(origin: home).project(position)
            if hypot(point.east, point.north) > limit { return false }
        }
        switch observation.altitude {
        case .ground: if hideGround || hasAltitudeRange { return false }
        case .feet(let altitude):
            if let minimumAltitudeFeet, altitude < minimumAltitudeFeet { return false }
            if let maximumAltitudeFeet, altitude > maximumAltitudeFeet { return false }
        case nil: if !includeUnknownAltitude { return false }
        }
        return true
    }
}
