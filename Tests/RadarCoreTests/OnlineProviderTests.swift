import Foundation
import Testing
@testable import RadarCore

struct OnlineProviderTests {
    @Test func compatiblePayloadsPreserveObservationAgeAndOptionalFields() throws {
        for key in ["aircraft", "ac"] {
            let json = Data("""
            {"now":1791291522000,"msg":"No error","\(key)":[
              {"hex":"ABC123","flight":" TEST1 ","lat":51.5,"lon":-2.5,"seen_pos":12.5,"seen":0,"alt_baro":"ground"},
              {"hex":"abc456","lat":true,"lon":0,"seen_pos":0},null,{"hex":"bad"}]}
            """.utf8)
            let snapshot = try ADSBFiProvider.decode(json)
            #expect(snapshot.observations.count == 2)
            let contact = try #require(snapshot.observations.first)
            #expect(contact.positionTime == Date(timeIntervalSince1970: 1791291509.5))
            #expect(contact.callsign == "TEST1" && contact.source == "adsb.fi")
            #expect(contact.altitude == .ground && contact.speedKnots == nil)
            #expect(snapshot.heardWithoutPosition == 1)
        }
        #expect(throws: (any Error).self) { try ADSBFiProvider.decode(Data(#"{"now":true,"ac":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { try ADSBFiProvider.decode(Data(#"{"now":1000,"ac":[],"msg":"Error"}"#.utf8)) }
    }

    @Test func retryPolicyHonoursProviderDelayAndResetsAfterRecovery() {
        let now = Date(timeIntervalSince1970: 1000)
        var policy = OnlineRefreshPolicy()
        policy.failed(at: now, interval: 1)
        #expect(policy.nextAttempt == now.addingTimeInterval(2))
        policy.failed(at: now, interval: 1)
        #expect(policy.nextAttempt == now.addingTimeInterval(4))
        policy.failed(at: now, interval: 1, retryAfter: now.addingTimeInterval(120))
        #expect(policy.nextAttempt == now.addingTimeInterval(120))
        policy.succeeded(at: now, interval: 7)
        #expect(policy.nextAttempt == now.addingTimeInterval(7))
        policy.failed(at: now, interval: 1)
        #expect(policy.nextAttempt == now.addingTimeInterval(2))
        #expect(URLSessionOnlineTransport.retryDate("30", now: now) == now.addingTimeInterval(30))
        #expect(URLSessionOnlineTransport.retryDate("Tue, 06 Oct 2026 13:00:00 GMT", now: now) != nil)
    }

    @Test func schedulerPacesPrioritisesAndCancelsQueuedRequests() async throws {
        let transport = RecordingTransport()
        let scheduler = OnlineRequestScheduler(transport: transport)
        let base = URL(string: "https://example.test")!
        _ = try await scheduler.get(base.appendingPathComponent("first"))
        let identity = Task { try await scheduler.get(base.appendingPathComponent("identity"), priority: .identity) }
        let cancelled = Task { try await scheduler.get(base.appendingPathComponent("cancelled")) }
        let position = Task { try await scheduler.get(base.appendingPathComponent("position")) }
        try await Task.sleep(for: .milliseconds(50))
        cancelled.cancel()
        _ = try await position.value
        _ = try await identity.value
        do { _ = try await cancelled.value; Issue.record("Cancelled request completed") } catch is CancellationError {} catch { Issue.record("Unexpected cancellation error: \(error)") }
        let calls = await transport.calls
        #expect(calls.map { $0.0.lastPathComponent } == ["first", "position", "identity"])
        #expect(calls[1].1.timeIntervalSince(calls[0].1) >= 0.99)
        #expect(calls[2].1.timeIntervalSince(calls[1].1) >= 0.99)
    }

    @Test func missingHomeMakesNoRequestsAndObsoleteResponsesAreDiscarded() async throws {
        let provider = SuspendedProvider()
        let feed = OnlineFeed(provider: provider)
        await feed.start(location: nil)
        let missing = await feed.poll()
        if case .failed = missing.status {} else { Issue.record("Missing Home should explain how to start") }
        #expect(await provider.calls == 0)
        await feed.start(location: SyntheticSource.exampleLocation)
        let request = Task { await feed.poll() }
        for _ in 0..<100 {
            if await provider.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await feed.stop()
        await provider.release()
        let reading = await request.value
        #expect(reading.snapshot == nil && reading.status == .stopped)
    }

    @Test @MainActor func onlinePreferencesMigrateAndPersistWithinProviderLimits() throws {
        let name = "online-settings-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data(#"{"source":"local","sweepSeconds":6}"#.utf8), forKey: "phosphor-settings")
        let preferences = RadarPreferences(defaults: defaults)
        var settings = preferences.load()
        #expect(settings.sweepSeconds == 6 && settings.onlineRefreshSeconds == 5 && settings.onlineRadiusNM == 250)
        settings.source = .online
        settings.onlineRefreshSeconds = 0
        settings.onlineRadiusNM = 900
        preferences.save(settings)
        #expect(preferences.load().source == .online)
        #expect(preferences.load().onlineRefreshSeconds == 1 && preferences.load().onlineRadiusNM == 250)
    }
}

private actor RecordingTransport: OnlineHTTPTransport {
    var calls: [(URL, Date)] = []
    func get(_ url: URL) async throws -> OnlineHTTPResponse {
        calls.append((url, .now))
        return OnlineHTTPResponse(data: Data())
    }
}

private actor SuspendedProvider: OnlineAircraftProvider {
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func positions(in search: OnlineSearch) async throws -> ReceiverSnapshot {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
        return ReceiverSnapshot(observations: [])
    }
    func release() { continuation?.resume(); continuation = nil }
}
