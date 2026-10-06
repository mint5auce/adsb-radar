import Foundation
import RadarCore
import SwiftUI

struct Linework: Decodable, Sendable {
    let coastlines: [[[Double]]]
    let borders: [[[Double]]]
}

struct ProjectedLinework: Sendable {
    let coastlines: [[RadarPoint]]
    let borders: [[RadarPoint]]
}

/// Immutable paths are built once per receiver location, not on animation frames.
final class GeographyPaths {
    let coastline: Path
    let borders: Path

    private init(_ lines: ProjectedLinework) {
        coastline = Self.path(lines.coastlines)
        borders = Self.path(lines.borders)
    }

    @MainActor static func load(origin: GeographicCoordinate) async throws -> GeographyPaths {
        guard let url = Bundle.module.url(forResource: "Geography", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let projected = try await Task.detached(priority: .utility) {
            let linework = try JSONDecoder().decode(Linework.self, from: Data(contentsOf: url))
            let projection = ReceiverProjection(origin: origin)
            func project(_ lines: [[[Double]]]) -> [[RadarPoint]] {
                lines.map { line in
                    line.compactMap { coordinate in
                        guard coordinate.count == 2,
                              let point = GeographicCoordinate(latitude: coordinate[1], longitude: coordinate[0]) else { return nil }
                        return projection.project(point)
                    }
                }
            }
            return ProjectedLinework(coastlines: project(linework.coastlines), borders: project(linework.borders))
        }.value
        return GeographyPaths(projected)
    }

    private static func path(_ lines: [[RadarPoint]]) -> Path {
        var result = Path()
        for line in lines {
            var previous: RadarPoint?
            for point in line {
                let position = CGPoint(x: point.east, y: point.north)
                if let previous, hypot(point.east - previous.east, point.north - previous.north) < 1000 {
                    result.addLine(to: position)
                } else { result.move(to: position) }
                previous = point
            }
        }
        return result
    }
}
