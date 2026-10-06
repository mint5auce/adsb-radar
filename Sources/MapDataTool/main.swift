import Foundation
import RadarCore

@main struct MapDataTool {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "refresh" {
            let directory = URL(fileURLWithPath: args[2])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let updater = MapUpdateService()
            for provider in MapProvider.allCases {
                guard let snapshot = try await updater.fetch(provider, currentDate: nil) else { continue }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(snapshot).write(to: directory.appendingPathComponent(provider == .nats ? "NATSMap.json" : "AirportsMap.json"), options: .atomic)
                print("Verified \(snapshot.features.count) features from \(provider.title), \(snapshot.date)")
            }
            return
        }
        guard args.count == 5, ["nats", "airports"].contains(args[1]) else {
            throw MapDataError.invalid("Usage: swift run MapDataTool nats|airports input.xml|csv YYYY-MM-DD output.json")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        let snapshot = try args[1] == "nats" ? NATSImporter.parse(data, effectiveDate: args[3]) : AirportImporter.parse(data, snapshotDate: args[3])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
        print("Imported \(snapshot.features.count) map features from \(snapshot.provider.title), \(snapshot.date)")
    }
}
