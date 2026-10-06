import Foundation
import Testing
@testable import RadarCore

struct MapSnapshotStoreTests {
    @Test func validatedReplacementSurvivesRestartAndFailedReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try #require(Bundle.module.url(forResource: "nats-route", withExtension: "xml"))
        let snapshot = try NATSImporter.parse(Data(contentsOf: fixture), effectiveDate: "2026-10-01")
        let store = MapSnapshotStore(directory: directory)
        try await store.install(snapshot)
        var invalid = snapshot; invalid.schemaVersion = 999
        await #expect(throws: MapDataError.self) { try await store.install(invalid) }
        let restarted = MapSnapshotStore(directory: directory)
        #expect(try await restarted.cached(.nats) == snapshot)
        // An incomplete staging file cannot replace the active generation.
        try Data("partial".utf8).write(to: directory.appendingPathComponent("interrupted.tmp"))
        #expect(try await restarted.cached(.nats) == snapshot)
    }
    @Test func currentCycleDiscoveryExcludesFutureAndRejectsMissingLinks() throws {
        let page = "<a href='/ICAO_AIP/EG_AIP_DS_20261001_XML.zip'>current</a><a href='/ICAO_AIP/EG_AIP_DS_20261029_XML.zip'>future</a>"
        let cycle = try MapUpdateService.natsCycle(in: page, today: "2026-10-06")
        #expect(cycle.date == "2026-10-01")
        #expect(throws: MapDataError.self) { try MapUpdateService.natsCycle(in: page, today: "2026-09-01") }
    }
}
