import CoreFoundation
import Foundation

public struct GeographicCoordinate: Equatable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum AircraftAltitude: Equatable, Sendable {
    case feet(Double)
    case ground
}

public struct AircraftObservation: Equatable, Sendable {
    public let address: String
    public let callsign: String?
    public let position: GeographicCoordinate?
    public let positionTime: Date?
    public let altitude: AircraftAltitude?
    public let speedKnots: Double?
    public let directionDegrees: Double?
    public let source: String

    public init(address: String, callsign: String? = nil, position: GeographicCoordinate? = nil,
                positionTime: Date? = nil, altitude: AircraftAltitude? = nil,
                speedKnots: Double? = nil, directionDegrees: Double? = nil,
                source: String = "LOCAL RTL-SDR") {
        self.address = address
        self.callsign = callsign
        self.position = position
        self.positionTime = positionTime
        self.altitude = altitude
        self.speedKnots = speedKnots
        self.directionDegrees = directionDegrees
        self.source = source
    }
}

public struct ReceiverSnapshot: Sendable {
    public let observations: [AircraftObservation]

    public init(observations: [AircraftObservation]) {
        self.observations = observations
    }

    public var heardWithoutPosition: Int {
        observations.filter { $0.position == nil }.count
    }

    public static func decode(_ data: Data) throws -> ReceiverSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let now = number(json["now"]),
              let aircraft = json["aircraft"] as? [Any] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Missing receiver snapshot timestamp or aircraft list."))
        }
        let observations = aircraft.compactMap { value -> AircraftObservation? in
            guard let entry = value as? [String: Any], let address = entry["hex"] as? String,
                  address.range(of: "^~?[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { return nil }
            let callsign = (entry["flight"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let coordinate: GeographicCoordinate?
            let positionTime: Date?
            if let lat = number(entry["lat"]), let lon = number(entry["lon"]),
               let age = number(entry["seen_pos"]), age >= 0,
               let valid = GeographicCoordinate(latitude: lat, longitude: lon) {
                coordinate = valid
                positionTime = Date(timeIntervalSince1970: now - age)
            } else {
                coordinate = nil
                positionTime = nil
            }
            let altitude: AircraftAltitude?
            if entry["alt_baro"] as? String == "ground" {
                altitude = .ground
            } else if let feet = number(entry["alt_baro"]) ?? number(entry["alt_geom"]) {
                altitude = .feet(feet)
            } else { altitude = nil }
            let speed = number(entry["gs"]).flatMap { $0 >= 0 ? $0 : nil }
            let track = number(entry["track"]).flatMap { (0...360).contains($0) ? $0.truncatingRemainder(dividingBy: 360) : nil }
            return AircraftObservation(
                address: address.lowercased(), callsign: callsign?.isEmpty == false ? callsign : nil,
                position: coordinate, positionTime: positionTime, altitude: altitude,
                speedKnots: speed, directionDegrees: track
            )
        }
        return ReceiverSnapshot(observations: observations)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
}
