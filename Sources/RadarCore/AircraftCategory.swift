import Foundation

/// Reported DO-260 emitter categories; no-information and reserved codes have no value.
public enum AircraftCategory: String, Codable, CaseIterable, Sendable {
    case light = "A1", small = "A2", large = "A3", highVortexLarge = "A4", heavy = "A5"
    case highPerformance = "A6", helicopter = "A7"
    case glider = "B1", lighterThanAir = "B2", parachutist = "B3", ultralight = "B4", unmanned = "B6", spaceVehicle = "B7"
    case emergencyVehicle = "C1", serviceVehicle = "C2", pointObstacle = "C3", clusterObstacle = "C4", lineObstacle = "C5"

    public var title: String {
        switch self {
        case .light: "Light"
        case .small: "Small"
        case .large: "Large"
        case .highVortexLarge: "High-vortex large"
        case .heavy: "Heavy"
        case .highPerformance: "High-performance"
        case .helicopter: "Helicopter"
        case .glider: "Glider"
        case .lighterThanAir: "Lighter than air"
        case .parachutist: "Parachutist"
        case .ultralight: "Ultralight"
        case .unmanned: "Unmanned aircraft"
        case .spaceVehicle: "Space vehicle"
        case .emergencyVehicle: "Emergency vehicle"
        case .serviceVehicle: "Service vehicle"
        case .pointObstacle: "Point obstacle"
        case .clusterObstacle: "Cluster obstacle"
        case .lineObstacle: "Line obstacle"
        }
    }
    public static func reported(_ value: String?) -> AircraftCategory? {
        value.flatMap { AircraftCategory(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) }
    }
}

public struct AircraftCategoryValue: Equatable, Codable, Sendable {
    public let value: AircraftCategory
    public let provider: String
    public let updatedAt: Date
    public init(value: AircraftCategory, provider: String, updatedAt: Date) {
        self.value = value; self.provider = provider; self.updatedAt = updatedAt
    }
}

public enum AircraftCategoryGroup: String, Codable, CaseIterable, Sendable {
    case light, small, large, heavy, highPerformance, helicopters, other
    public var title: String {
        switch self {
        case .highPerformance: "High-performance"
        default: rawValue.capitalized
        }
    }
    public static let largerAircraft: Set<AircraftCategoryGroup> = [.small, .large, .heavy]
}

extension AircraftCategory {
    public var group: AircraftCategoryGroup {
        switch self {
        case .light: .light
        case .small: .small
        case .large, .highVortexLarge: .large
        case .heavy: .heavy
        case .highPerformance: .highPerformance
        case .helicopter: .helicopters
        default: .other
        }
    }
}
