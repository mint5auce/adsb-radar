import Foundation
import Testing
@testable import RadarCore

struct MapImportTests {
    @Test func publishedRouteResolvesItsEndpointsWithoutInventingWidth() throws {
        let url = try #require(Bundle.module.url(forResource: "nats-route", withExtension: "xml"))
        let snapshot = try NATSImporter.parse(Data(contentsOf: url), effectiveDate: "2026-10-01")
        let route = try #require(snapshot.features.first)
        #expect(snapshot.features.count == 1)
        #expect(route.kind == .route)
        #expect(route.paths.first?.first?.latitude == 52.225)
        #expect(route.paths.first?.last?.latitude == 52.35925)
        #expect(route.lower.description == "FL 245")
        #expect(route.upper.description == "FL 460")
        #expect(route.details.contains { $0.title == "WIDTH" && $0.value == "UNKNOWN" })
        #expect(route.routeEndpoints?.map(\.name) == ["BEDFO", "EBOTO"])
        #expect(route.routeEndpoints?.first?.coordinate == route.paths.first?.first)
    }
    @Test func publishedRegionsRetainClosedCurvedBoundaries() throws {
        let url = try #require(Bundle.module.url(forResource: "nats-airspace", withExtension: "xml"))
        let snapshot = try NATSImporter.parse(Data(contentsOf: url), effectiveDate: "2026-10-01")
        #expect(snapshot.features.count == 3)
        let circle = try #require(snapshot.features.first { $0.name == "EDINBURGH CTR" })
        #expect(circle.paths[0].count > 100)
        #expect(circle.paths[0].first == circle.paths[0].last)
        let center = GeographicCoordinate(latitude: 55.95, longitude: -3.3725)!
        #expect(circle.paths[0].allSatisfy {
            let point = ReceiverProjection(origin: center).project($0)
            return abs(hypot(point.east, point.north) - 10) < 0.000001
        })
        #expect(snapshot.features.allSatisfy { $0.kind == .airspace })
        #expect(snapshot.features.allSatisfy { $0.paths.allSatisfy { $0.first == $0.last } })
        #expect(snapshot.features.contains { $0.name == "CARDIFF CTA 1" && $0.paths[0].count > 30 })
    }
    @Test func signedArcSweepAndUnsupportedGeometryAreNotSilentlyChanged() throws {
        let xml = """
        <fixture><Airspace><identifier>arc-test</identifier><timeSlice><AirspaceTimeSlice>
        <interpretation>BASELINE</interpretation><type>CTR</type><name>QUARTER ARC</name>
        <geometryComponent><AirspaceGeometryComponent><operation>BASE</operation><theAirspaceVolume><AirspaceVolume>
        <horizontalProjection><Surface><patches><PolygonPatch><exterior><Ring><curveMember><Curve><segments>
        <ArcByCenterPoint><pos>0 0</pos><radius uom="[nmi_i]">60.040460732619</radius><startAngle uom="deg">90</startAngle><endAngle uom="deg">0</endAngle></ArcByCenterPoint>
        <GeodesicString><pos>1 0</pos><pos>0 1</pos></GeodesicString>
        </segments></Curve></curveMember></Ring></exterior></PolygonPatch></patches></Surface></horizontalProjection>
        </AirspaceVolume></theAirspaceVolume></AirspaceGeometryComponent></geometryComponent>
        </AirspaceTimeSlice></timeSlice></Airspace></fixture>
        """
        let feature = try #require(NATSImporter.parse(Data(xml.utf8), effectiveDate: "2026-10-01").features.first)
        #expect(feature.paths[0].allSatisfy { $0.latitude >= -0.00001 && $0.longitude >= -0.00001 })
        #expect(feature.paths[0].contains { $0.latitude > 0.65 && $0.longitude > 0.65 })
        let unsupported = xml.replacingOccurrences(of: "ArcByCenterPoint", with: "UnsupportedCurve")
        #expect(throws: MapDataError.self) { try NATSImporter.parse(Data(unsupported.utf8), effectiveDate: "2026-10-01") }
    }
}
