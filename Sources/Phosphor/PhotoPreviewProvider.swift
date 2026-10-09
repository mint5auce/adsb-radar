#if DEBUG
import Foundation
import RadarCore

/// Opt-in local artwork for native verification; no provider photographs or network requests.
struct PhotoPreviewProvider: AircraftPhotoProvider {
    func photo(address: String, registration: String?) async throws -> AircraftPhoto? {
        guard CommandLine.arguments.contains("--preview-photos"), address != "def456" else { return nil }
        if address == "4067ce" { try await Task.sleep(for: .seconds(6)) }
        return AircraftPhoto(imageURL: URL(string: "https://example.com/illustrative-photo.png")!,
            pageURL: URL(string: "https://www.planespotters.net/photo/api")!,
            photographer: "Illustrative test fixture", width: 1536, height: 1024)
    }

    func image(for photo: AircraftPhoto) async throws -> Data {
        guard let index = CommandLine.arguments.firstIndex(of: "--photo-fixture"),
              CommandLine.arguments.indices.contains(index + 1) else { throw AircraftPhotoError.invalidResponse }
        return try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    }
}
#endif
