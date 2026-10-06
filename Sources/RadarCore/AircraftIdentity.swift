import Foundation

public struct AircraftIdentityValue: Equatable, Codable, Sendable {
    public let value: String
    public let provider: String
    public let updatedAt: Date

    public init(value: String, provider: String, updatedAt: Date) {
        self.value = value
        self.provider = provider
        self.updatedAt = updatedAt
    }
}

public struct AircraftIdentity: Equatable, Codable, Sendable {
    public var registration: AircraftIdentityValue?
    public var aircraftType: AircraftIdentityValue?
    public var lastUpdated: Date? { [registration?.updatedAt, aircraftType?.updatedAt].compactMap { $0 }.min() }
    public init(registration: AircraftIdentityValue? = nil, aircraftType: AircraftIdentityValue? = nil) {
        self.registration = registration
        self.aircraftType = aircraftType
    }
    public var complete: Bool { registration != nil && aircraftType != nil }
    public func isFresh(at now: Date, refreshAge: TimeInterval) -> Bool {
        complete && lastUpdated.map { now.timeIntervalSince($0) < refreshAge } == true
    }
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

    /// Merge persisted fields independently so a late disk read cannot overwrite a newer response.
    public mutating func restore(_ saved: [String: AircraftIdentity]) {
        for (address, identity) in saved {
            for (registration, field) in [(true, identity.registration), (false, identity.aircraftType)] {
                guard let field, !field.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      field.updatedAt.timeIntervalSince1970.isFinite else { continue }
                merge([AircraftIdentityUpdate(address: address, registration: registration ? field.value : nil,
                    aircraftType: registration ? nil : field.value, provider: field.provider, updatedAt: field.updatedAt)])
            }
        }
    }

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

    public mutating func begin(visible: [String], selected: String?, at now: Date, batchSize: Int = 20, refreshAge: TimeInterval = 7 * 86400) -> [String] {
        let addresses = Set(visible + (selected.map { [$0] } ?? []))
        let due = addresses.filter { Self.isICAO($0) && !pending.contains($0) &&
            identities[$0]?.isFresh(at: now, refreshAge: refreshAge) != true && now >= (retries[$0]?.nextAttempt ?? .distantPast) }
        let batch = Array(due.sorted { lhs, rhs in
            if lhs == rhs { return false }
            if lhs == selected { return true }
            if rhs == selected { return false }
            return lhs < rhs
        }.prefix(max(1, batchSize)))
        pending.formUnion(batch)
        return batch
    }

    public mutating func finish(_ batch: [String], updates: [AircraftIdentityUpdate], at now: Date, refreshAge: TimeInterval = 7 * 86400) {
        let requested = Set(batch)
        merge(updates.filter { requested.contains($0.address) })
        pending.subtract(batch)
        for address in batch {
            if identities[address]?.isFresh(at: now, refreshAge: refreshAge) == true { retries.removeValue(forKey: address) }
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
