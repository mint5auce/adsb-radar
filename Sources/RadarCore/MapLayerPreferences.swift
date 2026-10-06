import Foundation

public struct MapLayerPreferences: Codable, Equatable, Sendable {
    public var routes = true
    public var airspace = true
    public var airports = true
    public var flightLevel: Int?
    public init() {}
    public func enabled(_ kind: MapFeatureKind) -> Bool {
        switch kind { case .route: routes; case .airspace: airspace; case .airport: airports }
    }
}

public enum MapVisibility: Sendable { case included, uncertain, hidden }

extension MapLayerPreferences {
    @discardableResult public mutating func setFlightLevel(_ text: String) -> Bool {
        guard let level = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), (0...660).contains(level) else { return false }
        flightLevel = level
        return true
    }
}

extension MapAltitude {
    var standardFlightLevel: Double? {
        guard reference == "STD", let value, value.isFinite else { return nil }
        switch unit { case "FL": return value; case "FT": return value / 100; case "M": return value / 30.48; default: return nil }
    }
}

extension MapFeature {
    public func slice(at level: Int?) -> MapVisibility {
        guard kind != .airport, let level else { return .included }
        guard let floor = lower.standardFlightLevel, let ceiling = upper.standardFlightLevel, floor <= ceiling else { return .uncertain }
        return (floor...ceiling).contains(Double(level)) ? .included : .hidden
    }
    public func visibility(_ preferences: MapLayerPreferences, radiusNM: Double) -> MapVisibility {
        guard preferences.enabled(kind), !smallAirport || radiusNM <= 35 else { return .hidden }
        return slice(at: preferences.flightLevel)
    }
}
