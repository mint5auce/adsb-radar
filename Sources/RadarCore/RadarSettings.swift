import Foundation

public enum UpdateMode: String, Codable, CaseIterable, Sendable { case sweep, immediate }
public enum AltitudeUnit: String, Codable, CaseIterable, Sendable { case feet, metres }
public enum SpeedUnit: String, Codable, CaseIterable, Sendable { case knots, kilometresPerHour, milesPerHour }
public enum DistanceUnit: String, Codable, CaseIterable, Sendable { case nauticalMiles, kilometres, miles }
public enum AircraftFeed: String, CaseIterable, Sendable { case local, online, synthetic }
public enum AircraftSourceKind: String, Codable, CaseIterable, Sendable {
    case local, online, combined, synthetic
    public var feeds: Set<AircraftFeed> {
        switch self {
        case .local: [.local]
        case .online: [.online]
        case .combined: [.local, .online]
        case .synthetic: [.synthetic]
        }
    }
    public var usesOnline: Bool { feeds.contains(.online) }
}

public struct RadarSettings: Equatable, Codable, Sendable {
    public var receiver: GeographicCoordinate?
    public var mode: UpdateMode = .sweep
    public var sweepSeconds: Double = 4
    public var staleSeconds: Double = 15
    public var removalSeconds: Double = 60
    public var trailSeconds: Double = 120
    public var initialRadiusNM: Double = 100
    public var altitudeUnit: AltitudeUnit = .feet
    public var speedUnit: SpeedUnit = .knots
    public var distanceUnit: DistanceUnit = .nauticalMiles
    public var source: AircraftSourceKind = .local
    public var scenario: SyntheticScenario = .test
    public var demoCount: Int = 100
    public var localReceiverAttemptLimit: Int = 3
    public var onlineRefreshSeconds: Double = 5
    public var onlineRadiusNM: Double = 250
    public var enrichIdentities: Bool = true
    public var identityRefreshDays: Double = 7
    public var aircraftFilters = AircraftViewFilters()
    public var labelMode: AircraftLabelMode = .automatic
    public var trailMode: AircraftTrailMode = .selected
    public var directionVectors: Bool = true
    public var mapLayers = MapLayerPreferences()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case receiver, mode, sweepSeconds, staleSeconds, removalSeconds, trailSeconds, initialRadiusNM
        case altitudeUnit, speedUnit, distanceUnit, source, scenario, demoCount, onlineRefreshSeconds, onlineRadiusNM, enrichIdentities, identityRefreshDays
        case labelMode, trailMode, directionVectors, aircraftFilters, localReceiverAttemptLimit, mapLayers
    }

    // Decode missing keys with defaults so an upgrade preserves the user's existing preferences.
    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        receiver = try values.decodeIfPresent(GeographicCoordinate.self, forKey: .receiver)
        mode = try values.decodeIfPresent(UpdateMode.self, forKey: .mode) ?? mode
        sweepSeconds = try values.decodeIfPresent(Double.self, forKey: .sweepSeconds) ?? sweepSeconds
        staleSeconds = try values.decodeIfPresent(Double.self, forKey: .staleSeconds) ?? staleSeconds
        removalSeconds = try values.decodeIfPresent(Double.self, forKey: .removalSeconds) ?? removalSeconds
        trailSeconds = try values.decodeIfPresent(Double.self, forKey: .trailSeconds) ?? trailSeconds
        initialRadiusNM = try values.decodeIfPresent(Double.self, forKey: .initialRadiusNM) ?? initialRadiusNM
        altitudeUnit = try values.decodeIfPresent(AltitudeUnit.self, forKey: .altitudeUnit) ?? altitudeUnit
        speedUnit = try values.decodeIfPresent(SpeedUnit.self, forKey: .speedUnit) ?? speedUnit
        distanceUnit = try values.decodeIfPresent(DistanceUnit.self, forKey: .distanceUnit) ?? distanceUnit
        source = try values.decodeIfPresent(AircraftSourceKind.self, forKey: .source) ?? source
        scenario = try values.decodeIfPresent(SyntheticScenario.self, forKey: .scenario) ?? scenario
        demoCount = try values.decodeIfPresent(Int.self, forKey: .demoCount) ?? demoCount
        localReceiverAttemptLimit = try values.decodeIfPresent(Int.self, forKey: .localReceiverAttemptLimit) ?? localReceiverAttemptLimit
        onlineRefreshSeconds = try values.decodeIfPresent(Double.self, forKey: .onlineRefreshSeconds) ?? onlineRefreshSeconds
        onlineRadiusNM = try values.decodeIfPresent(Double.self, forKey: .onlineRadiusNM) ?? onlineRadiusNM
        enrichIdentities = try values.decodeIfPresent(Bool.self, forKey: .enrichIdentities) ?? enrichIdentities
        identityRefreshDays = try values.decodeIfPresent(Double.self, forKey: .identityRefreshDays) ?? identityRefreshDays
        aircraftFilters = try values.decodeIfPresent(AircraftViewFilters.self, forKey: .aircraftFilters) ?? aircraftFilters
        labelMode = try values.decodeIfPresent(AircraftLabelMode.self, forKey: .labelMode) ?? labelMode
        trailMode = try values.decodeIfPresent(AircraftTrailMode.self, forKey: .trailMode) ?? trailMode
        directionVectors = try values.decodeIfPresent(Bool.self, forKey: .directionVectors) ?? directionVectors
        mapLayers = try values.decodeIfPresent(MapLayerPreferences.self, forKey: .mapLayers) ?? mapLayers
    }

    public func validated() -> RadarSettings {
        var value = self
        func bounded(_ number: Double, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            min(range.upperBound, max(range.lowerBound, number.isFinite ? number : fallback))
        }
        value.sweepSeconds = bounded(sweepSeconds, 4, 0.5...30)
        value.staleSeconds = bounded(staleSeconds, 15, 1...300)
        value.removalSeconds = bounded(removalSeconds, 60, value.staleSeconds...900)
        value.trailSeconds = bounded(trailSeconds, 120, 5...600)
        value.initialRadiusNM = bounded(initialRadiusNM, 100, 5...2000)
        value.demoCount = min(250, max(25, demoCount))
        value.localReceiverAttemptLimit = max(1, localReceiverAttemptLimit)
        value.onlineRefreshSeconds = bounded(onlineRefreshSeconds, 5, 1...300)
        value.onlineRadiusNM = bounded(onlineRadiusNM, 250, 1...250)
        value.identityRefreshDays = bounded(identityRefreshDays, 7, (1.0 / 24)...3650)
        if let level = value.mapLayers.flightLevel, !(0...660).contains(level) { value.mapLayers.flightLevel = nil }
        if value.aircraftFilters.validationMessage != nil { value.aircraftFilters = AircraftViewFilters() }
        if let receiver { value.receiver = GeographicCoordinate(latitude: receiver.latitude, longitude: receiver.longitude) }
        return value
    }

    public func altitude(_ altitude: AircraftAltitude?) -> String {
        switch altitude {
        case .ground: return "GROUND"
        case .feet(let value): return String(format: "%.0f %@", altitudeValue(value), altitudeUnit == .feet ? "FT" : "M")
        case nil: return "UNKNOWN"
        }
    }

    public func altitudeValue(_ feet: Double) -> Double { altitudeUnit == .feet ? feet : feet * 0.3048 }

    public func speed(_ knots: Double?) -> String {
        guard let knots else { return "UNKNOWN" }
        switch speedUnit {
        case .knots: return String(format: "%.0f KT", knots)
        case .kilometresPerHour: return String(format: "%.0f KM/H", knots * 1.852)
        case .milesPerHour: return String(format: "%.0f MPH", knots * 1.150779448)
        }
    }

    public func distance(_ nauticalMiles: Double) -> String {
        String(format: "%.0f %@", distanceValue(nauticalMiles), distanceSymbol)
    }

    public func distanceValue(_ nauticalMiles: Double) -> Double {
        switch distanceUnit {
        case .nauticalMiles: nauticalMiles
        case .kilometres: nauticalMiles * 1.852
        case .miles: nauticalMiles * 1.150779448
        }
    }

    public var distanceSymbol: String {
        switch distanceUnit { case .nauticalMiles: "NM"; case .kilometres: "KM"; case .miles: "MI" }
    }
}
