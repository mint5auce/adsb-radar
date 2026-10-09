import AppKit
import Observation
import RadarCore

/// Owns one selection's metadata and only the image currently being displayed.
@MainActor @Observable
final class AircraftPhotoLookup {
    enum Status: Equatable { case lookingUp, available, unavailable, disabled }
    private(set) var status: Status = .lookingUp
    private(set) var photo: AircraftPhoto?
    private(set) var image: NSImage?
    private var manualExpansion: Bool?
    @ObservationIgnored private let provider: any AircraftPhotoProvider
    @ObservationIgnored private var selection: Selection?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var imageTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private let metadataLifetime: Duration
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var imageRevision = 0

    private struct Selection: Equatable {
        let address: String
        let registration: String?
        let enabled: Bool
    }

    init(provider: any AircraftPhotoProvider = PlanespottersPhotoProvider(), metadataLifetime: Duration = .seconds(86_400)) {
        self.provider = provider
        self.metadataLifetime = metadataLifetime
    }

    var isExpanded: Bool { manualExpansion ?? (status == .available) }

    func select(address: String, registration: String?, enabled: Bool) {
        let target = Selection(address: address, registration: registration, enabled: enabled)
        guard target != selection else { return }
        let newAircraft = target.address != selection?.address
        cancelRequests()
        if newAircraft { manualExpansion = nil }
        selection = target
        beginLookup(target)
    }

    private func beginLookup(_ target: Selection) {
        photo = nil
        status = target.enabled ? .lookingUp : .disabled
        guard target.enabled else { return }
        let revision = revision
        metadataTask = Task { [self] in
            do {
                let result = try await provider.photo(address: target.address, registration: target.registration)
                guard self.revision == revision, !Task.isCancelled else { return }
                photo = result
                status = result == nil ? .unavailable : .available
                loadImageIfDisplayed()
                expiryTask = Task { [weak self, metadataLifetime] in
                    do { try await Task.sleep(for: metadataLifetime) } catch { return }
                    guard let self, self.revision == revision else { return }
                    self.releaseImage()
                    self.beginLookup(target)
                }
            } catch {
                guard self.revision == revision, !Task.isCancelled else { return }
                status = .unavailable
            }
            metadataTask = nil
        }
    }

    func setExpanded(_ expanded: Bool) {
        manualExpansion = expanded
        updateImageDisplay()
    }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        updateImageDisplay()
    }

    func reset() {
        cancelRequests()
        selection = nil
        photo = nil
        manualExpansion = nil
        visible = false
        status = .lookingUp
    }

    private func updateImageDisplay() {
        if visible && isExpanded { loadImageIfDisplayed() }
        else { releaseImage() }
    }

    private func loadImageIfDisplayed() {
        guard visible, isExpanded, status == .available, let photo, image == nil, imageTask == nil else { return }
        let revision = imageRevision
        imageTask = Task {
            do {
                let data = try await provider.image(for: photo)
                guard imageRevision == revision, !Task.isCancelled else { return }
                guard let decoded = NSImage(data: data), decoded.isValid else { throw AircraftPhotoError.invalidResponse }
                image = decoded
            } catch {
                guard imageRevision == revision, !Task.isCancelled else { return }
                self.photo = nil
                status = .unavailable
            }
            imageTask = nil
        }
    }

    private func releaseImage() {
        imageRevision += 1
        imageTask?.cancel()
        imageTask = nil
        image = nil
    }

    private func cancelRequests() {
        revision += 1
        metadataTask?.cancel()
        metadataTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        releaseImage()
    }
}
