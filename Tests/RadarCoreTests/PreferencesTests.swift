import Foundation
import Testing
import RadarCore

struct PreferencesTests {
    @Test @MainActor func syntheticLaunchDoesNotReplaceTheFirstLaunchLocalDefault() throws {
        let name = "adsb-radar-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let options = try RadarLaunchOptions(arguments: ["--synthetic"])
        let launched = RadarPreferences(defaults: defaults, options: options)
        var edited = launched.load()
        #expect(edited.source == .synthetic)
        edited.altitudeUnit = .metres
        launched.save(edited)
        let restored = RadarPreferences(defaults: defaults).load()
        #expect(restored.source == .local)
        #expect(restored.altitudeUnit == .metres)
        #expect(restored.receiver == nil)
    }

    @Test func settingsFromBeforeSyntheticSupportKeepTheirValues() throws {
        let data = Data(#"{"receiver":{"latitude":52,"longitude":-2},"mode":"immediate","sweepSeconds":6,"staleSeconds":20,"removalSeconds":75,"trailSeconds":90,"initialRadiusNM":80,"altitudeUnit":"metres","speedUnit":"kilometresPerHour","distanceUnit":"kilometres"}"#.utf8)
        let settings = try JSONDecoder().decode(RadarSettings.self, from: data)
        #expect(settings.receiver?.latitude == 52)
        #expect(settings.mode == .immediate && settings.speedUnit == .kilometresPerHour)
        #expect(settings.staleSeconds == 20 && settings.removalSeconds == 75)
        #expect(settings.source == .local && settings.scenario == .test && settings.demoCount == 100)
    }

    @Test func invalidScenarioAndCountProduceAnActionableLaunchError() {
        #expect(throws: RadarLaunchOptions.InvalidOption.self) { try RadarLaunchOptions(arguments: ["--scenario", "other"]) }
        #expect(throws: RadarLaunchOptions.InvalidOption.self) { try RadarLaunchOptions(arguments: ["--demo-count", "251"]) }
        #expect(throws: RadarLaunchOptions.InvalidOption.self) { try RadarLaunchOptions(arguments: ["--scenario"]) }
    }

    @Test @MainActor func launchOverridesStayTemporaryWhenDisplaySettingsAreSaved() throws {
        let name = "adsb-radar-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let normal = RadarPreferences(defaults: defaults)
        #expect(normal.load().source == .local)
        var saved = normal.load()
        saved.source = .synthetic
        saved.scenario = .test
        saved.demoCount = 25
        saved.receiver = GeographicCoordinate(latitude: 52, longitude: 0)
        normal.save(saved)
        let options = try RadarLaunchOptions(arguments: ["--synthetic", "--scenario", "demo", "--demo-count", "250"])
        let launched = RadarPreferences(defaults: defaults, options: options)
        var edited = launched.load()
        #expect(edited.source == .synthetic && edited.scenario == .demo && edited.demoCount == 250)
        edited.speedUnit = .milesPerHour
        launched.save(edited)
        let restored = normal.load()
        #expect(restored.scenario == .test && restored.demoCount == 25)
        #expect(restored.speedUnit == .milesPerHour)
        #expect(restored.receiver == saved.receiver)
    }
}
