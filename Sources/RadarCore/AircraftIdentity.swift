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
    public var modelDescription: AircraftIdentityValue?
    public var ownerOperator: AircraftIdentityValue?
    public var category: AircraftCategoryValue?
    public var detailFields: [AircraftIdentityValue] { [registration, aircraftType, modelDescription, ownerOperator].compactMap { $0 } }
    public var lastUpdated: Date? { (detailFields.map(\.updatedAt) + [category?.updatedAt].compactMap { $0 }).min() }
    public init(registration: AircraftIdentityValue? = nil, aircraftType: AircraftIdentityValue? = nil,
                modelDescription: AircraftIdentityValue? = nil, ownerOperator: AircraftIdentityValue? = nil,
                category: AircraftCategoryValue? = nil) {
        self.registration = registration
        self.aircraftType = aircraftType
        self.modelDescription = modelDescription
        self.ownerOperator = ownerOperator
        self.category = category
    }
    /// Keep model designators and acronyms intact while making known manufacturer names readable.
    public var aircraftLabel: String? {
        guard let description = modelDescription?.value else { return aircraftType?.value }
        let manufacturers = ["BOEING": "Boeing", "AIRBUS": "Airbus", "CESSNA": "Cessna", "PIPER": "Piper",
            "BEECH": "Beech", "BEECHCRAFT": "Beechcraft", "EMBRAER": "Embraer", "BOMBARDIER": "Bombardier",
            "GULFSTREAM": "Gulfstream", "DASSAULT": "Dassault", "BELL": "Bell", "ROBINSON": "Robinson",
            "AGUSTAWESTLAND": "AgustaWestland", "EUROCOPTER": "Eurocopter", "SIKORSKY": "Sikorsky"]
        let parts = description.split(separator: " ", maxSplits: 1)
        guard let first = parts.first, let manufacturer = manufacturers[String(first)] else { return description }
        return manufacturer + (parts.count == 2 ? " " + parts[1] : "")
    }
    public var complete: Bool { registration != nil && aircraftType != nil && category != nil }
    public func isFresh(at now: Date, refreshAge: TimeInterval) -> Bool {
        complete && lastUpdated.map { now.timeIntervalSince($0) < refreshAge } == true
    }
}

public struct AircraftIdentityUpdate: Equatable, Sendable {
    public let address: String
    public let registration: String?
    public let aircraftType: String?
    public let modelDescription: String?
    public let ownerOperator: String?
    public let category: AircraftCategory?
    public let provider: String
    public let updatedAt: Date

    public init(address: String, registration: String? = nil, aircraftType: String? = nil,
                modelDescription: String? = nil, ownerOperator: String? = nil,
                category: AircraftCategory? = nil, provider: String = "adsb.fi", updatedAt: Date = .now) {
        self.address = address.lowercased()
        self.registration = Self.cleaned(registration)
        self.aircraftType = Self.cleaned(aircraftType)
        self.modelDescription = Self.cleaned(modelDescription)
        self.ownerOperator = Self.cleaned(ownerOperator)
        self.category = category
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
            restore(identity.registration) { AircraftIdentityUpdate(address: address, registration: $0.value, provider: $0.provider, updatedAt: $0.updatedAt) }
            restore(identity.aircraftType) { AircraftIdentityUpdate(address: address, aircraftType: $0.value, provider: $0.provider, updatedAt: $0.updatedAt) }
            restore(identity.modelDescription) { AircraftIdentityUpdate(address: address, modelDescription: $0.value, provider: $0.provider, updatedAt: $0.updatedAt) }
            restore(identity.ownerOperator) { AircraftIdentityUpdate(address: address, ownerOperator: $0.value, provider: $0.provider, updatedAt: $0.updatedAt) }
            if let field = identity.category, !field.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               field.updatedAt.timeIntervalSince1970.isFinite {
                merge([AircraftIdentityUpdate(address: address, category: field.value, provider: field.provider, updatedAt: field.updatedAt)])
            }
        }
    }

    private mutating func restore(_ field: AircraftIdentityValue?, update: (AircraftIdentityValue) -> AircraftIdentityUpdate) {
        guard let field, !field.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              field.updatedAt.timeIntervalSince1970.isFinite else { return }
        merge([update(field)])
    }

    public mutating func merge(_ updates: [AircraftIdentityUpdate]) {
        for update in updates where Self.isICAO(update.address) {
            var identity = identities[update.address] ?? AircraftIdentity()
            if let value = update.registration, identity.registration.map({ $0.updatedAt <= update.updatedAt }) ?? true {
                identity.registration = AircraftIdentityValue(value: value, provider: update.provider, updatedAt: update.updatedAt)
            }
            if let value = update.aircraftType, identity.aircraftType.map({ $0.updatedAt <= update.updatedAt }) ?? true {
                // A corrected type code must not keep displaying the previous model's description.
                if let previous = identity.aircraftType, previous.value != value,
                   identity.modelDescription.map({ $0.updatedAt <= update.updatedAt }) == true {
                    identity.modelDescription = nil
                }
                identity.aircraftType = AircraftIdentityValue(value: value, provider: update.provider, updatedAt: update.updatedAt)
            }
            if let value = update.modelDescription,
               update.aircraftType == nil || update.aircraftType == identity.aircraftType?.value,
               identity.modelDescription.map({ $0.updatedAt <= update.updatedAt }) ?? true {
                identity.modelDescription = AircraftIdentityValue(value: value, provider: update.provider, updatedAt: update.updatedAt)
            }
            if let value = update.ownerOperator, identity.ownerOperator.map({ $0.updatedAt <= update.updatedAt }) ?? true {
                identity.ownerOperator = AircraftIdentityValue(value: value, provider: update.provider, updatedAt: update.updatedAt)
            }
            if let category = update.category, identity.category.map({ $0.updatedAt <= update.updatedAt }) ?? true {
                identity.category = AircraftCategoryValue(value: category, provider: update.provider, updatedAt: update.updatedAt)
            }
            if !identity.detailFields.isEmpty || identity.category != nil { identities[update.address] = identity }
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
