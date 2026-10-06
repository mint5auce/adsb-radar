import CryptoKit
import Foundation
import Testing
@testable import RadarCore

struct MapUpdateTests {
    @Test func checkedArchiveProducesConsistentProviderGeneration() async throws {
        let xml = try combinedFixture()
        let archive = try zip(xml, checksum: digest(xml))
        let service = MapUpdateService(download: { url in
            url.pathExtension == "zip" ? archive : Data("<a href='/EG_AIP_DS_20261001_XML.zip'>dataset</a>".utf8)
        })
        let snapshot = try #require(await service.fetch(.nats, currentDate: nil, today: "2026-10-06"))
        #expect(snapshot.features.filter { $0.kind == .route }.count == 1)
        #expect(snapshot.features.filter { $0.kind == .airspace }.count == 3)
        #expect(snapshot.date == "2026-10-01")
        #expect(try await service.fetch(.nats, currentDate: snapshot.date, today: "2026-10-06") == nil)
    }
    @Test func checksumAndReferenceFailuresRejectDownloadedReplacements() async throws {
        let xml = try combinedFixture()
        let wrong = try zip(xml, checksum: String(repeating: "0", count: 64))
        let service = MapUpdateService(download: { url in url.pathExtension == "zip" ? wrong : Data("<a href='/EG_AIP_DS_20261001_XML.zip'>dataset</a>".utf8) })
        await #expect(throws: MapDataError.self) { try await service.fetch(.nats, currentDate: nil, today: "2026-10-06") }
        let fixture = try #require(Bundle.module.url(forResource: "nats-route", withExtension: "xml"))
        let original = try String(contentsOf: fixture, encoding: .utf8)
        let broken = original.replacingOccurrences(of: "urn:uuid:", with: "urn:uuid:missing-")
        #expect(throws: MapDataError.self) { try NATSImporter.parse(Data(broken.utf8), effectiveDate: "2026-10-01") }
        #expect(throws: MapDataError.self) { try NATSImporter.parse(Data("<broken".utf8), effectiveDate: "2026-10-01") }
    }
    private func combinedFixture() throws -> Data {
        let strings = try ["nats-route", "nats-airspace"].map { name in
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml"))
            let text = try String(contentsOf: url, encoding: .utf8)
            return text.replacingOccurrences(of: #"<\?xml[^>]*\?>"#, with: "", options: .regularExpression)
        }
        return Data(("<fixture>" + strings.joined() + "</fixture>").utf8)
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func zip(_ xml: Data, checksum: String) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = "EG_AIP_DS_FULL_20261001"
        try xml.write(to: directory.appendingPathComponent(base + ".xml"))
        try Data((checksum + "  " + base + ".xml\n").utf8).write(to: directory.appendingPathComponent(base + ".sha256"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory; process.arguments = ["-q", "fixture.zip", base + ".xml", base + ".sha256"]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MapDataError.invalid("Fixture zip failed") }
        return try Data(contentsOf: directory.appendingPathComponent("fixture.zip"))
    }
}
