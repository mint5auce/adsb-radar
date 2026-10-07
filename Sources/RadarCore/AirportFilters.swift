import Foundation

public enum AirportSize: String, Codable, CaseIterable, Sendable {
    case large = "large_airport", medium = "medium_airport", small = "small_airport"

    public var title: String {
        switch self { case .large: "Large"; case .medium: "Medium"; case .small: "Small" }
    }
}

public enum AirportServiceFilter: String, Codable, CaseIterable, Sendable {
    case all, withScheduledService, withoutScheduledService

    public var title: String {
        switch self {
        case .all: "All"
        case .withScheduledService: "With scheduled service"
        case .withoutScheduledService: "Without scheduled service"
        }
    }
}

public struct AirportFilters: Codable, Equatable, Sendable {
    public var sizes: Set<AirportSize> = [.large, .medium]
    public var service: AirportServiceFilter = .all
    public var includeUnknownService = true

    public init() {}

    private enum CodingKeys: String, CodingKey { case sizes, service, includeUnknownService }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sizes = try values.decodeIfPresent(Set<AirportSize>.self, forKey: .sizes) ?? sizes
        service = try values.decodeIfPresent(AirportServiceFilter.self, forKey: .service) ?? service
        includeUnknownService = try values.decodeIfPresent(Bool.self, forKey: .includeUnknownService) ?? includeUnknownService
    }

    public func matches(_ airport: MapFeature) -> Bool {
        guard let size = airport.sizeForFiltering, sizes.contains(size) else { return false }
        if service == .all { return true }
        guard let scheduled = airport.scheduledService else { return includeUnknownService }
        return scheduled == (service == .withScheduledService)
    }
}

extension MapFeature {
    /// Older snapshots stored size in their Type detail and small-airport flag.
    var sizeForFiltering: AirportSize? {
        if let airportSize { return airportSize }
        if let type = details.first(where: { $0.title == "TYPE" })?.value,
           let size = AirportSize(rawValue: type.lowercased().replacingOccurrences(of: " ", with: "_")) { return size }
        return smallAirport ? .small : nil
    }
}
