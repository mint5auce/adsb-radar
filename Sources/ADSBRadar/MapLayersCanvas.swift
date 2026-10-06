import RadarCore
import SwiftUI

struct MapLayersCanvas: View {
    let layers: MapLayerModel
    let camera: RadarCamera
    let preferences: MapLayerPreferences
    let selected: String?
    var reserved: [CGRect] = []

    var body: some View {
        Canvas { context, size in
            let scale = camera.pixelsPerNM(width: size.width, height: size.height)
            let center = camera.screen(RadarPoint(), width: size.width, height: size.height)
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: center.x, ty: center.y)
            let viewport = CGRect(origin: .zero, size: size)
            let visible = layers.projected.filter {
                $0.feature.visibility(preferences, radiusNM: camera.radiusNM) != .hidden &&
                $0.bounds.applying(transform).insetBy(dx: -12, dy: -12).intersects(viewport)
            }
            // Boundaries first, route lines second, airports last. Selection sits above all.
            let ordered = visible.sorted {
                if ($0.feature.id == selected) != ($1.feature.id == selected) { return $1.feature.id == selected }
                let rank: [MapFeatureKind: Int] = [.airspace: 0, .route: 1, .airport: 2]
                let a = rank[$0.feature.kind] ?? 0, b = rank[$1.feature.kind] ?? 0
                return a == b ? $0.feature.id < $1.feature.id : a < b
            }
            // Stroke shared edges in a single pass so coincident routes do not accumulate brightness.
            for kind in [MapFeatureKind.airspace, .route] {
                for uncertain in [false, true] {
                    var combined = Path()
                    for item in ordered where item.feature.kind == kind && item.feature.id != selected &&
                        (item.feature.slice(at: preferences.flightLevel) == .uncertain) == uncertain {
                        combined.addPath(item.path)
                    }
                    context.stroke(combined.applying(transform), with: .color(RadarStyle.green.opacity((kind == .route ? 0.19 : 0.15) * (uncertain ? 0.45 : 1))),
                        style: StrokeStyle(lineWidth: 0.65, dash: kind == .route && uncertain ? [3, 3] : []))
                }
            }
            for item in ordered {
                let active = item.feature.id == selected
                let uncertain = item.feature.slice(at: preferences.flightLevel) == .uncertain
                let opacity = uncertain && !active ? 0.45 : 1.0
                let color = active ? RadarStyle.bright : RadarStyle.green
                let path = item.path.applying(transform)
                switch item.feature.kind {
                case .airspace:
                    context.fill(path, with: .color(color.opacity((active ? 0.045 : 0.007) * opacity)), style: FillStyle(eoFill: true))
                    if active { context.stroke(path, with: .color(color.opacity(0.85)), lineWidth: 1.3) }
                case .route:
                    if active { context.stroke(path, with: .color(color), lineWidth: 1.6) }
                    if camera.radiusNM <= 55 || active {
                        for endpoint in item.endpoints {
                            let point = endpoint.applying(transform)
                            var diamond = Path()
                            diamond.move(to: CGPoint(x: point.x, y: point.y - 3)); diamond.addLine(to: CGPoint(x: point.x + 3, y: point.y))
                            diamond.addLine(to: CGPoint(x: point.x, y: point.y + 3)); diamond.addLine(to: CGPoint(x: point.x - 3, y: point.y)); diamond.closeSubpath()
                            context.stroke(diamond, with: .color(color.opacity(0.55 * opacity)), lineWidth: 0.7)
                        }
                    }
                case .airport:
                    let point = item.anchor.applying(transform)
                    let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(active ? 1 : 0.6)), lineWidth: active ? 1.4 : 0.9)
                    var cross = Path(); cross.move(to: CGPoint(x: point.x - 2, y: point.y)); cross.addLine(to: CGPoint(x: point.x + 2, y: point.y))
                    context.stroke(cross, with: .color(color.opacity(0.6)), lineWidth: 0.7)
                }
            }
            var occupied = reserved
            var labelled: Set<String> = []
            let labelBudget = max(18, Int(size.width * size.height / 15000))
            var labelCounts: [MapFeatureKind: Int] = [:]
            // Selected feature gets first choice of space. Labels remain deliberately sparse.
            let labels = ordered.reversed()
            for item in labels {
                let active = item.feature.id == selected
                let share = item.feature.kind == .airport ? 0.5 : item.feature.kind == .route ? 0.4 : 0.1
                guard active || labelCounts[item.feature.kind, default: 0] < max(2, Int(Double(labelBudget) * share)) else { continue }
                guard active || item.feature.kind != .airspace || camera.radiusNM <= 55 else { continue }
                guard active || item.feature.kind != .route || camera.radiusNM <= 250 else { continue }
                guard active || !labelled.contains(item.feature.label) else { continue }
                let opacity = item.feature.slice(at: preferences.flightLevel) == .uncertain ? 0.3 : 0.5
                let color = active ? RadarStyle.bright : RadarStyle.green.opacity(opacity)
                let text = context.resolve(Text(item.feature.label).font(.system(size: 10, design: .monospaced)).foregroundStyle(color))
                var point = item.anchor.applying(transform)
                if item.feature.kind == .airspace { point = CGPoint(x: item.bounds.midX, y: item.bounds.midY).applying(transform) }
                let measured = text.measure(in: CGSize(width: 250, height: 28))
                if active {
                    point.x = min(max(point.x, 8), size.width - measured.width - 18)
                    point.y = min(max(point.y, 55), size.height - measured.height - 55)
                }
                let rect = CGRect(x: point.x + 8, y: point.y - 6, width: measured.width, height: measured.height)
                guard viewport.contains(rect), active || !occupied.contains(where: { $0.intersects(rect.insetBy(dx: -25, dy: -18)) }) else { continue }
                context.fill(Path(rect.insetBy(dx: -3, dy: -2)), with: .color(RadarStyle.background.opacity(0.86)))
                context.draw(text, at: rect.origin, anchor: .topLeading)
                occupied.append(rect); labelled.insert(item.feature.label); labelCounts[item.feature.kind, default: 0] += 1
                if item.feature.kind == .route, camera.radiusNM <= 55 || active {
                    for (index, endpoint) in item.endpoints.enumerated() {
                        let title = index == 0 ? "FROM" : "TO"
                        guard let name = item.feature.details.first(where: { $0.title == title })?.value else { continue }
                        let label = context.resolve(Text(name).font(.system(size: 9, design: .monospaced)).foregroundStyle(color))
                        let position = endpoint.applying(transform)
                        let box = CGRect(origin: CGPoint(x: position.x + 5, y: position.y + 5), size: label.measure(in: CGSize(width: 120, height: 20)))
                        guard viewport.contains(box), !occupied.contains(where: { $0.intersects(box.insetBy(dx: -5, dy: -4)) }) else { continue }
                        context.draw(label, at: box.origin, anchor: .topLeading); occupied.append(box)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
