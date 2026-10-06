import Foundation

public struct RadarLaunchOptions: Sendable {
    public var source: AircraftSourceKind?
    public var scenario: SyntheticScenario?
    public var demoCount: Int?

    public init() {}

    public init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--synthetic": source = .synthetic
            case "--scenario", "--demo-count":
                guard index + 1 < arguments.count else { throw InvalidOption(argument: argument) }
                index += 1
                if argument == "--scenario" {
                    guard let value = SyntheticScenario(rawValue: arguments[index]) else { throw InvalidOption(argument: argument) }
                    scenario = value
                } else {
                    guard let value = Int(arguments[index]), (25...250).contains(value) else { throw InvalidOption(argument: argument) }
                    demoCount = value
                }
            default: break // AppKit may supply its own launch arguments.
            }
            index += 1
        }
        if scenario != nil || demoCount != nil { source = .synthetic }
    }

    public struct InvalidOption: Error, CustomStringConvertible {
        let argument: String
        public var description: String {
            "Invalid \(argument). Use --synthetic [--scenario test|demo] [--demo-count 25...250]."
        }
    }

    public func applying(to settings: RadarSettings) -> RadarSettings {
        var result = settings
        if let source { result.source = source }
        if let scenario { result.scenario = scenario }
        if let demoCount { result.demoCount = demoCount }
        return result.validated()
    }

    fileprivate func preservingSavedChoices(in edited: RadarSettings, saved: RadarSettings) -> RadarSettings {
        var result = edited
        if source != nil { result.source = saved.source }
        if scenario != nil { result.scenario = saved.scenario }
        if demoCount != nil { result.demoCount = saved.demoCount }
        return result
    }
}

/// Saves display edits while keeping command-line source choices temporary.
@MainActor
public final class RadarPreferences {
    private let defaults: UserDefaults
    private let options: RadarLaunchOptions

    public init(defaults: UserDefaults = .standard, options: RadarLaunchOptions = RadarLaunchOptions()) {
        self.defaults = defaults
        self.options = options
    }

    public func load() -> RadarSettings { options.applying(to: savedSettings()) }

    public func save(_ settings: RadarSettings) {
        let persistent = options.preservingSavedChoices(in: settings.validated(), saved: savedSettings())
        if let data = try? JSONEncoder().encode(persistent) { defaults.set(data, forKey: "phosphor-settings") }
    }

    private func savedSettings() -> RadarSettings {
        guard defaults.object(forKey: "phosphor-settings") != nil else { return .firstLaunch }
        return defaults.data(forKey: "phosphor-settings")
            .flatMap { try? JSONDecoder().decode(RadarSettings.self, from: $0) }?.validated() ?? RadarSettings()
    }
}
