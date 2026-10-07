import Foundation
import Observation
import RadarCore

struct FlightRouteMatch: Equatable {
    let route: FlightRoute
    let lookedUpAt: Date
    var cached = false
}

enum FlightRouteLookupState: Equatable {
    case unknown
    case lookingUp
    case matched(FlightRouteMatch)

    var match: FlightRouteMatch? {
        if case .matched(let match) = self { return match }
        return nil
    }
}

/// Owns selected-flight enrichment only; it has no access to contact movement or identities.
@MainActor
@Observable
final class FlightRouteLookup {
    private(set) var state: FlightRouteLookupState = .unknown
    @ObservationIgnored private let provider: any FlightRouteProvider
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var selection: Selection?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var allowsLookup = false
    @ObservationIgnored private var cache: [String: CacheEntry] = [:]
    @ObservationIgnored private var retries: [String: OnlineRefreshPolicy] = [:]

    private struct CacheEntry {
        let match: FlightRouteMatch?
        let expiresAt: Date
    }

    private struct Selection: Equatable {
        let address: String
        let callsign: String
    }

    init(provider: any FlightRouteProvider, now: @escaping @MainActor () -> Date) {
        self.provider = provider
        self.now = now
    }

    func update(address: String?, callsign: String?, allowsLookup: Bool) {
        let selected = address.flatMap { address in
            FlightRoute.normalizedCallsign(callsign).map { Selection(address: address, callsign: $0) }
        }
        let changed = selected != selection || allowsLookup != self.allowsLookup
        if changed {
            cancel()
            selection = selected
            self.allowsLookup = allowsLookup
        }
        guard let target = selected else { return }
        let instant = now()
        if let entry = cache[target.callsign], instant < entry.expiresAt {
            if changed || state.match?.lookedUpAt != entry.match?.lookedUpAt {
                state = entry.match.map { match in
                    var cached = match
                    cached.cached = true
                    return .matched(cached)
                } ?? .unknown
            }
            return
        }
        guard request == nil else { return }
        state = .unknown
        guard allowsLookup, instant >= (retries[target.callsign]?.nextAttempt ?? .distantPast) else { return }
        state = .lookingUp
        let revision = revision
        request = Task {
            do {
                let route = try await provider.route(for: target.callsign)
                guard revision == self.revision, !Task.isCancelled else { return }
                if let route, route.callsign != target.callsign || route.airports.count < 2 {
                    throw FlightRouteProviderError.invalidResponse
                }
                let checkedAt = now()
                let match = route.map { FlightRouteMatch(route: $0, lookedUpAt: checkedAt) }
                cache = cache.filter { checkedAt < $0.value.expiresAt }
                // Bound a long-running session's cache without persisting flight data.
                if cache.count >= 256, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                    cache.removeValue(forKey: oldest)
                }
                cache[target.callsign] = CacheEntry(match: match, expiresAt: checkedAt.addingTimeInterval(route == nil ? 300 : 1800))
                retries.removeValue(forKey: target.callsign)
                state = match.map { .matched($0) } ?? .unknown
            } catch {
                guard revision == self.revision, !Task.isCancelled else { return }
                let retryAfter: Date?
                if case FlightRouteProviderError.http(_, let date) = error { retryAfter = date }
                else { retryAfter = nil }
                var policy = retries[target.callsign] ?? OnlineRefreshPolicy()
                policy.failed(at: now(), interval: 30, retryAfter: retryAfter)
                retries[target.callsign] = policy
                state = .unknown
            }
            request = nil
        }
    }

    func cancel() {
        revision += 1
        request?.cancel()
        request = nil
        selection = nil
        state = .unknown
    }

    func reset() {
        cancel()
        cache = [:]
        retries = [:]
    }
}
