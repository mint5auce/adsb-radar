import Foundation

public struct MapLayerPreferences: Codable, Equatable, Sendable {
    public var routes = true
    public var airspace = true
    public var airports = true
    public var airportFilters = AirportFilters()
    public var flightLevel: Int?
    public init() {}

    private enum CodingKeys: String, CodingKey { case routes, airspace, airports, airportFilters, flightLevel }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        routes = try values.decodeIfPresent(Bool.self, forKey: .routes) ?? routes
        airspace = try values.decodeIfPresent(Bool.self, forKey: .airspace) ?? airspace
        airports = try values.decodeIfPresent(Bool.self, forKey: .airports) ?? airports
        airportFilters = try values.decodeIfPresent(AirportFilters.self, forKey: .airportFilters) ?? airportFilters
        flightLevel = try values.decodeIfPresent(Int.self, forKey: .flightLevel)
    }

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
        guard preferences.enabled(kind) else { return .hidden }
        if kind == .airport, !preferences.airportFilters.matches(self) { return .hidden }
        return slice(at: preferences.flightLevel)
    }
}
