import Foundation

public struct AircraftPhoto: Equatable, Sendable {
    public let imageURL: URL
    public let pageURL: URL
    public let photographer: String
    public let width: Int
    public let height: Int

    public init(imageURL: URL, pageURL: URL, photographer: String, width: Int, height: Int) {
        self.imageURL = imageURL
        self.pageURL = pageURL
        self.photographer = photographer
        self.width = width
        self.height = height
    }
}

public protocol AircraftPhotoProvider: Sendable {
    func photo(address: String, registration: String?) async throws -> AircraftPhoto?
    func image(for photo: AircraftPhoto) async throws -> Data
}

public enum AircraftPhotoError: Error {
    case invalidResponse
    case http(Int, retryAfter: Date?)
}

/// Direct, keyless thumbnail access. The shared allowance is independent of position updates.
public struct PlanespottersPhotoProvider: AircraftPhotoProvider {
    private static let sharedScheduler = OnlineRequestScheduler(transport: URLSessionOnlineTransport(
        userAgent: "Phosphor/0.2 (+https://github.com/mint5auce/phosphor)"))
    private let scheduler: OnlineRequestScheduler

    public init(scheduler: OnlineRequestScheduler? = nil) {
        self.scheduler = scheduler ?? Self.sharedScheduler
    }

    public func photo(address: String, registration: String?) async throws -> AircraftPhoto? {
        if AircraftIdentityCatalogue.isICAO(address.lowercased()),
           let match = try await lookup("hex", value: address.lowercased()) { return match }
        if let registration = registration?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
           registration.range(of: "^[A-Z0-9][A-Z0-9-]{1,14}$", options: .regularExpression) != nil {
            return try await lookup("reg", value: registration)
        }
        return nil
    }

    private func lookup(_ kind: String, value: String) async throws -> AircraftPhoto? {
        let url = URL(string: "https://api.planespotters.net/pub/photos/")!
            .appendingPathComponent(kind).appendingPathComponent(value)
        let response = try await scheduler.get(url, priority: .identity)
        guard (200..<300).contains(response.status) else {
            throw AircraftPhotoError.http(response.status, retryAfter: response.retryAfter)
        }
        let payload = try JSONDecoder().decode(Payload.self, from: response.data)
        guard payload.error == nil, let photos = payload.photos else { throw AircraftPhotoError.invalidResponse }
        guard let first = photos.first else { return nil }
        let thumbnail = first.thumbnail_large
        guard let imageURL = URL(string: thumbnail.src), imageURL.scheme == "https",
              let pageURL = URL(string: first.link), pageURL.scheme == "https",
              Self.belongsToProvider(imageURL, domains: ["planespotters.net", "plnspttrs.net"]),
              Self.belongsToProvider(pageURL, domains: ["planespotters.net"]),
              !first.photographer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              thumbnail.size.width > 0, thumbnail.size.height > 0 else { throw AircraftPhotoError.invalidResponse }
        return AircraftPhoto(imageURL: imageURL, pageURL: pageURL, photographer: first.photographer,
                             width: thumbnail.size.width, height: thumbnail.size.height)
    }

    private static func belongsToProvider(_ url: URL, domains: [String]) -> Bool {
        guard let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public func image(for photo: AircraftPhoto) async throws -> Data {
        let response = try await scheduler.get(photo.imageURL, priority: .identity)
        guard (200..<300).contains(response.status) else {
            throw AircraftPhotoError.http(response.status, retryAfter: response.retryAfter)
        }
        return response.data
    }

    private struct Payload: Decodable {
        let photos: [Photo]?
        let error: String?
    }
    private struct Photo: Decodable {
        let thumbnail_large: Thumbnail
        let link: String
        let photographer: String
    }
    private struct Thumbnail: Decodable {
        let src: String
        let size: Size
    }
    private struct Size: Decodable {
        let width: Int
        let height: Int
    }
}
