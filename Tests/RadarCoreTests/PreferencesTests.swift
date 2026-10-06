import Foundation
import Testing
import RadarCore

struct PreferencesTests {
    @Test @MainActor func legacyPresentationSurvivesAndVisibilityChoicePersists() throws {
        let name = "phosphor-legacy-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"initialRadiusNM":75}"#.utf8), forKey: "phosphor-settings")
        let preferences = RadarPreferences(defaults: defaults)
        var settings = preferences.load()
        #expect(settings.labelMode == .automatic && settings.trailMode == .selected)
        #expect(settings.mapLayers.routes && settings.mapLayers.airspace && settings.mapLayers.airports)
        #expect(settings.controlVisibility == .pointerAtEdge)
        #expect(settings.initialRadiusNM == 75)
        settings.controlVisibility = .caretButtons
        settings.mapLayers.routes = false
        settings.labelMode = .selectedOnly
        preferences.save(settings)
        #expect(RadarPreferences(defaults: defaults).load() == settings)
    }

    @Test @MainActor func firstLaunchUsesAnUnadornedMapAndAllAircraftDetail() throws {
        let name = "phosphor-startup-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = RadarPreferences(defaults: defaults)
        let settings = preferences.load()
        #expect(!settings.mapLayers.routes && !settings.mapLayers.airspace && !settings.mapLayers.airports)
        #expect(settings.labelMode == .all && settings.trailMode == .all && settings.directionVectors)
        preferences.save(settings)
        #expect(RadarPreferences(defaults: defaults).load() == settings)
    }

    @Test @MainActor func missingReceiverAttemptLimitDefaultsMigratesAndPersists() throws {
        let name = "phosphor-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = RadarPreferences(defaults: defaults)
        #expect(preferences.load().localReceiverAttemptLimit == 3)
        defaults.set(Data(#"{"mode":"immediate"}"#.utf8), forKey: "phosphor-settings")
        var settings = preferences.load()
        #expect(settings.localReceiverAttemptLimit == 3 && settings.mode == .immediate)
        settings.localReceiverAttemptLimit = 5
        preferences.save(settings)
        #expect(preferences.load().localReceiverAttemptLimit == 5)
        settings.localReceiverAttemptLimit = 0
        preferences.save(settings)
        #expect(preferences.load().localReceiverAttemptLimit == 1)
    }

    @Test @MainActor func syntheticLaunchDoesNotReplaceTheFirstLaunchLocalDefault() throws {
        let name = "phosphor-tests-\(UUID().uuidString)"
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
        let name = "phosphor-tests-\(UUID().uuidString)"
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
