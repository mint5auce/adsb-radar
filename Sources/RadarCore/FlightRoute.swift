import Foundation

/// A callsign database match, not a verified flight plan or the aircraft's current leg.
public struct FlightRoute: Equatable, Sendable {
    public let callsign: String
    public let airports: [FlightRouteAirport]
    public let provider: String
    public let sourceURL: URL

    public init(callsign: String, airports: [FlightRouteAirport], provider: String, sourceURL: URL) {
        self.callsign = callsign
        self.airports = airports
        self.provider = provider
        self.sourceURL = sourceURL
    }

    public static func normalizedCallsign(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.range(of: "^[A-Z0-9]{2,8}$", options: .regularExpression) != nil,
              cleaned.range(of: "[A-Z]", options: .regularExpression) != nil else { return nil }
        return cleaned
    }
}

public struct FlightRouteAirport: Equatable, Sendable {
    public let name: String
    public let icao: String
    public let iata: String?
    public let coordinate: GeographicCoordinate

    public init(name: String, icao: String, iata: String? = nil, coordinate: GeographicCoordinate) {
        self.name = name
        self.icao = icao
        self.iata = iata
        self.coordinate = coordinate
    }

    public var displayName: String {
        name + " (" + [iata, icao].compactMap { $0 }.joined(separator: " / ") + ")"
    }
}

public protocol FlightRouteProvider: Sendable {
    func route(for callsign: String) async throws -> FlightRoute?
}

public enum FlightRouteProviderError: Error, Sendable {
    case invalidResponse
    case http(Int, retryAfter: Date?)
}

/// Per-callsign mirror of Virtual Radar Server's CC0 standing data.
/// This provider uses its own paced allowance, independently of adsb.fi positions.
public struct VirtualRadarRouteProvider: FlightRouteProvider {
    public static let sourceURL = URL(string: "https://github.com/vradarserver/standing-data")!
    private let scheduler: OnlineRequestScheduler
    private let baseURL: URL

    public init(scheduler: OnlineRequestScheduler = OnlineRequestScheduler(),
                baseURL: URL = URL(string: "https://vrs-standing-data.adsb.lol/routes")!) {
        self.scheduler = scheduler
        self.baseURL = baseURL
    }

    public func route(for callsign: String) async throws -> FlightRoute? {
        guard let callsign = FlightRoute.normalizedCallsign(callsign) else { return nil }
        let url = baseURL.appendingPathComponent(String(callsign.prefix(2))).appendingPathComponent(callsign + ".json")
        let response = try await scheduler.get(url, priority: .identity)
        if response.status == 404 { return nil }
        guard (200..<300).contains(response.status) else {
            throw FlightRouteProviderError.http(response.status, retryAfter: response.retryAfter)
        }
        return try Self.decode(response.data, callsign: callsign)
    }

    public static func decode(_ data: Data, callsign: String) throws -> FlightRoute? {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let requested = FlightRoute.normalizedCallsign(callsign), payload.callsign == requested else {
            throw FlightRouteProviderError.invalidResponse
        }
        if payload.airportCodes == "unknown" { return nil }
        let airports = try payload.airports.map { airport in
            let name = airport.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, airport.icao.range(of: "^[A-Z0-9]{4}$", options: .regularExpression) != nil,
                  let coordinate = GeographicCoordinate(latitude: airport.lat, longitude: airport.lon) else {
                throw FlightRouteProviderError.invalidResponse
            }
            let iata = airport.iata.flatMap { $0.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil ? $0 : nil }
            return FlightRouteAirport(name: name, icao: airport.icao, iata: iata, coordinate: coordinate)
        }
        guard airports.count >= 2, airports.map(\.icao).joined(separator: "-") == payload.airportCodes else {
            throw FlightRouteProviderError.invalidResponse
        }
        return FlightRoute(callsign: requested, airports: airports, provider: "Virtual Radar Server / adsb.lol", sourceURL: sourceURL)
    }

    private struct Payload: Decodable {
        let callsign: String
        let airportCodes: String
        let airports: [Airport]
        enum CodingKeys: String, CodingKey {
            case callsign, airportCodes = "airport_codes", airports = "_airports"
        }
    }
    private struct Airport: Decodable {
        let name: String
        let icao: String
        let iata: String?
        let lat: Double
        let lon: Double
    }
}
