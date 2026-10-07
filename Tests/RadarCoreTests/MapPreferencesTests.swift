import Foundation
import Testing
@testable import RadarCore

struct MapPreferencesTests {
    @Test @MainActor func airportFiltersUpgradeAndPersistWithoutReplacingSavedChoices() throws {
        let suite = "airport-preferences-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = RadarPreferences(defaults: defaults)
        #expect(preferences.load().mapLayers.airportFilters.sizes == [.large, .medium])
        #expect(!preferences.load().mapLayers.airports)
        defaults.set(Data(#"{"initialRadiusNM":75,"labelMode":"selectedOnly","mapLayers":{"routes":false,"airspace":true,"airports":false,"flightLevel":145}}"#.utf8), forKey: "phosphor-settings")
        var settings = preferences.load()
        #expect(settings.initialRadiusNM == 75 && settings.labelMode == .selectedOnly)
        #expect(!settings.mapLayers.routes && settings.mapLayers.airspace && !settings.mapLayers.airports)
        #expect(settings.mapLayers.flightLevel == 145)
        #expect(settings.mapLayers.airportFilters.sizes == [.large, .medium])
        #expect(settings.mapLayers.airportFilters.service == .all)
        #expect(settings.mapLayers.airportFilters.includeUnknownService)
        settings.mapLayers.airportFilters.sizes = [.small]
        settings.mapLayers.airportFilters.service = .withoutScheduledService
        settings.mapLayers.airportFilters.includeUnknownService = false
        preferences.save(settings)
        #expect(RadarPreferences(defaults: defaults).load() == settings)
        settings.mapLayers.airportFilters.sizes = []
        preferences.save(settings)
        #expect(RadarPreferences(defaults: defaults).load().mapLayers.airportFilters.sizes.isEmpty)
    }

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
