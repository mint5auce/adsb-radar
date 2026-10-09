import Foundation
import Testing
import RadarCore

struct AircraftPhotoProviderTests {
    @Test func malformedOrUntrustedPhotoMetadataIsRejected() async throws {
        for payload in [
            "{}",
            #"{"error":"temporarily unavailable"}"#,
            photoJSON.replacingOccurrences(of: "Example Photographer", with: " "),
            photoJSON.replacingOccurrences(of: "https://t.plnspttrs.net", with: "http://t.plnspttrs.net"),
            photoJSON.replacingOccurrences(of: "https://www.planespotters.net", with: "https://example.com"),
            photoJSON.replacingOccurrences(of: "420", with: "0")
        ] {
            let provider = PlanespottersPhotoProvider(scheduler: OnlineRequestScheduler(transport: FixedPhotoTransport(
                response: OnlineHTTPResponse(data: Data(payload.utf8)))))
            await #expect(throws: (any Error).self) { try await provider.photo(address: "406b90", registration: nil) }
        }
    }

    @Test func hexMissFallsBackToRegistrationAndPreservesCreditAndURLs() async throws {
        let transport = PhotoTransport()
        let provider = PlanespottersPhotoProvider(scheduler: OnlineRequestScheduler(transport: transport))
        let photo = try #require(try await provider.photo(address: "406B90", registration: "G-EZWX"))
        #expect(photo.photographer == "Example Photographer")
        #expect(photo.imageURL.absoluteString == "https://t.plnspttrs.net/example_280.jpg")
        #expect(photo.pageURL.absoluteString == "https://www.planespotters.net/photo/123?utm_source=api")
        #expect(await transport.paths == ["/pub/photos/hex/406b90", "/pub/photos/reg/G-EZWX"])
    }
}

private struct FixedPhotoTransport: OnlineHTTPTransport {
    let response: OnlineHTTPResponse
    func get(_ url: URL) async throws -> OnlineHTTPResponse { response }
}

private actor PhotoTransport: OnlineHTTPTransport {
    var paths: [String] = []
    func get(_ url: URL) async throws -> OnlineHTTPResponse {
        paths.append(url.path)
        return OnlineHTTPResponse(data: Data((url.path.contains("/hex/") ? #"{"photos":[]}"# : photoJSON).utf8))
    }
}

private let photoJSON = #"""
{"photos":[{"id":"123","thumbnail_large":{"src":"https://t.plnspttrs.net/example_280.jpg","size":{"width":420,"height":280}},"link":"https://www.planespotters.net/photo/123?utm_source=api","photographer":"Example Photographer"}]}
"""#
