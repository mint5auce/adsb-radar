import Foundation

public protocol AircraftIdentityStorage: Sendable {
    func load() async throws -> [String: AircraftIdentity]
    func save(_ identities: [String: AircraftIdentity]) async throws
}

/// Disk work is serialized off the display actor. The cache contains identity fields only.
public actor FileAircraftIdentityStorage: AircraftIdentityStorage {
    private struct Document: Codable {
        let version: Int
        let identities: [String: AircraftIdentity]
    }
    private let url: URL

    public init(url: URL = FileAircraftIdentityStorage.defaultURL) { self.url = url }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("dev.mint5auce.phosphor", isDirectory: true)
            .appendingPathComponent("aircraft-identities.json")
    }

    public func load() throws -> [String: AircraftIdentity] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch CocoaError.fileReadNoSuchFile { return [:] }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        var catalogue = AircraftIdentityCatalogue()
        catalogue.restore(document.identities)
        return catalogue.identities
    }

    public func save(_ identities: [String: AircraftIdentity]) throws {
        var catalogue = AircraftIdentityCatalogue()
        catalogue.restore(identities)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(version: 1, identities: catalogue.identities))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
