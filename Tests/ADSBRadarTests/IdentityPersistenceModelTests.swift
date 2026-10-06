import Foundation
import Testing
import RadarCore
@testable import ADSBRadar

struct IdentityPersistenceModelTests {
    @Test @MainActor func restartUsesFileCacheOfflineWithRefreshDisabled() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("identities.json")
        var settings = localSettings()
        let first = RadarModel(sources: [.local: ControlledSource(addresses: ["abc123"], source: "LOCAL")],
            provider: IdentityFixtureProvider(), identityStorage: FileAircraftIdentityStorage(url: url),
            initialSettings: settings, defaults: isolatedDefaults())
        first.start()
        try await eventually { first.identities["abc123"]?.complete == true }
        let identity = first.identities["abc123"]
        await first.shutdown()
        settings.enrichIdentities = false
        let offline = IdentityFixtureProvider(failing: true)
        let second = RadarModel(sources: [.local: ControlledSource(addresses: ["abc123"], source: "LOCAL")],
            provider: offline, identityStorage: FileAircraftIdentityStorage(url: url),
            initialSettings: settings, defaults: isolatedDefaults())
        second.start()
        try await eventually { second.identities["abc123"] != nil && !second.contacts.isEmpty }
        second.selectedAddress = "abc123"
        #expect(second.selectedIdentity == identity)
        #expect(second.selectedContact?.observation.source == "LOCAL")
        #expect(await offline.requests.isEmpty)
        await second.shutdown()
    }

    @Test @MainActor func expiredCacheSurvivesOfflineFailureWithoutQueryingUnseenEntries() async throws {
        let saved = cachedIdentity(updatedAt: Date.now.addingTimeInterval(-8 * 86400))
        let provider = IdentityFixtureProvider(failing: true)
        let model = RadarModel(sources: [.local: ControlledSource(addresses: ["abc123"], source: "LOCAL")],
            provider: provider, identityStorage: MemoryIdentityStorage(values: ["abc123": saved, "bbb222": saved]),
            initialSettings: localSettings(), defaults: isolatedDefaults())
        model.start()
        try await eventually { await provider.requests.count == 1 }
        model.selectedAddress = "abc123"
        try await Task.sleep(for: .milliseconds(700))
        #expect(model.selectedIdentity == saved)
        #expect(await provider.requests == [["abc123"]])
        #expect(model.statuses[.local] == .receiving)
        await model.shutdown()
    }

    @Test @MainActor func changingRefreshAgeRefreshesOnlyDueEncounteredDetails() async throws {
        let saved = cachedIdentity(updatedAt: Date.now.addingTimeInterval(-2 * 86400))
        let provider = IdentityFixtureProvider()
        var settings = localSettings()
        let model = RadarModel(sources: [.local: ControlledSource(addresses: ["abc123"], source: "LOCAL", fixedPositions: true)],
            provider: provider, identityStorage: MemoryIdentityStorage(values: ["abc123": saved, "bbb222": saved]),
            initialSettings: settings, defaults: isolatedDefaults())
        model.start()
        try await eventually { model.identities["abc123"] != nil && !model.contacts.isEmpty }
        try await Task.sleep(for: .milliseconds(600))
        #expect(await provider.requests.isEmpty)
        let position = model.contacts.first?.observation
        settings.identityRefreshDays = 1
        model.apply(settings)
        try await eventually { model.identities["abc123"]?.registration?.value == "G-TEST" }
        #expect(await provider.requests == [["abc123"]])
        #expect(model.identities["bbb222"] == saved)
        #expect(model.contacts.first?.observation == position)
        #expect(model.identities["abc123"]?.lastUpdated != saved.lastUpdated)
        await model.shutdown()
    }

    @Test @MainActor func unreadableAndUnwritableCacheDoesNotPreventReceptionOrEnrichment() async throws {
        let provider = IdentityFixtureProvider()
        let model = RadarModel(sources: [.local: ControlledSource(addresses: ["abc123"], source: "LOCAL")],
            provider: provider, identityStorage: MemoryIdentityStorage(failing: true),
            initialSettings: localSettings(), defaults: isolatedDefaults())
        model.start()
        try await eventually { model.identities["abc123"]?.complete == true }
        try await Task.sleep(for: .seconds(1.1))
        #expect(model.statuses[.local] == .receiving && model.contacts.count == 1)
        await model.shutdown()
        #expect(model.identities["abc123"]?.registration?.value == "G-TEST")
    }

    @MainActor private func localSettings() -> RadarSettings {
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        return settings
    }

    private func cachedIdentity(updatedAt: Date) -> AircraftIdentity {
        AircraftIdentity(registration: AircraftIdentityValue(value: "G-CACHED", provider: "adsb.fi", updatedAt: updatedAt),
                         aircraftType: AircraftIdentityValue(value: "A319", provider: "adsb.fi", updatedAt: updatedAt),
                         category: AircraftCategoryValue(value: .large, provider: "adsb.fi", updatedAt: updatedAt))
    }
}
