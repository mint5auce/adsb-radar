import Foundation

/// Reads a complete AIXM BASELINE export. No aviation widths are inferred.
public enum NATSImporter {
    public static func parse(_ data: Data, effectiveDate: String) throws -> MapSnapshot {
        guard data.range(of: Data("<!DOCTYPE".utf8)) == nil else { throw MapDataError.invalid("XML document types are unsupported") }
        let document = AIXMDocument()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = document
        guard parser.parse(), document.failure == nil else {
            throw MapDataError.invalid(document.failure ?? "Invalid NATS XML")
        }
        var result: [MapFeature] = []
        for feature in document.features where feature.name == "RouteSegment" {
            let slice = try feature.timeSlice()
            guard let routeID = slice.child("routeFormed")?.reference,
                  let route = document.byID[routeID], route.name == "Route" else {
                throw MapDataError.invalid("Unresolved route reference")
            }
            let routeSlice = try route.timeSlice()
            let name = ["designatorPrefix", "designatorSecondLetter", "designatorNumber"].compactMap { routeSlice.child($0)?.value }.joined()
            func endpoint(_ key: String) throws -> (String, GeographicCoordinate) {
                guard let point = slice.child(key)?.first("EnRouteSegmentPoint"),
                      let reference = point.children.first(where: { $0.name.hasPrefix("pointChoice_") })?.reference,
                      let target = document.byID[reference] else { throw MapDataError.invalid("Unresolved route endpoint") }
                let targetSlice = try target.timeSlice()
                guard let label = targetSlice.child("designator")?.value,
                      let position = targetSlice.child("location")?.first("pos") else { throw MapDataError.invalid("Missing waypoint position") }
                return (label, try position.coordinate())
            }
            let start = try endpoint("start"), end = try endpoint("end")
            let paths: [[GeographicCoordinate]]
            if let curve = slice.child("curveExtent")?.first("Curve") {
                paths = [try AIXMGeometry.curve(curve, index: document.byID)]
            } else { paths = [MapGeodesy.line(from: start.1, to: end.1)] }
            var item = MapFeature(id: "route:" + (try feature.identifier()), kind: .route, name: name, label: name, paths: paths)
            item.lower = slice.altitude("lower")
            item.upper = slice.altitude("upper")
            let left = slice.child("widthLeft"), right = slice.child("widthRight")
            let width: String
            if let l = left?.value, let r = right?.value {
                width = "L \(l) \(left?.attributes["uom"] ?? "") / R \(r) \(right?.attributes["uom"] ?? "")"
            } else { width = "UNKNOWN" }
            item.routeEndpoints = [MapRouteEndpoint(name: start.0, coordinate: start.1), MapRouteEndpoint(name: end.0, coordinate: end.1)]
            item.details = [MapDetail("WIDTH", width)]
            result.append(item)
        }
        for feature in document.features where feature.name == "Airspace" {
            let slice = try feature.timeSlice()
            guard let type = slice.child("type")?.value, ["CTA", "CTR", "TMA"].contains(type) else { continue }
            let components = slice.children.filter { $0.name == "geometryComponent" }
            guard !components.isEmpty else { throw MapDataError.invalid("Missing airspace geometry") }
            for (offset, component) in components.enumerated() {
                guard let geometry = component.child("AirspaceGeometryComponent"),
                      geometry.child("operation")?.value == "BASE",
                      let volume = geometry.child("theAirspaceVolume")?.child("AirspaceVolume"),
                      let surface = volume.child("horizontalProjection")?.child("Surface"),
                      let patches = surface.child("patches"), !patches.children.isEmpty else {
                    throw MapDataError.invalid("Unsupported airspace composition")
                }
                for (patchIndex, patch) in patches.children.enumerated() {
                    guard patch.name == "PolygonPatch", let exterior = patch.child("exterior") else {
                        throw MapDataError.invalid("Unsupported airspace surface")
                    }
                    let rings = [exterior] + patch.children.filter { $0.name == "interior" }
                    let paths = try rings.map { try AIXMGeometry.ring($0, index: document.byID) }
                    let name = slice.child("name")?.value ?? slice.child("designator")?.value ?? "UNKNOWN"
                    var item = MapFeature(id: "airspace:" + (try feature.identifier()) + ":\(offset):\(patchIndex)",
                        kind: .airspace, name: name, label: name, paths: paths)
                    item.lower = volume.altitude("lower"); item.upper = volume.altitude("upper")
                    item.details = [MapDetail("TYPE", type), MapDetail("DESIGNATOR", slice.child("designator")?.value ?? "UNKNOWN")]
                    result.append(item)
                }
            }
        }
        let snapshot = MapSnapshot(provider: .nats, date: effectiveDate,
            sourceURL: "https://nats-uk.ead-it.com/cms-nats/opencms/en/Publications/digital-datasets/",
            terms: "© NATS. Aviation use only. Not for resale. Published airspace; activation is not represented.",
            coverage: "United Kingdom and Crown Dependencies (NATS published extent)", features: result.sorted { $0.id < $1.id })
        try snapshot.validate()
        return snapshot
    }
}

