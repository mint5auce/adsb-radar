import Foundation
import Testing
import RadarCore

struct IdentityStorageTests {
    let epoch = Date(timeIntervalSince1970: 1000)

    @Test func fileRoundTripRetainsEachFieldsDateAndProviderWithoutMovement() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("identities.json")
        let storage = FileAircraftIdentityStorage(url: url)
        #expect(try await storage.load().isEmpty)
        var catalogue = AircraftIdentityCatalogue()
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", registration: "G-TEST", provider: "first", updatedAt: epoch),
            AircraftIdentityUpdate(address: "abc123", aircraftType: "A320", modelDescription: "AIRBUS A320", provider: "second", updatedAt: epoch.addingTimeInterval(20)),
            AircraftIdentityUpdate(address: "abc123", ownerOperator: "Example Airways", provider: "third", updatedAt: epoch.addingTimeInterval(30))])
        var saved = catalogue.identities
        saved["~abc123"] = saved["abc123"]
        try await storage.save(saved)
        let restored = try await FileAircraftIdentityStorage(url: url).load()
        #expect(restored == catalogue.identities)
        let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(Set(document.keys) == ["version", "identities"])
        #expect(restored["abc123"]?.registration?.updatedAt == epoch)
        #expect(restored["abc123"]?.aircraftType?.provider == "second")
        #expect(restored["abc123"]?.aircraftLabel == "Airbus A320")
        #expect(restored["abc123"]?.ownerOperator?.provider == "third")
        #expect(restored["abc123"]?.ownerOperator?.updatedAt == epoch.addingTimeInterval(30))
    }

    @Test func existingVersionOneCachesDecodeWithoutDescriptionOrOwner() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("identities.json")
        try Data(#"{"version":1,"identities":{"abc123":{"registration":{"value":"G-TEST","provider":"adsb.fi","updatedAt":0},"aircraftType":{"value":"B77W","provider":"adsb.fi","updatedAt":0}}}}"#.utf8).write(to: url)
        let restored = try await FileAircraftIdentityStorage(url: url).load()
        #expect(restored["abc123"]?.aircraftLabel == "B77W")
        #expect(restored["abc123"]?.modelDescription == nil && restored["abc123"]?.ownerOperator == nil)
    }

    @Test func corruptUnknownVersionAndUnwritableStorageReportErrors() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("identities.json")
        let storage = FileAircraftIdentityStorage(url: url)
        try Data("broken json".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await storage.load() }
        try Data(#"{"version":99,"identities":{}}"#.utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await storage.load() }
        // A regular file used as the parent is a deterministic write failure, even as root.
        let blocked = FileAircraftIdentityStorage(url: url.appendingPathComponent("child.json"))
        await #expect(throws: (any Error).self) { try await blocked.save([:]) }
    }

    @Test func refreshAgeUsesOldestKnownFieldAndQueriesOnlyEncounteredIdentities() {
        var catalogue = AircraftIdentityCatalogue()
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", registration: "G-TEST", aircraftType: "A320", category: .large, updatedAt: epoch),
            AircraftIdentityUpdate(address: "aaa111", registration: "UNSEEN", aircraftType: "B738", category: .large, updatedAt: epoch)])
        #expect(catalogue.begin(visible: ["abc123"], selected: nil, at: epoch.addingTimeInterval(9), refreshAge: 10).isEmpty)
        #expect(catalogue.begin(visible: [], selected: nil, at: epoch.addingTimeInterval(100), refreshAge: 10).isEmpty)
        #expect(catalogue.begin(visible: [], selected: "abc123", at: epoch.addingTimeInterval(10), refreshAge: 10) == ["abc123"])
    }

    @Test func partialAndFailedRefreshesPreserveOldFieldsAndBackOffEvenWithCompleteCache() {
        var catalogue = AircraftIdentityCatalogue()
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", registration: "G-TEST", aircraftType: "A320", category: .large, updatedAt: epoch)])
        let refresh = epoch.addingTimeInterval(100)
        let batch = catalogue.begin(visible: ["abc123"], selected: nil, at: refresh, refreshAge: 10)
        catalogue.finish(batch, updates: [AircraftIdentityUpdate(address: "abc123", aircraftType: "A321", updatedAt: refresh)], at: refresh, refreshAge: 10)
        #expect(catalogue.identities["abc123"]?.registration?.updatedAt == epoch)
        #expect(catalogue.identities["abc123"]?.aircraftType?.updatedAt == refresh)
        #expect(catalogue.identities["abc123"]?.lastUpdated == epoch)
        #expect(catalogue.begin(visible: batch, selected: nil, at: refresh.addingTimeInterval(29), refreshAge: 10).isEmpty)
        let retry = catalogue.begin(visible: batch, selected: nil, at: refresh.addingTimeInterval(30), refreshAge: 10)
        #expect(retry == batch)
        catalogue.finish(retry, updates: [], at: refresh.addingTimeInterval(30), refreshAge: 10)
        #expect(catalogue.identities["abc123"]?.lastUpdated == epoch)
        #expect(catalogue.begin(visible: batch, selected: nil, at: refresh.addingTimeInterval(59), refreshAge: 10).isEmpty)
    }

    @Test func lateCacheLoadCannotReplaceNewerFieldsAndCanFillMissingFields() {
        var catalogue = AircraftIdentityCatalogue()
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", registration: "G-NEW", updatedAt: epoch)])
        let old = AircraftIdentityValue(value: "G-OLD", provider: "cached", updatedAt: epoch.addingTimeInterval(-1))
        let type = AircraftIdentityValue(value: "A320", provider: "cached", updatedAt: epoch.addingTimeInterval(-1))
        let description = AircraftIdentityValue(value: "AIRBUS A320", provider: "cached", updatedAt: epoch.addingTimeInterval(-1))
        let owner = AircraftIdentityValue(value: "Example Airways", provider: "cached", updatedAt: epoch.addingTimeInterval(-1))
        catalogue.merge([AircraftIdentityUpdate(address: "abc123", modelDescription: "AIRBUS A320neo", updatedAt: epoch)])
        catalogue.restore(["abc123": AircraftIdentity(registration: old, aircraftType: type, modelDescription: description, ownerOperator: owner), "invalid": AircraftIdentity(registration: old)])
        #expect(catalogue.identities["abc123"]?.registration?.value == "G-NEW")
        #expect(catalogue.identities["abc123"]?.aircraftType == type)
        #expect(catalogue.identities["abc123"]?.modelDescription?.value == "AIRBUS A320neo")
        #expect(catalogue.identities["abc123"]?.ownerOperator == owner)
        #expect(catalogue.identities["invalid"] == nil)
    }

    @Test @MainActor func configurableRefreshAgeMigratesAndPersistsIndependentlyOfPositionAge() throws {
        let name = "identity-refresh-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = RadarPreferences(defaults: defaults)
        #expect(preferences.load().identityRefreshDays == 7)
        #expect(try JSONDecoder().decode(RadarSettings.self, from: Data(#"{"source":"local"}"#.utf8)).identityRefreshDays == 7)
        var settings = RadarSettings()
        settings.identityRefreshDays = 0.5
        preferences.save(settings)
        #expect(preferences.load().identityRefreshDays == 0.5)
        #expect(preferences.load().staleSeconds == 15 && preferences.load().removalSeconds == 60)
        settings.identityRefreshDays = .nan
        #expect(settings.validated().identityRefreshDays == 7)
    }
}
