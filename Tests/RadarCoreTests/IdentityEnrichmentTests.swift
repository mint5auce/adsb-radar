import Foundation
import Testing
@testable import RadarCore

struct IdentityEnrichmentTests {
    let epoch = Date(timeIntervalSince1970: 1000)

    @Test func identityUsesRegistrationAndAirframeTypeWithoutRequiringAPosition() throws {
        let snapshot = try ADSBFiProvider.decode(Data(#"{"now":1000,"ac":[{"hex":"ABC123","r":" G-TEST ","t":"A320","type":"adsb_icao"},{"hex":"abc456","r":null,"t":" "},{"hex":"~abc123","r":"OTHER"}]}"#.utf8))
        #expect(snapshot.identities.count == 1)
        #expect(snapshot.identities.first?.registration == "G-TEST")
        #expect(snapshot.identities.first?.aircraftType == "A320")
        #expect(snapshot.observations.allSatisfy { $0.position == nil })
    }

    @Test func batchesPrioritiseSelectionDeduplicateAndBackOffMissingIdentities() {
        var catalogue = AircraftIdentityCatalogue()
        let batch = catalogue.begin(visible: ["aaa111", "aaa111", "bbb222", "~abc123"], selected: "ccc333", at: epoch, batchSize: 2)
        #expect(batch == ["ccc333", "aaa111"])
        #expect(catalogue.begin(visible: batch, selected: nil, at: epoch).isEmpty)
        catalogue.finish(batch, updates: [AircraftIdentityUpdate(address: "aaa111", registration: "G-TEST", updatedAt: epoch)], at: epoch)
        #expect(catalogue.begin(visible: batch, selected: nil, at: epoch.addingTimeInterval(29)).isEmpty)
        #expect(catalogue.begin(visible: batch, selected: nil, at: epoch.addingTimeInterval(30)).count == 2)
        catalogue.cancel(batch)
        catalogue.merge([AircraftIdentityUpdate(address: "aaa111", aircraftType: "A320", category: .large, updatedAt: epoch.addingTimeInterval(31))])
        #expect(catalogue.begin(visible: ["aaa111"], selected: nil, at: epoch.addingTimeInterval(100)).isEmpty)
        #expect(catalogue.identities["aaa111"]?.registration?.value == "G-TEST")
    }

    @Test func partialAndOlderResponsesRetainUsefulValuesAndProvenance() {
        var catalogue = AircraftIdentityCatalogue()
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", registration: "G-NEW", aircraftType: "A320", category: .large, updatedAt: epoch)])
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", registration: "G-OLD", updatedAt: epoch.addingTimeInterval(-1)),
            AircraftIdentityUpdate(address: "abc123", registration: " ", updatedAt: epoch.addingTimeInterval(10))])
        #expect(catalogue.identities["abc123"]?.registration?.value == "G-NEW")
        #expect(catalogue.identities["abc123"]?.aircraftType?.value == "A320")
        #expect(catalogue.identities["abc123"]?.lastUpdated == epoch)
        #expect(catalogue.identities["abc123"]?.registration?.provider == "adsb.fi")
    }

    @Test func batchEndpointFiltersInvalidAndUnrequestedAircraft() async throws {
        let payload = Data(#"{"now":1000,"ac":[{"hex":"abc123","r":"G-TEST","t":"A320"},{"hex":"fff000","r":"UNREQUESTED"}]}"#.utf8)
        let transport = IdentityTransport(payload: payload)
        let provider = ADSBFiProvider(scheduler: OnlineRequestScheduler(transport: transport))
        let updates = try await provider.identities(for: ["ABC123", "abc123", "aaa111", "~abc123", "invalid"])
        #expect(updates.map(\.address) == ["abc123"])
        #expect(await transport.urls.first?.lastPathComponent == "aaa111,abc123")
        #expect(try await provider.identities(for: ["invalid"]).isEmpty)
        #expect(await transport.urls.count == 1)
    }

    @Test func slowIdentityResponseDoesNotHoldUpPositionRequests() async throws {
        let transport = SlowIdentityTransport()
        let scheduler = OnlineRequestScheduler(transport: transport)
        let identity = Task { try await scheduler.get(URL(string: "https://example.test/identity")!, priority: .identity) }
        for _ in 0..<100 {
            if await !transport.urls.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let position = Task { try await scheduler.get(URL(string: "https://example.test/position")!) }
        for _ in 0..<150 {
            if await transport.urls.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let countBeforeCancellation = await transport.urls.count
        identity.cancel()
        _ = try await position.value
        _ = await identity.result
        #expect(countBeforeCancellation == 2)
    }

    @Test func schedulerHonoursRetryAfterAcrossBothRequestKinds() async throws {
        let transport = IdentityTransport(payload: Data(), retrySeconds: 1.3)
        let scheduler = OnlineRequestScheduler(transport: transport)
        _ = try await scheduler.get(URL(string: "https://example.test/first")!)
        _ = try await scheduler.get(URL(string: "https://example.test/second")!, priority: .identity)
        let times = await transport.times
        #expect(times[1].timeIntervalSince(times[0]) >= 1.29)
    }

    @Test @MainActor func enrichmentPreferenceDefaultsOnAndCanBeDisabledPersistently() throws {
        let name = "identity-settings-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = RadarPreferences(defaults: defaults)
        #expect(preferences.load().enrichIdentities)
        var settings = preferences.load()
        settings.enrichIdentities = false
        preferences.save(settings)
        #expect(!preferences.load().enrichIdentities)
        #expect(try JSONDecoder().decode(RadarSettings.self, from: Data(#"{"source":"local"}"#.utf8)).enrichIdentities)
    }
}

private actor IdentityTransport: OnlineHTTPTransport {
    var urls: [URL] = []
    var times: [Date] = []
    let payload: Data
    let retrySeconds: Double
    init(payload: Data, retrySeconds: Double = 0) { self.payload = payload; self.retrySeconds = retrySeconds }
    func get(_ url: URL) async throws -> OnlineHTTPResponse {
        urls.append(url)
        times.append(.now)
        return OnlineHTTPResponse(data: payload, retryAfter: urls.count == 1 && retrySeconds > 0 ? Date.now.addingTimeInterval(retrySeconds) : nil)
    }
}

private actor SlowIdentityTransport: OnlineHTTPTransport {
    var urls: [URL] = []
    func get(_ url: URL) async throws -> OnlineHTTPResponse {
        urls.append(url)
        if url.lastPathComponent == "identity" { try await Task.sleep(for: .seconds(20)) }
        return OnlineHTTPResponse(data: Data())
    }
}
