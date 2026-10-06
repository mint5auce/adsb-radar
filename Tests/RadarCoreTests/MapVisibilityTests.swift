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
    @Test func airportsIgnoreAltitudeAndSmallFieldsRequireZoom() {
        let point = GeographicCoordinate(latitude: 52, longitude: -1)!
        var feature = MapFeature(id: "test", kind: .airport, name: "Field", label: "Field", paths: [[point]])
        var preferences = MapLayerPreferences(); preferences.flightLevel = 400
        #expect(feature.visibility(preferences, radiusNM: 100) == .included)
        feature.smallAirport = true
        #expect(feature.visibility(preferences, radiusNM: 100) == .hidden)
        #expect(feature.visibility(preferences, radiusNM: 25) == .included)
        preferences.airports = false
        #expect(feature.visibility(preferences, radiusNM: 25) == .hidden)
    }
}
