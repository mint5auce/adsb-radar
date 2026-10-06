import Foundation
import Testing
@testable import RadarCore

struct MapPreferencesTests {
    @Test func mapLayersUpgradeExistingSettingsAndPersistIndependently() throws {
        var settings = try JSONDecoder().decode(RadarSettings.self, from: Data("{\"initialRadiusNM\":75}".utf8))
        #expect(settings.mapLayers.routes)
        #expect(settings.mapLayers.airspace)
        #expect(settings.mapLayers.airports)
        settings.mapLayers.routes = false
        let roundTrip = try JSONDecoder().decode(RadarSettings.self, from: JSONEncoder().encode(settings))
        #expect(!roundTrip.mapLayers.routes)
        #expect(roundTrip.initialRadiusNM == 75)
        #expect(roundTrip.mapLayers.airports)
    }
}
