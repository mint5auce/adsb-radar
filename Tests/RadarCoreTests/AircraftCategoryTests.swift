import Foundation
import Testing
import RadarCore

struct AircraftCategoryTests {
    @Test func nonICAOCategoriesUseReportDatesIndependentlyOfOlderPositions() throws {
        var settings = RadarSettings()
        settings.source = .online; settings.mode = .immediate
        settings.receiver = GeographicCoordinate(latitude: 0, longitude: 0)
        let date = Date(timeIntervalSince1970: 1000)
        var session = RadarSession(startedAt: date, enabledFeeds: [.online])
        let first = try ADSBFiProvider.decode(Data(#"{"now":1000,"ac":[{"hex":"~abc123","lat":0,"lon":1,"seen_pos":20,"category":"A5"}]}"#.utf8))
        session.ingest(first, from: .online)
        #expect(session.advance(to: date, settings: settings).first?.observation.positionTime == date.addingTimeInterval(-20))
        #expect(session.reportedCategory(for: "online:~abc123")?.updatedAt == date)
        let later = try ADSBFiProvider.decode(Data(#"{"now":1001,"ac":[{"hex":"~abc123","lat":0,"lon":2,"seen_pos":100,"category":"A2"}]}"#.utf8))
        session.ingest(later, from: .online)
        #expect(session.advance(to: date.addingTimeInterval(1), settings: settings).first?.observation.positionTime == date.addingTimeInterval(-20))
        #expect(session.reportedCategory(for: "online:~abc123")?.value == .small)
        #expect(session.reportedCategory(for: "online:~abc123")?.updatedAt == date.addingTimeInterval(1))
        var catalogue = AircraftIdentityCatalogue()
        catalogue.merge(first.identities + later.identities)
        #expect(catalogue.identities.isEmpty)
    }
    @Test func localReportsDecodeKnownCategoriesWithoutInventingUnknownOnes() throws {
        let data = Data(#"{"now":1000,"aircraft":[{"hex":"abc123","category":"A4"},{"hex":"bbb222","category":"A0"},{"hex":"ccc333","category":"B5"},{"hex":"ddd444","category":"nonsense"}]}"#.utf8)
        let snapshot = try ReceiverSnapshot.decode(data)
        #expect(snapshot.observations.count == 4)
        #expect(snapshot.observations.first?.category == .highVortexLarge)
        #expect(snapshot.observations.dropFirst().allSatisfy { $0.category == nil })
        #expect(snapshot.identities.first?.category == .highVortexLarge)
        #expect(snapshot.identities.first?.updatedAt == Date(timeIntervalSince1970: 1000))
    }

    @Test func knownCategoriesSurviveUnknownRefreshAndFileRestart() async throws {
        let date = Date(timeIntervalSince1970: 1000)
        var catalogue = AircraftIdentityCatalogue()
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", category: .heavy, provider: "LOCAL", updatedAt: date)])
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", updatedAt: date.addingTimeInterval(30))])
        #expect(catalogue.identities["abc123"]?.category?.value == .heavy)
        #expect(catalogue.identities["abc123"]?.category?.updatedAt == date)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = FileAircraftIdentityStorage(url: folder.appendingPathComponent("identities.json"))
        try await storage.save(catalogue.identities)
        #expect(try await storage.load() == catalogue.identities)
    }

    @Test func onlineReportsPreserveCategoriesAndOldCacheEntriesKeepTheirIdentity() throws {
        let online = try ADSBFiProvider.decode(Data(#"{"now":1000,"ac":[{"hex":"abc123","category":"A4"}]}"#.utf8))
        #expect(online.observations.first?.category == .highVortexLarge)
        #expect(online.identities.first?.category == .highVortexLarge)
        #expect(online.identities.first?.provider == "adsb.fi")
        let old = try JSONDecoder().decode(AircraftIdentity.self, from: Data(#"{"registration":{"value":"G-OLD","provider":"adsb.fi","updatedAt":1000},"aircraftType":{"value":"A320","provider":"adsb.fi","updatedAt":1000}}"#.utf8))
        #expect(old.registration?.value == "G-OLD" && old.aircraftType?.value == "A320")
        #expect(old.category == nil)
        var catalogue = AircraftIdentityCatalogue()
        catalogue.restore(["abc123": old])
        #expect(catalogue.begin(visible: ["abc123"], selected: nil, at: old.registration!.updatedAt) == ["abc123"])
    }
}
