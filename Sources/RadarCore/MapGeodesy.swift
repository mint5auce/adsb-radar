import Foundation

public enum MapGeodesy {
    public static func destination(from center: GeographicCoordinate, bearing: Double, distanceNM: Double) -> GeographicCoordinate {
        let angle = bearing * .pi / 180
        return ReceiverProjection(origin: center).coordinate(at: RadarPoint(east: sin(angle) * distanceNM, north: cos(angle) * distanceNM))!
    }
    public static func line(from start: GeographicCoordinate, to end: GeographicCoordinate) -> [GeographicCoordinate] {
        let projection = ReceiverProjection(origin: start)
        let delta = projection.project(end)
        let count = max(1, Int(ceil(hypot(delta.east, delta.north) / 2)))
        return (0...count).map { i in
            if i == 0 { return start }; if i == count { return end }
            return projection.coordinate(at: RadarPoint(east: delta.east * Double(i) / Double(count), north: delta.north * Double(i) / Double(count)))!
        }
    }
}

enum AIXMGeometry {
    static func ring(_ node: AIXMNode, index: [String: AIXMNode]) throws -> [GeographicCoordinate] {
        guard let ring = node.child("Ring"), !ring.children.isEmpty else { throw MapDataError.invalid("Missing boundary ring") }
        var result: [GeographicCoordinate] = []
        for member in ring.children {
            guard member.name == "curveMember", let curve = member.child("Curve") ?? member.reference.flatMap({ index[$0] }) else {
                throw MapDataError.invalid("Unresolved boundary reference")
            }
            try append(try self.curve(curve, index: index), to: &result)
        }
        guard let first = result.first, let last = result.last, distance(first, last) < 0.1 else {
            throw MapDataError.invalid("Open airspace boundary")
        }
        result[result.count - 1] = first
        return result
    }

    static func curve(_ node: AIXMNode, index: [String: AIXMNode]) throws -> [GeographicCoordinate] {
        guard let segments = node.child("segments"), !segments.children.isEmpty else { throw MapDataError.invalid("Missing curve segments") }
        var result: [GeographicCoordinate] = []
        for segment in segments.children {
            var sampled: [GeographicCoordinate] = []
            switch segment.name {
            case "GeodesicString", "LineStringSegment":
                let points = try segment.descendants("pos").map { try $0.coordinate() }
                guard points.count >= 2 else { throw MapDataError.invalid("Incomplete line geometry") }
                for pair in zip(points, points.dropFirst()) {
                    let line: [GeographicCoordinate]
                    if segment.name == "GeodesicString" { line = MapGeodesy.line(from: pair.0, to: pair.1) }
                    else {
                        let count = max(1, Int(ceil(distance(pair.0, pair.1) / 2)))
                        line = try (0...count).map { i in
                            let t = Double(i) / Double(count)
                            guard let point = GeographicCoordinate(latitude: pair.0.latitude + t * (pair.1.latitude - pair.0.latitude),
                                longitude: pair.0.longitude + t * (pair.1.longitude - pair.0.longitude)) else { throw MapDataError.invalid("Invalid line") }
                            return point
                        }
                    }
                    try append(line, to: &sampled)
                }
            case "ArcByCenterPoint", "CircleByCenterPoint":
                guard let center = segment.first("pos"), let radiusNode = segment.child("radius"),
                      let radius = radiusNode.value.flatMap(Double.init), radius.isFinite, radius > 0, radius <= 600,
                      radiusNode.attributes["uom"] == "[nmi_i]" else { throw MapDataError.invalid("Unsupported arc radius") }
                let origin = try center.coordinate()
                let start: Double, end: Double
                if segment.name == "CircleByCenterPoint" { start = 0; end = 360 }
                else {
                    guard let a = segment.child("startAngle"), let b = segment.child("endAngle"),
                          a.attributes["uom"] == "deg", b.attributes["uom"] == "deg",
                          let av = a.value.flatMap(Double.init), let bv = b.value.flatMap(Double.init),
                          av.isFinite, bv.isFinite, abs(bv - av) <= 360 else { throw MapDataError.invalid("Invalid arc angles") }
                    start = av; end = bv
                }
                // EPSG:4326 angles run clockwise from north. Preserve the signed sweep.
                let count = max(1, Int(ceil(abs(end - start) / 1)))
                sampled = (0...count).map { MapGeodesy.destination(from: origin, bearing: start + (end - start) * Double($0) / Double(count), distanceNM: radius) }
                if segment.name == "CircleByCenterPoint" { sampled[sampled.count - 1] = sampled[0] }
            default: throw MapDataError.invalid("Unsupported geometry: \(segment.name)")
            }
            try append(sampled, to: &result)
        }
        return result
    }

    private static func append(_ points: [GeographicCoordinate], to result: inout [GeographicCoordinate]) throws {
        guard let first = points.first else { throw MapDataError.invalid("Empty geometry") }
        if let last = result.last {
            // Published decimal endpoints and geodesic arc endpoints can differ by metres.
            guard distance(last, first) < 0.1 else { throw MapDataError.invalid("Disconnected boundary geometry") }
            result.append(contentsOf: points.dropFirst())
        } else { result = points }
    }
    private static func distance(_ a: GeographicCoordinate, _ b: GeographicCoordinate) -> Double {
        let delta = ReceiverProjection(origin: a).project(b)
        return hypot(delta.east, delta.north)
    }
}
