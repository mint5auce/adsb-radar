import Foundation
import CoreGraphics

public enum AircraftLabelMode: String, Codable, CaseIterable, Sendable {
    case automatic, all, selectedOnly
    public var title: String {
        switch self { case .automatic: "Automatic"; case .all: "All"; case .selectedOnly: "Selected only" }
    }
}

public enum AircraftTrailMode: String, Codable, CaseIterable, Sendable {
    case all, selected, none
    public var title: String { rawValue.capitalized }
    public func shows(selected: Bool) -> Bool { self == .all || (self == .selected && selected) }
}

public struct AircraftLabelCandidate {
    public let id: String
    public let point: CGPoint
    public let size: CGSize
    public let selected: Bool
    public let stale: Bool
    public let homeDistance: Double

    public init(id: String, point: CGPoint, size: CGSize, selected: Bool = false, stale: Bool = false, homeDistance: Double = 0) {
        self.id = id; self.point = point; self.size = size
        self.selected = selected; self.stale = stale; self.homeDistance = homeDistance
    }
}

/// Owns placement continuity, independent of reception and trail history.
public final class AircraftLabelLayout {
    private var slots: [String: Int] = [:]
    public init() {}

    public func place(_ candidates: [AircraftLabelCandidate], in viewport: CGRect, mode: AircraftLabelMode) -> [String: CGRect] {
        let ordered = candidates.sorted { a, b in
            if a.selected != b.selected { return a.selected }
            if a.stale != b.stale { return !a.stale }
            if (slots[a.id] != nil) != (slots[b.id] != nil) { return slots[a.id] != nil }
            if a.homeDistance != b.homeDistance { return a.homeDistance < b.homeDistance }
            return a.id < b.id
        }
        var result: [String: CGRect] = [:]
        var nextSlots: [String: Int] = [:]
        for candidate in ordered where viewport.contains(candidate.point) {
            if mode == .selectedOnly && !candidate.selected { continue }
            let origins = origins(for: candidate)
            let preferred = slots[candidate.id] ?? 0
            let choices = [preferred] + origins.indices.filter { $0 != preferred }
            for slot in choices {
                var rect = CGRect(origin: origins[slot], size: candidate.size)
                if candidate.selected {
                    rect.origin.x = min(max(rect.minX, viewport.minX + 3), max(viewport.minX + 3, viewport.maxX - rect.width - 3))
                    rect.origin.y = min(max(rect.minY, viewport.minY + 3), max(viewport.minY + 3, viewport.maxY - rect.height - 3))
                }
                guard candidate.selected || mode == .all || viewport.contains(rect.insetBy(dx: -3, dy: -2)) else { continue }
                let collides = result.values.contains { $0.insetBy(dx: -4, dy: -3).intersects(rect) }
                guard mode != .automatic || !collides else { continue }
                result[candidate.id] = rect
                nextSlots[candidate.id] = slot
                break
            }
        }
        slots = nextSlots
        return result
    }

    private func origins(for candidate: AircraftLabelCandidate) -> [CGPoint] {
        let x = candidate.point.x, y = candidate.point.y
        let w = candidate.size.width, h = candidate.size.height
        return [CGPoint(x: x + 12, y: y - 8), CGPoint(x: x - w - 12, y: y - 8),
                CGPoint(x: x + 12, y: y - h - 12), CGPoint(x: x - w - 12, y: y - h - 12),
                CGPoint(x: x + 12, y: y + 12), CGPoint(x: x - w - 12, y: y + 12),
                CGPoint(x: x - w / 2, y: y - h - 12), CGPoint(x: x - w / 2, y: y + 12)]
    }
}
