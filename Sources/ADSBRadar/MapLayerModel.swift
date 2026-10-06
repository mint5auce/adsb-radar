import Foundation
import Observation
import RadarCore
import SwiftUI

struct ProjectedMapFeature {
    let feature: MapFeature
    let path: Path
    let anchor: CGPoint
    let endpoints: [CGPoint]
    let bounds: CGRect

    init(feature: MapFeature, lines: [[RadarPoint]]) {
        self.feature = feature
        var path = Path()
        for line in lines {
            for (index, point) in line.enumerated() {
                let position = CGPoint(x: point.east, y: point.north)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }
            if feature.kind == .airspace { path.closeSubpath() }
        }
        self.path = path
        let points = lines.first ?? []
        endpoints = [points.first, points.last].compactMap { $0 }.map { CGPoint(x: $0.east, y: $0.north) }
        let middle = points.isEmpty ? RadarPoint() : points[points.count / 2]
        anchor = CGPoint(x: middle.east, y: middle.north)
        bounds = path.boundingRect
    }

    func contains(_ point: CGPoint, tolerance: Double) -> Bool {
        if feature.kind == .airport { return hypot(point.x - anchor.x, point.y - anchor.y) <= tolerance }
        guard bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return false }
        if feature.kind == .airspace, path.contains(point, eoFill: true) { return true }
        return path.strokedPath(StrokeStyle(lineWidth: tolerance * 2, lineCap: .round, lineJoin: .round)).contains(point)
    }
}

@MainActor @Observable final class MapLayerModel {
    private(set) var snapshots: [MapSnapshot] = []
    private(set) var projected: [ProjectedMapFeature] = []
    private(set) var loading = false
    private(set) var updating = false
    private(set) var messages: [MapProvider: String] = [:]
    @ObservationIgnored private let store: MapSnapshotStore
    @ObservationIgnored private let updater: MapUpdateService
    @ObservationIgnored private var origin: GeographicCoordinate?
    @ObservationIgnored private var revision = 0

    init(store: MapSnapshotStore = MapSnapshotStore(), updater: MapUpdateService = MapUpdateService()) {
        self.store = store; self.updater = updater
    }

    func load(origin: GeographicCoordinate?) async {
        revision += 1
        let version = revision
        self.origin = origin; projected = []; loading = true
        defer { if revision == version { loading = false } }
        if snapshots.isEmpty {
            var loaded: [MapSnapshot] = []
            for provider in MapProvider.allCases {
                do {
                    let bundled = try await Self.bundled(provider)
                    let cached = try? await store.cached(provider)
                    let snapshot = cached.flatMap { $0.date >= bundled.date && $0.date <= MapUpdateService.today() ? $0 : nil } ?? bundled
                    loaded.append(snapshot)
                } catch { messages[provider] = "Offline snapshot unavailable: \(error.localizedDescription)" }
            }
            guard revision == version else { return }
            snapshots = loaded
        }
        await project(version: version)
    }

    func checkForUpdates() async {
        guard !updating, !loading else { return }
        updating = true
        defer { updating = false }
        for provider in MapProvider.allCases {
            messages[provider] = "Checking…"
            do {
                if let snapshot = try await updater.fetch(provider, currentDate: snapshots.first(where: { $0.provider == provider })?.date) {
                    if let previous = snapshots.first(where: { $0.provider == provider }) { try snapshot.validateReplacement(of: previous) }
                    try await store.install(snapshot)
                    snapshots.removeAll { $0.provider == provider }; snapshots.append(snapshot)
                    revision += 1
                    await project(version: revision)
                    messages[provider] = "Updated successfully"
                } else { messages[provider] = "Current effective dataset installed" }
            } catch { messages[provider] = "Kept existing data. " + Self.updateFailure(error) }
        }
    }

    func feature(_ id: String?) -> MapFeature? {
        guard let id else { return nil }
        return snapshots.lazy.flatMap(\.features).first { $0.id == id }
    }
    func snapshot(for feature: MapFeature) -> MapSnapshot? { snapshots.first { $0.provider == (feature.kind == .airport ? .ourAirports : .nats) } }
    func candidates(at point: CGPoint, camera: RadarCamera, size: CGSize, preferences: MapLayerPreferences) -> [MapFeature] {
        let scale = camera.pixelsPerNM(width: size.width, height: size.height)
        let mapPoint = CGPoint(x: camera.offset.east + (point.x - size.width / 2) / scale,
            y: camera.offset.north - (point.y - size.height / 2) / scale)
        return projected.filter {
            $0.feature.visibility(preferences, radiusNM: camera.radiusNM) != .hidden &&
            $0.contains(mapPoint, tolerance: ($0.feature.kind == .airport ? 9 : 5) / scale)
        }.sorted {
            if $0.feature.kind != $1.feature.kind { return $0.feature.kind.rawValue < $1.feature.kind.rawValue }
            if $0.feature.name != $1.feature.name { return $0.feature.name < $1.feature.name }
            return $0.feature.id < $1.feature.id
        }.map(\.feature)
    }

    private static func updateFailure(_ error: any Error) -> String {
        if let network = error as? URLError {
            switch network.code {
            case .notConnectedToInternet: return "No internet connection."
            case .timedOut: return "The download timed out. Try again later."
            default: return "The data source could not be reached. Try again later."
            }
        }
        if error is DecodingError { return "The downloaded data format was not recognised." }
        return error.localizedDescription
    }

    private func project(version: Int) async {
        guard let origin else { return }
        let features = snapshots.flatMap(\.features)
        let lines = await Task.detached(priority: .utility) {
            let projection = ReceiverProjection(origin: origin)
            return features.map { $0.paths.map { $0.map(projection.project) } }
        }.value
        guard revision == version, self.origin == origin else { return }
        projected = zip(features, lines).map { ProjectedMapFeature(feature: $0, lines: $1) }
    }
    private static func bundled(_ provider: MapProvider) async throws -> MapSnapshot {
        guard let url = Bundle.module.url(forResource: provider == .nats ? "NATSMap" : "AirportsMap", withExtension: "json") else {
            throw MapDataError.invalid("Missing bundled map")
        }
        return try await Task.detached(priority: .utility) {
            let snapshot = try JSONDecoder().decode(MapSnapshot.self, from: Data(contentsOf: url))
            try snapshot.validate()
            guard snapshot.provider == provider else { throw MapDataError.invalid("Incorrect bundled provider") }
            return snapshot
        }.value
    }
}

enum RadarSelection: Hashable { case aircraft(String), map(String) }
struct RadarObjectChoice: Identifiable {
    let id: RadarSelection
    let title: String
    let detail: String
}
