import Foundation

public enum AirportImporter {
    public static func parse(_ data: Data, snapshotDate: String) throws -> MapSnapshot {
        guard let text = String(data: data, encoding: .utf8) else { throw MapDataError.invalid("Airport data is not UTF-8") }
        let rows = try CSV.rows(text)
        guard let header = rows.first, Set(header).count == header.count,
              ["id", "ident", "type", "name", "latitude_deg", "longitude_deg", "iso_country", "icao_code", "iata_code", "gps_code", "local_code", "elevation_ft"].allSatisfy(header.contains) else {
            throw MapDataError.invalid("Unsupported airport columns")
        }
        var features: [MapFeature] = []
        for row in rows.dropFirst() {
            guard row.count == header.count else { throw MapDataError.invalid("Incomplete airport row") }
            let fields = Dictionary(uniqueKeysWithValues: zip(header, row))
            func field(_ key: String) -> String? { fields[key].flatMap { $0.isEmpty ? nil : $0 } }
            guard ["GB", "GG", "JE", "IM"].contains(field("iso_country") ?? ""),
                  let type = field("type"), ["large_airport", "medium_airport", "small_airport"].contains(type) else { continue }
            guard let id = field("id"), let ident = field("ident"), let name = field("name"),
                  let lat = field("latitude_deg").flatMap(Double.init), let lon = field("longitude_deg").flatMap(Double.init),
                  let coordinate = GeographicCoordinate(latitude: lat, longitude: lon) else { throw MapDataError.invalid("Invalid airport position or identity") }
            let code = field("icao_code") ?? field("iata_code") ?? field("local_code") ?? ident
            var feature = MapFeature(id: "airport:" + id, kind: .airport, name: name, label: code, paths: [[coordinate]])
            feature.smallAirport = type == "small_airport"
            feature.details = [MapDetail("ICAO", field("icao_code") ?? "UNKNOWN"), MapDetail("IATA", field("iata_code") ?? "UNKNOWN"),
                MapDetail("GPS CODE", field("gps_code") ?? "UNKNOWN"), MapDetail("LOCAL CODE", field("local_code") ?? "UNKNOWN"),
                MapDetail("SOURCE IDENTIFIER", ident), MapDetail("TYPE", type.replacingOccurrences(of: "_", with: " ").uppercased()),
                MapDetail("ELEVATION", field("elevation_ft").map { $0 + " FT MSL" } ?? "UNKNOWN")]
            features.append(feature)
        }
        let snapshot = MapSnapshot(provider: .ourAirports, date: snapshotDate,
            sourceURL: "https://ourairports.com/data/", terms: "OurAirports data is in the public domain.",
            coverage: "United Kingdom, Guernsey, Jersey and Isle of Man", features: features.sorted { $0.id < $1.id })
        try snapshot.validate()
        return snapshot
    }
}

private enum CSV {
    static func rows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, afterQuote = false
        // A state machine preserves commas, escaped quotes and newlines inside names.
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var index = 0
        while index < characters.count {
            let char = characters[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; afterQuote = true }
                } else { field.append(char) }
            } else if char == "," || char == "\n" {
                row.append(field); field = ""; afterQuote = false
                if char == "\n" { if row != [""] { rows.append(row) }; row = [] }
            } else if char == "\"", field.isEmpty, !afterQuote { quoted = true }
            else {
                guard !afterQuote, char != "\"" else { throw MapDataError.invalid("Malformed airport CSV") }
                field.append(char)
            }
            index += 1
        }
        guard !quoted else { throw MapDataError.invalid("Truncated airport CSV") }
        if !row.isEmpty || !field.isEmpty || afterQuote { row.append(field); rows.append(row) }
        return rows
    }
}
