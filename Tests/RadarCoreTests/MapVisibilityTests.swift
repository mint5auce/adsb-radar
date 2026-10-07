import Foundation
import Testing
@testable import RadarCore

struct MapVisibilityTests {
    @Test func inclusiveStandardLimitsAndUncertainReferences() {
        let point = GeographicCoordinate(latitude: 52, longitude: -1)!
        var feature = MapFeature(id: "test", kind: .route, name: "L1", label: "L1", paths: [[point, point]])
        feature.lower = MapAltitude(value: 100, unit: "FL", reference: "STD")
        feature.upper = MapAltitude(value: 20000, unit: "FT", reference: "STD")
        #expect(feature.slice(at: nil) == .included)
        #expect(feature.slice(at: 100) == .included)
        #expect(feature.slice(at: 200) == .included)
        #expect(feature.slice(at: 99) == .hidden)
        #expect(feature.slice(at: 201) == .hidden)
        feature.lower.reference = "MSL"
        #expect(feature.slice(at: 50) == .uncertain)
        #expect(feature.slice(at: 300) == .uncertain)
        feature.lower = .unknown
        #expect(feature.slice(at: 100) == .uncertain)
    }
    @Test func invalidFlightLevelInputPreservesLastView() {
        var preferences = MapLayerPreferences()
        let valid = preferences.setFlightLevel("245"); #expect(valid)
        let negative = preferences.setFlightLevel("-10"); #expect(!negative)
        let decimal = preferences.setFlightLevel("100.5"); #expect(!decimal)
        let high = preferences.setFlightLevel("1000"); #expect(!high)
        #expect(preferences.flightLevel == 245)
    }
    @Test func airportSizesAreIndependentOfZoomAndFlightLevel() {
        let point = GeographicCoordinate(latitude: 52, longitude: -1)!
        var feature = MapFeature(id: "test", kind: .airport, name: "Field", label: "Field", paths: [[point]])
        var preferences = MapLayerPreferences(); preferences.flightLevel = 400
        feature.airportSize = .medium
        #expect(feature.visibility(preferences, radiusNM: 100) == .included)
        feature.airportSize = .small; feature.smallAirport = true
        #expect(feature.visibility(preferences, radiusNM: 100) == .hidden)
        #expect(feature.visibility(preferences, radiusNM: 25) == .hidden)
        preferences.airportFilters.sizes = [.small]
        #expect(feature.visibility(preferences, radiusNM: 250) == .included)
        #expect(feature.visibility(preferences, radiusNM: 25) == .included)
        feature.airportSize = .large; feature.smallAirport = false
        #expect(feature.visibility(preferences, radiusNM: 25) == .hidden)
        preferences.airportFilters.sizes.insert(.large)
        #expect(feature.visibility(preferences, radiusNM: 250) == .included)
        preferences.airportFilters.sizes = []
        #expect(feature.visibility(preferences, radiusNM: 25) == .hidden)
        preferences.airportFilters.sizes = Set(AirportSize.allCases)
        preferences.airports = false
        #expect(feature.visibility(preferences, radiusNM: 25) == .hidden)
    }

    @Test func airportServiceFiltersCombineWithSizeAndUnknownChoices() {
        let point = GeographicCoordinate(latitude: 52, longitude: -1)!
        var airport = MapFeature(id: "test", kind: .airport, name: "Field", label: "Field", paths: [[point]])
        airport.airportSize = .medium
        var preferences = MapLayerPreferences()
        let cases: [(Bool?, MapVisibility, MapVisibility)] = [
            (true, .included, .hidden), (false, .hidden, .included), (nil, .included, .included)
        ]
        for (status, withService, withoutService) in cases {
            airport.scheduledService = status
            preferences.airportFilters.service = .withScheduledService
            #expect(airport.visibility(preferences, radiusNM: 100) == withService)
            preferences.airportFilters.service = .withoutScheduledService
            #expect(airport.visibility(preferences, radiusNM: 100) == withoutService)
            preferences.airportFilters.service = .all
            #expect(airport.visibility(preferences, radiusNM: 100) == .included)
        }
        preferences.airportFilters.includeUnknownService = false
        #expect(airport.visibility(preferences, radiusNM: 100) == .included)
        preferences.airportFilters.service = .withScheduledService
        #expect(airport.visibility(preferences, radiusNM: 100) == .hidden)
        preferences.airportFilters.service = .withoutScheduledService
        #expect(airport.visibility(preferences, radiusNM: 100) == .hidden)
        airport.scheduledService = false
        #expect(airport.visibility(preferences, radiusNM: 100) == .included)
        preferences.airportFilters.sizes = [.large]
        #expect(airport.visibility(preferences, radiusNM: 100) == .hidden)
        let route = MapFeature(id: "route", kind: .route, name: "L1", label: "L1", paths: [[point, point]])
        #expect(route.visibility(preferences, radiusNM: 100) == .included)
    }

    @Test func olderAirportSnapshotsRetainSizesAndTreatServiceAsUnknown() throws {
        let point = GeographicCoordinate(latitude: 52, longitude: -1)!
        var preferences = MapLayerPreferences()
        preferences.airportFilters.service = .withScheduledService
        for size in AirportSize.allCases {
            var legacy = MapFeature(id: size.rawValue, kind: .airport, name: "Field", label: "Field", paths: [[point]])
            legacy.smallAirport = size == .small
            legacy.details = [MapDetail("TYPE", size.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())]
            let airport = try JSONDecoder().decode(MapFeature.self, from: JSONEncoder().encode(legacy))
            #expect(airport.airportSize == nil && airport.scheduledService == nil)
            #expect(airport.inspectionDetails.contains(MapDetail("SCHEDULED SERVICE", "UNKNOWN")))
            preferences.airportFilters.sizes = [size]
            #expect(airport.visibility(preferences, radiusNM: 250) == .included)
            preferences.airportFilters.includeUnknownService = false
            #expect(airport.visibility(preferences, radiusNM: 250) == .hidden)
            preferences.airportFilters.includeUnknownService = true
        }
    }
}
