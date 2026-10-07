import Foundation
import Testing
import RadarCore

struct AircraftIdentifierTests {
    @Test func registrationIsPrimaryAndOtherIdentifiersRemainAvailable() {
        let identity = AircraftIdentity(registration: AircraftIdentityValue(value: "G-RASA", provider: "fixture", updatedAt: .now))
        let identifiers = AircraftIdentifiers(observation: AircraftObservation(address: "400f18", callsign: "AOS57"),
            identity: identity, preferred: .registration)
        #expect(identifiers.primary == "G-RASA")
        #expect(identifiers.secondary == ["AOS57", "400F18"])
    }
    @Test func fallbackOrdersIgnoreBlankValuesAndAvoidDuplicateDetails() {
        let observation = AircraftObservation(address: "400f18", callsign: " AOS57 ")
        let identity = AircraftIdentity(registration: AircraftIdentityValue(value: " G-RASA ", provider: "fixture", updatedAt: .now))
        let callsignFirst = AircraftIdentifiers(observation: observation, identity: identity, preferred: .callsign)
        #expect(callsignFirst.primary == "AOS57")
        #expect(callsignFirst.secondary == ["G-RASA", "400F18"])
        #expect(AircraftIdentifiers(observation: observation, identity: nil, preferred: .registration).primary == "AOS57")
        let blank = AircraftObservation(address: "400f18", callsign: " \n ")
        #expect(AircraftIdentifiers(observation: blank, identity: identity, preferred: .callsign).primary == "G-RASA")
        let blankIdentity = AircraftIdentity(registration: AircraftIdentityValue(value: " ", provider: "fixture", updatedAt: .now))
        let unknown = AircraftIdentifiers(observation: blank, identity: blankIdentity, preferred: .registration)
        #expect(unknown.primary == "400F18" && unknown.secondary.isEmpty)
        let same = AircraftObservation(address: "400f18", callsign: "G-RASA")
        #expect(AircraftIdentifiers(observation: same, identity: identity, preferred: .callsign).secondary == ["400F18"])
        let addressCallsign = AircraftObservation(address: "400f18", callsign: "400f18")
        #expect(AircraftIdentifiers(observation: addressCallsign, identity: nil, preferred: .callsign).secondary.isEmpty)
    }

    @Test func newAndOlderPreferencesDefaultToRegistrationAndPersistEitherChoice() throws {
        #expect(RadarSettings.firstLaunch.aircraftIdentifier == .registration)
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(RadarSettings.self, from: Data(#"{"initialRadiusNM":75}"#.utf8))
        #expect(legacy.aircraftIdentifier == .registration && legacy.initialRadiusNM == 75)
        for preference in AircraftIdentifierPreference.allCases {
            var settings = legacy
            settings.aircraftIdentifier = preference
            let restored = try decoder.decode(RadarSettings.self, from: JSONEncoder().encode(settings))
            #expect(restored == settings)
        }
    }

}
