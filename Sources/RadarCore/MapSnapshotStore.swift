import Foundation

/// One atomic file per provider keeps routes and airspace in the same generation.
public actor MapSnapshotStore {
    private let directory: URL
    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ADSB Radar/MapData")) { self.directory = directory }

    public func cached(_ provider: MapProvider) throws -> MapSnapshot? {
        let file = directory.appendingPathComponent(provider.rawValue + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot = try JSONDecoder().decode(MapSnapshot.self, from: Data(contentsOf: file))
        try snapshot.validate()
        guard snapshot.provider == provider else { throw MapDataError.invalid("Wrong cached map provider") }
        return snapshot
    }
    public func install(_ snapshot: MapSnapshot) throws {
        try snapshot.validate()
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(snapshot.provider.rawValue + ".json"), options: .atomic)
    }
}
