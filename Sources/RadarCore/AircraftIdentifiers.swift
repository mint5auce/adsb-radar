import Foundation

public enum AircraftIdentifierPreference: String, Codable, CaseIterable, Sendable {
    case registration, callsign

    public var title: String {
        switch self {
        case .registration: "Registration"
        case .callsign: "Callsign"
        }
    }
}

/// The same primary identifier and remaining details for every aircraft display.
public struct AircraftIdentifiers: Equatable, Sendable {
    public let registration: String?
    public let callsign: String?
    public let primary: String
    public let secondary: [String]

    public init(observation: AircraftObservation, identity: AircraftIdentity?, preferred: AircraftIdentifierPreference) {
        func cleaned(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        registration = cleaned(identity?.registration?.value)
        callsign = cleaned(observation.callsign)
        let address = observation.address.uppercased()
        let ordered = (preferred == .registration ? [registration, callsign] : [callsign, registration]).compactMap { $0 } + [address]
        primary = ordered[0]
        var seen = Set([primary.uppercased()])
        secondary = ordered.dropFirst().filter { seen.insert($0.uppercased()).inserted }
    }
}
