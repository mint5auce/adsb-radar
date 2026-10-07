import Foundation
import Testing
@testable import RadarCore

struct DecodingTests {
    @Test func optionalLocalDatabaseDetailsKeepLocalProvenanceWithoutPositions() throws {
        let json = Data(#"{"now":1000,"aircraft":[{"hex":"ABC123","r":" G-TEST ","t":"B77W","desc":"BOEING 777-300ER","ownOp":"Example Airways"},{"hex":"~abc123","r":"OTHER","desc":"OTHER","ownOp":"OTHER","category":"A1"}]}"#.utf8)
        let snapshot = try ReceiverSnapshot.decode(json)
        #expect(snapshot.identities.count == 2)
        let identity = try #require(snapshot.identities.first)
        #expect(identity.registration == "G-TEST" && identity.modelDescription == "BOEING 777-300ER")
        #expect(identity.ownerOperator == "Example Airways" && identity.provider == "LOCAL RTL-SDR")
        #expect(identity.updatedAt == Date(timeIntervalSince1970: 1000))
        #expect(snapshot.identities.last?.modelDescription == nil && snapshot.identities.last?.ownerOperator == nil)
        #expect(snapshot.heardWithoutPosition == 2)
    }
    @Test func decodesPositionObservationTimeRatherThanMessageAge() throws {
        let json = Data(#"{"now":1000,"aircraft":[{"hex":"ABC123","flight":" BA123 ","lat":51.5,"lon":-0.1,"seen":0.1,"seen_pos":3}]}"#.utf8)
        let snapshot = try ReceiverSnapshot.decode(json)
        let aircraft = try #require(snapshot.observations.first)
        #expect(aircraft.address == "abc123")
        #expect(aircraft.callsign == "BA123")
        #expect(aircraft.position == GeographicCoordinate(latitude: 51.5, longitude: -0.1))
        #expect(aircraft.positionTime == Date(timeIntervalSince1970: 997))
    }

    @Test func missingAndMalformedAircraftDoNotHideValidContacts() throws {
        let json = Data(#"{"now":1000,"aircraft":[null,{"hex":"abcdef","alt_baro":"ground"},{"hex":"abc123","lat":true,"lon":1,"seen_pos":0},{"hex":"abc456","lat":52,"lon":-2,"seen_pos":1,"alt_baro":32000}]}"#.utf8)
        let snapshot = try ReceiverSnapshot.decode(json)
        #expect(snapshot.observations.count == 3)
        #expect(snapshot.heardWithoutPosition == 2)
        #expect(snapshot.observations.first?.altitude == .ground)
        #expect(snapshot.observations.last?.altitude == .feet(32000))
        #expect(snapshot.observations.last?.position != nil)
    }
}
