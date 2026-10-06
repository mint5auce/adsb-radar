import Foundation
import Testing
import RadarCore

struct CombinedSessionTests {
    let epoch = Date(timeIntervalSince1970: 1000)
    func observation(_ seconds: Double, source: String, address: String = "abc123", latitude: Double = 51.5) -> AircraftObservation {
        AircraftObservation(address: address, position: GeographicCoordinate(latitude: latitude, longitude: -2.5),
            positionTime: epoch.addingTimeInterval(seconds), source: source)
    }
    var settings: RadarSettings {
        var result = RadarSettings()
        result.source = .combined
        result.mode = .immediate
        result.receiver = SyntheticSource.exampleLocation
        return result
    }

    @Test func freshLocalWinsThenFallsBackAndRecoversWithGenuineTimestamps() throws {
        var session = RadarSession(startedAt: epoch, enabledFeeds: [.local, .online])
        session.ingest(ReceiverSnapshot(observations: [observation(0, source: "LOCAL")]), from: .local)
        session.ingest(ReceiverSnapshot(observations: [observation(10, source: "adsb.fi", latitude: 51.6)]), from: .online)
        let local = try #require(session.advance(to: epoch.addingTimeInterval(12), settings: settings).first)
        #expect(local.observation.source == "LOCAL" && local.positionAge == 12)
        #expect(local.trail.count == 1)
        let online = try #require(session.advance(to: epoch.addingTimeInterval(15), settings: settings).first)
        #expect(online.observation.source == "adsb.fi" && online.positionAge == 5 && !online.stale)
        #expect(online.trail.map(\.time) == [epoch, epoch.addingTimeInterval(10)])
        session.ingest(ReceiverSnapshot(observations: [AircraftObservation(address: "abc123", callsign: "MESSAGE", source: "MESSAGE ONLY")]), from: .local)
        #expect(session.advance(to: epoch.addingTimeInterval(16), settings: settings).first?.observation.source == "adsb.fi")
        session.ingest(ReceiverSnapshot(observations: [observation(16, source: "LOCAL", latitude: 51.7)]), from: .local)
        let recovered = try #require(session.advance(to: epoch.addingTimeInterval(17), settings: settings).first)
        #expect(recovered.observation.source == "LOCAL" && recovered.positionAge == 1)
        #expect(recovered.trail.count == 3)
        #expect(session.advance(to: epoch.addingTimeInterval(31), settings: settings).first?.stale == true)
        #expect(session.advance(to: epoch.addingTimeInterval(76), settings: settings).isEmpty)
    }

    @Test func identityCollisionsAreScopedAndDisabledSourcesLoseOnlyTheirOwnContacts() throws {
        var session = RadarSession(startedAt: epoch, enabledFeeds: [.local, .online])
        session.ingest(ReceiverSnapshot(observations: [observation(0, source: "LOCAL"),
            observation(0, source: "LOCAL", address: "~abc123"), observation(0, source: "LOCAL", address: "aaa111")]), from: .local)
        session.ingest(ReceiverSnapshot(observations: [observation(1, source: "adsb.fi"),
            observation(1, source: "adsb.fi", address: "~abc123"), observation(1, source: "adsb.fi", address: "bbb222")]), from: .online)
        let combined = session.advance(to: epoch.addingTimeInterval(2), settings: settings)
        #expect(combined.count == 5)
        #expect(Set(combined.map(\.id)).contains("local:~abc123"))
        #expect(Set(combined.map(\.id)).contains("online:~abc123"))
        session.setEnabledFeeds([.online])
        let online = session.advance(to: epoch.addingTimeInterval(3), settings: settings)
        #expect(online.count == 3 && !online.contains { $0.id == "aaa111" })
        #expect(online.first { $0.id == "abc123" }?.observation.source == "adsb.fi")
        session.ingest(ReceiverSnapshot(observations: [observation(4, source: "LOCAL", address: "aaa111")]), from: .local)
        #expect(session.advance(to: epoch.addingTimeInterval(4), settings: settings).count == 3)
    }

    @Test func missingPositionMessagesNeverRelabelOrRefreshExistingPositions() throws {
        var session = RadarSession(startedAt: epoch)
        session.ingest(ReceiverSnapshot(observations: [observation(0, source: "ORIGINAL")]))
        session.ingest(ReceiverSnapshot(observations: [AircraftObservation(address: "abc123", callsign: "LATEST", source: "MESSAGE")]))
        let contact = try #require(session.advance(to: epoch.addingTimeInterval(10), settings: settings).first)
        #expect(contact.observation.source == "ORIGINAL" && contact.positionAge == 10)
        #expect(contact.observation.callsign == "LATEST")
        session.ingest(ReceiverSnapshot(observations: [observation(-1, source: "OLD", latitude: 50)]))
        #expect(session.advance(to: epoch.addingTimeInterval(11), settings: settings).first?.observation.position == contact.observation.position)
    }

    @Test func sweepHandoverCannotKeepADisabledSourceInTheInspector() throws {
        var sweep = settings
        sweep.mode = .sweep
        var session = RadarSession(startedAt: epoch, enabledFeeds: [.local, .online])
        session.ingest(ReceiverSnapshot(observations: [observation(0, source: "LOCAL")]), from: .local)
        #expect(session.advance(to: epoch.addingTimeInterval(4), settings: sweep).first?.observation.source == "LOCAL")
        session.ingest(ReceiverSnapshot(observations: [observation(4, source: "adsb.fi")]), from: .online)
        session.setEnabledFeeds([.online])
        #expect(session.advance(to: epoch.addingTimeInterval(4.1), settings: sweep).first?.observation.source == "adsb.fi")
    }
}
