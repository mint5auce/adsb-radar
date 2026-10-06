import CryptoKit
import Foundation

/// Network and import work is isolated from the display's main actor.
public actor MapUpdateService {
    public typealias Download = @Sendable (URL) async throws -> Data
    private let download: Download
    public init(download: @escaping Download = MapUpdateService.downloadURL) { self.download = download }
    public static let natsPage = URL(string: "https://nats-uk.ead-it.com/cms-nats/opencms/en/Publications/digital-datasets/")!

    public func fetch(_ provider: MapProvider, currentDate: String?, today: String = MapUpdateService.today()) async throws -> MapSnapshot? {
        switch provider {
        case .nats:
            let page = try await download(Self.natsPage)
            guard let html = String(data: page, encoding: .utf8) else { throw MapDataError.invalid("Invalid NATS catalogue") }
            let cycle = try Self.natsCycle(in: html, today: today)
            if let currentDate, cycle.date <= currentDate { return nil }
            let archive = try await download(cycle.url)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("dataset.zip")
            try archive.write(to: file)
            let entriesData = try Self.unzip(["-Z1", file.path], maximumBytes: 100_000)
            guard let entries = String(data: entriesData, encoding: .utf8) else { throw MapDataError.invalid("Invalid NATS archive") }
            let basename = "EG_AIP_DS_FULL_" + cycle.date.replacingOccurrences(of: "-", with: "")
            let names = entries.split(whereSeparator: \.isNewline).map(String.init)
            func member(_ suffix: String) throws -> String {
                let matches = names.filter { URL(fileURLWithPath: $0).lastPathComponent == basename + suffix }
                guard matches.count == 1, let name = matches.first else { throw MapDataError.invalid("Missing or ambiguous NATS archive member") }
                return name
            }
            let xml = try Self.unzip(["-p", file.path, try member(".xml")], maximumBytes: 150_000_000)
            let checksum = try Self.unzip(["-p", file.path, try member(".sha256")], maximumBytes: 10_000)
            try Self.verify(xml, checksum: checksum)
            let snapshot = try NATSImporter.parse(xml, effectiveDate: cycle.date)
            guard snapshot.features.contains(where: { $0.kind == .route }), snapshot.features.contains(where: { $0.kind == .airspace }) else {
                throw MapDataError.invalid("Incomplete NATS layers")
            }
            return snapshot
        case .ourAirports:
            let data = try await download(URL(string: "https://davidmegginson.github.io/ourairports-data/airports.csv")!)
            return try AirportImporter.parse(data, snapshotDate: today)
        }
    }

    public nonisolated static func today() -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
    public nonisolated static func natsCycle(in html: String, today: String) throws -> (date: String, url: URL) {
        let expression = try NSRegularExpression(pattern: #"["']([^"']*EG_AIP_DS_(\d{8})_XML\.zip)["']"#)
        let source = html as NSString
        let cycles = expression.matches(in: html, range: NSRange(location: 0, length: source.length)).compactMap { match -> (String, URL)? in
            let digits = source.substring(with: match.range(at: 2))
            let date = String(digits.prefix(4)) + "-" + digits.dropFirst(4).prefix(2) + "-" + digits.suffix(2)
            guard MapSnapshot.validDate(date), date <= today,
                  let url = URL(string: source.substring(with: match.range(at: 1)), relativeTo: natsPage)?.absoluteURL,
                  url.scheme == "https", url.host == natsPage.host else { return nil }
            return (date, url)
        }
        guard let chosen = cycles.max(by: { $0.0 < $1.0 }) else { throw MapDataError.invalid("No currently effective NATS dataset found") }
        return chosen
    }
    public nonisolated static func verify(_ data: Data, checksum: Data) throws {
        guard let expected = String(data: checksum, encoding: .utf8)?.split(whereSeparator: \.isWhitespace).first,
              expected.count == 64, expected.allSatisfy(\.isHexDigit),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected.lowercased() else {
            throw MapDataError.invalid("NATS checksum did not match")
        }
    }
    public nonisolated static func downloadURL(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 90
        let (file, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes > 0, bytes <= 150_000_000 else {
            throw MapDataError.invalid("Map download failed or exceeded its size limit")
        }
        return try Data(contentsOf: file)
    }
    private static func unzip(_ arguments: [String], maximumBytes: Int) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            guard data.count + chunk.count <= maximumBytes else {
                process.terminate(); process.waitUntilExit(); throw MapDataError.invalid("NATS archive member is too large")
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MapDataError.invalid("Could not read NATS archive") }
        return data
    }
}
