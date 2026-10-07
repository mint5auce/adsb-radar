import Foundation

public enum MapFeatureKind: String, Codable, Sendable { case route, airspace, airport }
public enum MapProvider: String, Codable, CaseIterable, Sendable {
    case nats, ourAirports
    public var title: String { self == .nats ? "NATS UK AIP" : "OurAirports" }
}

public struct MapAltitude: Codable, Equatable, Sendable {
    public var value: Double?
    public var unit: String
    public var reference: String
    public static let unknown = MapAltitude(value: nil, unit: "", reference: "")
    public var description: String {
        guard let value else { return "UNKNOWN" }
        if unit == "FL", reference == "STD" { return String(format: "FL %g", value) }
        if value == 0, reference == "SFC" { return "SFC" }
        return String(format: "%g %@ %@", value, unit, reference.isEmpty ? "(reference unknown)" : reference)
    }
}

public struct MapDetail: Codable, Equatable, Sendable {
    public let title: String
    public let value: String
    public init(_ title: String, _ value: String) { self.title = title; self.value = value }
}

public struct MapRouteEndpoint: Codable, Equatable, Sendable {
    public let name: String
    public let coordinate: GeographicCoordinate
}

/// A source-backed geographic object ready for projection, independent of live traffic.
/// Polygon paths consist of one exterior ring followed by any interior rings.
public struct MapFeature: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: MapFeatureKind
    public let name: String
    public let label: String
    public let paths: [[GeographicCoordinate]]
    public var lower: MapAltitude = .unknown
    public var upper: MapAltitude = .unknown
    public var details: [MapDetail] = []
    public var smallAirport = false
    public var airportSize: AirportSize?
    public var scheduledService: Bool?
    public var routeEndpoints: [MapRouteEndpoint]?
    public var inspectionDetails: [MapDetail] {
        if kind == .airport {
            return details + [MapDetail("SCHEDULED SERVICE", scheduledService.map { $0 ? "YES" : "NO" } ?? "UNKNOWN")]
        }
        guard let routeEndpoints, routeEndpoints.count == 2 else { return details }
        return [MapDetail("FROM", routeEndpoints[0].name), MapDetail("TO", routeEndpoints[1].name)] + details
    }
}

public struct MapSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public let provider: MapProvider
    public let date: String
    public let sourceURL: String
    public let terms: String
    public let coverage: String
    public let features: [MapFeature]

    public func validate() throws {
        guard schemaVersion == 1, Self.validDate(date), !features.isEmpty,
              Set(features.map(\.id)).count == features.count else { throw MapDataError.invalid("Invalid map snapshot") }
        for feature in features {
            guard !feature.id.isEmpty, !feature.name.isEmpty, !feature.paths.isEmpty,
                  provider == .nats ? feature.kind != .airport : feature.kind == .airport else {
                throw MapDataError.invalid("Invalid map feature")
            }
            if feature.kind == .route {
                guard let endpoints = feature.routeEndpoints, endpoints.count == 2,
                      endpoints.allSatisfy({ !$0.name.isEmpty && GeographicCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) != nil }) else {
                    throw MapDataError.invalid("Missing route endpoint metadata")
                }
            }
            guard feature.lower.value?.isFinite != false, feature.upper.value?.isFinite != false else {
                throw MapDataError.invalid("Invalid vertical limit")
            }
            if let lower = feature.lower.standardFlightLevel, let upper = feature.upper.standardFlightLevel, lower > upper {
                throw MapDataError.invalid("Inverted vertical limits")
            }
            for path in feature.paths {
                let minimum = feature.kind == .airport ? 1 : feature.kind == .route ? 2 : 4
                guard path.count >= minimum, path.allSatisfy({ GeographicCoordinate(latitude: $0.latitude, longitude: $0.longitude) != nil }) else {
                    throw MapDataError.invalid("Invalid geometry for \(feature.name)")
                }
                if feature.kind == .airspace, path.first != path.last { throw MapDataError.invalid("Unclosed airspace boundary") }
            }
        }
    }

    /// A parseable fragment is not a safe replacement for an established dataset.
    /// Large legitimate coverage changes need a reviewed bundled snapshot first.
    public func validateReplacement(of previous: MapSnapshot) throws {
        try validate()
        guard provider == previous.provider, date >= previous.date else { throw MapDataError.invalid("Map replacement has the wrong provider or an older date") }
        for kind in [MapFeatureKind.route, .airspace, .airport] {
            let oldCount = previous.features.filter { $0.kind == kind }.count
            let newCount = features.filter { $0.kind == kind }.count
            guard oldCount == 0 || Double(newCount) >= Double(oldCount) * 0.8 else {
                throw MapDataError.invalid("The downloaded \(kind.rawValue) layer is unexpectedly incomplete (\(newCount) of \(oldCount) records).")
            }
        }
    }

    public static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return value.count == 10 && formatter.date(from: value).map { formatter.string(from: $0) == value } == true
    }
}

public enum MapDataError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