final class AIXMNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [AIXMNode] = []
    init(_ name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
    var value: String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return attributes["nil"] == "true" || value.isEmpty ? nil : value
    }
    var reference: String? { attributes["href"].map { $0.replacingOccurrences(of: "urn:uuid:", with: "").replacingOccurrences(of: "#", with: "") } }
    func child(_ name: String) -> AIXMNode? { children.first { $0.name == name } }
    func first(_ name: String) -> AIXMNode? {
        if self.name == name { return self }
        for child in children { if let found = child.first(name) { return found } }
        return nil
    }
    func descendants(_ name: String) -> [AIXMNode] {
        (self.name == name ? [self] : []) + children.flatMap { $0.descendants(name) }
    }
    func identifier() throws -> String {
        guard let id = child("identifier")?.value else { throw MapDataError.invalid("Missing AIXM identity") }
        return id
    }
    func timeSlice() throws -> AIXMNode {
        let slices = children.filter { $0.name == "timeSlice" }.flatMap(\.children)
        guard slices.count == 1, let slice = slices.first, slice.child("interpretation")?.value == "BASELINE" else {
            throw MapDataError.invalid("Expected one BASELINE timeslice")
        }
        return slice
    }
    func coordinate() throws -> GeographicCoordinate {
        if let crs = attributes["srsName"], !crs.hasSuffix("4326") { throw MapDataError.invalid("Unsupported coordinate reference") }
        let pair = (value ?? "").split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard pair.count == 2, let result = GeographicCoordinate(latitude: pair[0], longitude: pair[1]) else {
            throw MapDataError.invalid("Invalid AIXM coordinate")
        }
        return result
    }
    func altitude(_ prefix: String) -> MapAltitude {
        let node = child(prefix + "Limit")
        return MapAltitude(value: node?.value.flatMap(Double.init), unit: node?.attributes["uom"] ?? "", reference: child(prefix + "LimitReference")?.value ?? "")
    }
}

/// Retains only relevant features, not the full 70+ MB document tree.
private final class AIXMDocument: NSObject, XMLParserDelegate {
    var features: [AIXMNode] = []
    var byID: [String: AIXMNode] = [:]
    var failure: String?
    private var stack: [AIXMNode] = []
    private let retained: Set<String> = ["Route", "RouteSegment", "DesignatedPoint", "Navaid", "Airspace", "GeoBorder"]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        guard !stack.isEmpty || retained.contains(name) else { return }
        let attributes = Dictionary(attributeDict.map { (String($0.key.split(separator: ":").last!), $0.value) }, uniquingKeysWith: { a, _ in a })
        if let crs = attributes["srsName"], !crs.hasSuffix("4326") { failure = "Unsupported coordinate reference"; parser.abortParsing(); return }
        let node = AIXMNode(name, attributes: attributes)
        stack.last?.children.append(node)
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let node = stack.popLast() else { return }
        if let id = node.attributes["id"] { byID[id] = node }
        if stack.isEmpty {
            features.append(node)
            if let id = node.child("identifier")?.value { byID[id] = node }
        }
    }
}
