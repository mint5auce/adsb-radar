import Foundation
import Testing
@testable import RadarCore

struct AirportImportTests {
    @Test func quotedNamesMissingCodesAndExclusions() throws {
        let csv = """
        id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,iso_country,icao_code,iata_code,gps_code,local_code
        1,GB-1,small_airport,"Field, North",52,-1,,GB,,,,ABC
        2,EGLL,large_airport,Heathrow,51.47,-0.45,83,GB,EGLL,LHR,EGLL,
        3,OLD,closed,Old field,52,-1,100,GB,,,,
        4,HEL,heliport,Hospital,52,-1,100,GB,,,,
        5,FR1,medium_airport,France,49,2,100,FR,,,,
        """
        let snapshot = try AirportImporter.parse(Data(csv.utf8), snapshotDate: "2026-10-06")
        #expect(snapshot.features.count == 2)
        let field = try #require(snapshot.features.first { $0.id == "airport:1" })
        #expect(field.name == "Field, North")
        #expect(field.label == "ABC")
        #expect(field.smallAirport)
        #expect(field.details.contains(MapDetail("ICAO", "UNKNOWN")))
        #expect(field.details.contains(MapDetail("ELEVATION", "UNKNOWN")))
    }
}
