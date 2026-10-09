import AppKit
import Foundation
import Testing
import RadarCore
@testable import Phosphor

struct AircraftPhotoLookupTests {
    @Test @MainActor func lateImageCannotReturnAfterDisplayEnds() async throws {
        let provider = SuspendedImageProvider()
        let lookup = AircraftPhotoLookup(provider: provider)
        lookup.setVisible(true)
        lookup.select(address: "406b90", registration: nil, enabled: true)
        await provider.waitForImage()
        lookup.setExpanded(false)
        try await provider.completeImage()
        for _ in 0..<10 { await Task.yield() }
        #expect(lookup.image == nil)
        #expect(lookup.status == .available && !lookup.isExpanded)
        lookup.reset()
    }

    @Test @MainActor func metadataExpiresWithoutLosingManualDisclosureChoice() async throws {
        let provider = SuspendedPhotoProvider()
        let lookup = AircraftPhotoLookup(provider: provider, metadataLifetime: .milliseconds(30))
        lookup.select(address: "406b90", registration: nil, enabled: true)
        lookup.setExpanded(false)
        await provider.waitFor("406b90")
        await provider.complete("406b90")
        try await photoEventually { lookup.photo != nil }
        await provider.waitFor("406b90")
        #expect(lookup.photo == nil && lookup.status == .lookingUp)
        #expect(!lookup.isExpanded)
        lookup.reset()
        await provider.complete("406b90")
    }

    @Test @MainActor func manualCollapseWinsWhileMetadataLoadsAndNewSelectionResetsIt() async throws {
        let provider = SuspendedPhotoProvider()
        let lookup = AircraftPhotoLookup(provider: provider)
        lookup.select(address: "old123", registration: nil, enabled: true)
        lookup.setExpanded(false)
        await provider.waitFor("old123")
        await provider.complete("old123")
        try await photoEventually { lookup.photo != nil }
        #expect(!lookup.isExpanded)
        lookup.select(address: "new123", registration: nil, enabled: true)
        await provider.waitFor("new123")
        await provider.complete("new123")
        try await photoEventually { lookup.photo?.photographer == "new123" }
        #expect(lookup.isExpanded)
        lookup.reset()
    }

    @Test @MainActor func lateMetadataCannotReplaceAnotherAircraftOrDisabledState() async throws {
        let provider = SuspendedPhotoProvider()
        let lookup = AircraftPhotoLookup(provider: provider)
        lookup.select(address: "old123", registration: nil, enabled: true)
        await provider.waitFor("old123")
        lookup.select(address: "new123", registration: nil, enabled: true)
        await provider.waitFor("new123")
        await provider.complete("new123")
        try await photoEventually { lookup.photo?.photographer == "new123" }
        await provider.complete("old123")
        for _ in 0..<10 { await Task.yield() }
        #expect(lookup.photo?.photographer == "new123")
        lookup.select(address: "other1", registration: nil, enabled: true)
        await provider.waitFor("other1")
        lookup.select(address: "other1", registration: nil, enabled: false)
        await provider.complete("other1")
        for _ in 0..<10 { await Task.yield() }
        #expect(lookup.status == .disabled && lookup.photo == nil && lookup.image == nil)
    }

    @Test @MainActor func disclosureControlsImageLifetimeWithoutLosingMetadata() async throws {
        let lookup = AircraftPhotoLookup(provider: ImmediatePhotoProvider())
        lookup.setVisible(true)
        lookup.select(address: "406b90", registration: "G-EZWX", enabled: true)
        try await photoEventually { lookup.image != nil }
        #expect(lookup.isExpanded)
        #expect(lookup.photo?.photographer == "Fixture")
        lookup.setExpanded(false)
        #expect(lookup.image == nil)
        #expect(lookup.photo != nil)
        lookup.setVisible(false)
        lookup.setVisible(true)
        #expect(!lookup.isExpanded)
        lookup.setExpanded(true)
        try await photoEventually { lookup.image != nil }
        lookup.setVisible(false)
        #expect(lookup.image == nil)
        lookup.select(address: "406b90", registration: "G-EZWX", enabled: false)
        #expect(lookup.status == .disabled)
        #expect(lookup.image == nil && lookup.photo == nil)
    }
}

private actor SuspendedImageProvider: AircraftPhotoProvider {
    private var pending: CheckedContinuation<Data, Never>?
    func photo(address: String, registration: String?) async throws -> AircraftPhoto? { fixturePhoto }
    func image(for photo: AircraftPhoto) async throws -> Data {
        await withCheckedContinuation { pending = $0 }
    }
    func waitForImage() async {
        for _ in 0..<100 {
            if pending != nil { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Image request never arrived")
    }
    func completeImage() async throws {
        let bytes = try await ImmediatePhotoProvider().image(for: fixturePhoto)
        pending?.resume(returning: bytes)
        pending = nil
    }
}

private actor SuspendedPhotoProvider: AircraftPhotoProvider {
    private var pending: [String: CheckedContinuation<AircraftPhoto?, Never>] = [:]
    func photo(address: String, registration: String?) async throws -> AircraftPhoto? {
        await withCheckedContinuation { pending[address] = $0 }
    }
    func image(for photo: AircraftPhoto) async throws -> Data { Data() }
    func waitFor(_ address: String) async {
        for _ in 0..<100 {
            if pending[address] != nil { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Photo request never arrived")
    }
    func complete(_ address: String) {
        pending.removeValue(forKey: address)?.resume(returning: AircraftPhoto(imageURL: fixturePhoto.imageURL,
            pageURL: fixturePhoto.pageURL, photographer: address, width: 420, height: 280))
    }
}

private struct ImmediatePhotoProvider: AircraftPhotoProvider {
    func photo(address: String, registration: String?) async throws -> AircraftPhoto? { fixturePhoto }
    func image(for photo: AircraftPhoto) async throws -> Data {
        // A tiny valid PNG, generated fixture, never a provider photograph.
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1sAAAAASUVORK5CYII=")!
    }
}
private let fixturePhoto = AircraftPhoto(imageURL: URL(string: "https://example.com/photo.png")!,
    pageURL: URL(string: "https://example.com/original")!, photographer: "Fixture", width: 1, height: 1)

@MainActor private func photoEventually(_ condition: () -> Bool) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}
