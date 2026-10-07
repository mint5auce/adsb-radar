import Foundation
import Testing
import RadarCore
@testable import Phosphor

struct AircraftIdentifierModelTests {
    @Test @MainActor func chooserTracksArrivingRegistrationAndSavedPreferenceWithoutChangingContact() async throws {
        let source = IdentifierSnapshotSource()
        let defaults = isolatedDefaults()
        var settings = RadarSettings()
        settings.receiver = SyntheticSource.exampleLocation
        settings.mode = .immediate
        settings.enrichIdentities = false
        let model = RadarModel(source: source, identityStorage: MemoryIdentityStorage(), initialSettings: settings, defaults: defaults)
        model.start()
        try await eventually { model.contacts.count == 1 }
        let point = CGPoint(x: model.viewportWidth / 2, y: model.viewportHeight / 2)
        #expect(model.objectChoices(at: point).first?.title == "AOS57")
        let openChoice = try #require(model.objectChoices(at: point).first)
        await source.supplyRegistration()
        try await eventually { model.identities["400f18"]?.registration != nil }
        #expect(model.objectChoices(at: point).first?.title == "G-RASA")
        #expect(model.refreshedChoice(openChoice)?.title == "G-RASA")
        #expect(model.objectChoices(at: point).first?.detail.contains("AOS57 / 400F18") == true)
        model.selectedAddress = "400f18"
        let contact = try #require(model.selectedContact)
        settings.aircraftIdentifier = .callsign
        model.apply(settings)
        #expect(model.objectChoices(at: point).first?.title == "AOS57")
        #expect(model.objectChoices(at: point).first?.detail.contains("G-RASA / 400F18") == true)
        #expect(model.refreshedChoice(openChoice)?.title == "AOS57")
        #expect(model.selectedAddress == "400f18" && model.selectedContact?.observation == contact.observation)
        #expect(RadarPreferences(defaults: defaults).load().aircraftIdentifier == .callsign)
        await model.shutdown()
    }
}

private actor IdentifierSnapshotSource: AircraftDataSource {
    private var registration: String?
    private let time = Date.now
    func supplyRegistration() { registration = "G-RASA" }
    func start(location: GeographicCoordinate?) async {}
    func stop() async {}
    func poll() async -> ReceptionReading {
        ReceptionReading(status: .receiving, snapshot: ReceiverSnapshot(observations: [
            AircraftObservation(address: "400f18", callsign: "AOS57", position: SyntheticSource.exampleLocation,
                positionTime: time, altitude: .feet(12000), source: "LOCAL")
        ], identities: registration.map { [AircraftIdentityUpdate(address: "400f18", registration: $0)] } ?? []))
    }
}
