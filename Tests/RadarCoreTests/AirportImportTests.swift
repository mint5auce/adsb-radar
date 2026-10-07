import Foundation
import Testing
@testable import RadarCore

struct AirportImportTests {
    @Test func sourceSizesAndScheduledServiceRemainAvailableOffline() throws {
        let csv = """
        id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,iso_country,icao_code,iata_code,gps_code,local_code,scheduled_service
        1,SMALL,small_airport,Small field,52,-1,100,GB,,,,,no
        2,MEDIUM,medium_airport,Regional airport,52,-1,100,GB,,,,,yes
        3,LARGE,large_airport,Major airport,52,-1,100,GB,,,,,
        4,UNKNOWN,medium_airport,Unknown service,52,-1,100,GB,,,,,unexpected
        """
        let imported = try AirportImporter.parse(Data(csv.utf8), snapshotDate: "2026-10-06")
        let snapshot = try JSONDecoder().decode(MapSnapshot.self, from: JSONEncoder().encode(imported))
        let small = try #require(snapshot.features.first { $0.id == "airport:1" })
        let medium = try #require(snapshot.features.first { $0.id == "airport:2" })
        let large = try #require(snapshot.features.first { $0.id == "airport:3" })
        let unknown = try #require(snapshot.features.first { $0.id == "airport:4" })
        #expect(small.airportSize == .small && small.scheduledService == false)
        #expect(medium.airportSize == .medium && medium.scheduledService == true)
        #expect(large.airportSize == .large && large.scheduledService == nil)
        #expect(unknown.scheduledService == nil)
        #expect(medium.inspectionDetails.contains(MapDetail("SCHEDULED SERVICE", "YES")))
        #expect(large.inspectionDetails.contains(MapDetail("SCHEDULED SERVICE", "UNKNOWN")))
    }

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
