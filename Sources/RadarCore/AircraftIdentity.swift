import Foundation

public struct AircraftIdentityValue: Equatable, Sendable {
    public let value: String
    public let provider: String
    public let updatedAt: Date

    public init(value: String, provider: String, updatedAt: Date) {
        self.value = value
        self.provider = provider
        self.updatedAt = updatedAt
    }
}

public struct AircraftIdentity: Equatable, Sendable {
    public var registration: AircraftIdentityValue?
    public var aircraftType: AircraftIdentityValue?
    public var lastUpdated: Date? { [registration?.updatedAt, aircraftType?.updatedAt].compactMap { $0 }.min() }
    public init(registration: AircraftIdentityValue? = nil, aircraftType: AircraftIdentityValue? = nil) {
        self.registration = registration
        self.aircraftType = aircraftType
    }
    public var complete: Bool { registration != nil && aircraftType != nil }
}

public struct AircraftIdentityUpdate: Equatable, Sendable {
    public let address: String
    public let registration: String?
    public let aircraftType: String?
    public let provider: String
    public let updatedAt: Date

    public init(address: String, registration: String? = nil, aircraftType: String? = nil,
                provider: String = "adsb.fi", updatedAt: Date = .now) {
        self.address = address.lowercased()
        self.registration = Self.cleaned(registration)
        self.aircraftType = Self.cleaned(aircraftType)
        self.provider = provider
        self.updatedAt = updatedAt
    }
    private static func cleaned(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

public protocol AircraftIdentityProvider: Sendable {
    func identities(for addresses: [String]) async throws -> [AircraftIdentityUpdate]
}

/// Identity state has no movement inputs or access to the contact session.
public struct AircraftIdentityCatalogue: Sendable {
    public private(set) var identities: [String: AircraftIdentity] = [:]
    private var pending: Set<String> = []
    private var retries: [String: OnlineRefreshPolicy] = [:]
    public init() {}

    public mutating func merge(_ updates: [AircraftIdentityUpdate]) {
        for update in updates where Self.isICAO(update.address) {
            var identity = identities[update.address] ?? AircraftIdentity()
            if let value = update.registration, identity.registration.map({ $0.updatedAt <= update.updatedAt }) ?? true {
                identity.registration = AircraftIdentityValue(value: value, provider: update.provider, updatedAt: update.updatedAt)
            }
            if let value = update.aircraftType, identity.aircraftType.map({ $0.updatedAt <= update.updatedAt }) ?? true {
                identity.aircraftType = AircraftIdentityValue(value: value, provider: update.provider, updatedAt: update.updatedAt)
            }
            if identity.registration != nil || identity.aircraftType != nil { identities[update.address] = identity }
        }
    }

    public mutating func begin(visible: [String], selected: String?, at now: Date, batchSize: Int = 20) -> [String] {
        let addresses = Set(visible + (selected.map { [$0] } ?? []))
        let due = addresses.filter { Self.isICAO($0) && !pending.contains($0) &&
            identities[$0]?.complete != true && now >= (retries[$0]?.nextAttempt ?? .distantPast) }
        let batch = Array(due.sorted { lhs, rhs in
            if lhs == rhs { return false }
            if lhs == selected { return true }
            if rhs == selected { return false }
            return lhs < rhs
        }.prefix(max(1, batchSize)))
        pending.formUnion(batch)
        return batch
    }

    public mutating func finish(_ batch: [String], updates: [AircraftIdentityUpdate], at now: Date) {
        let requested = Set(batch)
        merge(updates.filter { requested.contains($0.address) })
        pending.subtract(batch)
        for address in batch {
            if identities[address]?.complete == true { retries.removeValue(forKey: address) }
            else {
                var policy = retries[address] ?? OnlineRefreshPolicy()
                policy.failed(at: now, interval: 30)
                retries[address] = policy
            }
        }
    }

    public mutating func cancel(_ batch: [String]) { pending.subtract(batch) }

    public static func isICAO(_ address: String) -> Bool {
        address.range(of: "^[0-9a-f]{6}$", options: .regularExpression) != nil
    }
}
