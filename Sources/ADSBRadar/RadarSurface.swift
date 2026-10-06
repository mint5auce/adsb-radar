import RadarCore
import SwiftUI

struct RadarSurface: View {
    @Bindable var model: RadarModel
    let openSettings: () -> Void
    @State private var size = CGSize(width: 800, height: 600)
    @State private var dragOrigin: RadarCamera?
    @State private var zoomOrigin: RadarCamera?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            GeographyCanvas(paths: model.geography, camera: model.camera, settings: model.displaySettings)
            if model.displaySettings.receiver != nil {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active)) { timeline in
                    SweepCanvas(camera: model.camera, angle: SweepTiming.angle(at: timeline.date, startedAt: model.sweepStartedAt, period: model.displaySettings.sweepSeconds))
                }
                .allowsHitTesting(false)
                AircraftCanvas(contacts: model.contacts, camera: model.camera, settings: model.displaySettings, selected: model.selectedAddress)
                    .allowsHitTesting(false)
            }
            if let coverage = model.onlineCoverage, coverage.limited, let origin = model.origin {
                OnlineBoundaryCanvas(coverage: coverage, origin: origin, camera: model.camera).allowsHitTesting(false)
            }
            overlays
        }
        .background(RadarStyle.background)
        .clipped()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            size = $0
            model.updateViewport(width: $0.width, height: $0.height)
        }
        .gesture(DragGesture(minimumDistance: 3).onChanged { event in
            if dragOrigin == nil { dragOrigin = model.camera }
            model.camera = (dragOrigin ?? model.camera).panned(dx: event.translation.width, dy: event.translation.height, width: size.width, height: size.height)
        }.onEnded { _ in dragOrigin = nil })
        .simultaneousGesture(MagnifyGesture().onChanged { event in
            if zoomOrigin == nil { zoomOrigin = model.camera }
            model.camera = (zoomOrigin ?? model.camera).zoomed(by: event.magnification)
        }.onEnded { _ in zoomOrigin = nil })
        .simultaneousGesture(SpatialTapGesture().onEnded { event in select(at: event.location) })
        .accessibilityLabel("Aircraft radar map")
        .accessibilityHint("Drag to pan. Pinch or use zoom buttons. Use the Contacts menu to select an aircraft with the keyboard.")
    }

    private var overlays: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NORTH UP / \(model.displaySettings.distance(model.camera.radiusNM)) RADIUS")
                        .padding(3).background(RadarStyle.background.opacity(0.9))
                    if model.onlineCoverage?.limited == true {
                        Text("ONLINE SEARCH LIMIT / \(model.settings.distance(model.settings.onlineRadiusNM))")
                            .foregroundStyle(RadarStyle.amber)
                            .padding(3).background(RadarStyle.background.opacity(0.9))
                    }
                    if let message = model.mapMessage { Text(message).foregroundStyle(RadarStyle.amber) }
                    if model.contacts.isEmpty, model.displaySettings.receiver != nil {
                        Text("NO POSITIONED CONTACTS").foregroundStyle(RadarStyle.muted)
                    }
                }
                .font(.system(size: 10, design: .monospaced)).tracking(1)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(timeline.date.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: Locale(identifier: "en_GB"), timeZone: .gmt)) + " UTC")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                        .padding(3).background(RadarStyle.background.opacity(0.9))
                }
            }
            .padding(6)
            .background(RadarStyle.background)
            Spacer()
            if model.displaySettings.receiver == nil {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.settings.source == .online ? "SET HOME LOCATION" : "SET RECEIVER POSITION").font(.system(size: 15, weight: .medium, design: .monospaced))
                    Text("Choose the geographic origin for\nyour sweep and range rings.").foregroundStyle(RadarStyle.muted)
                    Button("Enter latitude and longitude", action: openSettings).buttonStyle(.bordered)
                }
                .padding(24).background(RadarStyle.panel).overlay(Rectangle().stroke(RadarStyle.line))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Spacer()
            HStack {
                if let receiver = model.displaySettings.receiver {
                    Text(String(format: "ORIGIN  %.4f  /  %.4f", receiver.latitude, receiver.longitude))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
                Spacer()
                HStack(spacing: 0) {
                    control(model.settings.source == .online ? "Return home" : "Return to receiver", symbol: "location", action: model.returnToReceiver)
                        .keyboardShortcut("0", modifiers: .command)
                    control("Zoom out", symbol: "minus") { model.camera = model.camera.zoomed(by: 0.8) }
                        .keyboardShortcut("-", modifiers: .command)
                    control("Zoom in", symbol: "plus") { model.camera = model.camera.zoomed(by: 1.25) }
                        .keyboardShortcut("+", modifiers: .command)
                }
                .background(RadarStyle.panel).overlay(Rectangle().stroke(RadarStyle.line))
            }
        }
        .padding(24)
    }

    private func control(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 40, height: 36) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func select(at point: CGPoint) {
        guard let receiver = model.displaySettings.receiver else { return }
        let projection = ReceiverProjection(origin: receiver)
        let closest = model.contacts.compactMap { contact -> (String, Double)? in
            guard let coordinate = contact.observation.position else { return nil }
            let position = model.camera.screen(projection.project(coordinate), width: size.width, height: size.height)
            return (contact.id, hypot(position.x - point.x, position.y - point.y))
        }.min { $0.1 < $1.1 }
        model.selectedAddress = closest.flatMap { $0.1 <= 20 ? $0.0 : nil }
    }
}

struct GeographyCanvas: View {
    let paths: GeographyPaths?
    let camera: RadarCamera
    let settings: RadarSettings

    var body: some View {
        Canvas { context, size in
            let scale = camera.pixelsPerNM(width: size.width, height: size.height)
            if let paths {
                var geographic = context
                geographic.translateBy(x: size.width / 2 - camera.offset.east * scale, y: size.height / 2 + camera.offset.north * scale)
                geographic.scaleBy(x: scale, y: -scale)
                geographic.stroke(paths.coastline, with: .color(RadarStyle.coast), lineWidth: 0.8 / scale)
                geographic.stroke(paths.borders, with: .color(RadarStyle.coast.opacity(0.55)), style: StrokeStyle(lineWidth: 0.6 / scale, dash: [3 / scale, 3 / scale]))
            }
            guard settings.receiver != nil else { return }
            let screen = camera.screen(RadarPoint(), width: size.width, height: size.height)
            let receiver = CGPoint(x: screen.x, y: screen.y)
            let step = camera.radiusNM / 4
            let offsetDistance = hypot(camera.offset.east, camera.offset.north)
            let first = max(1, Int(floor((offsetDistance - camera.radiusNM * 2) / step)))
            let last = max(first, Int(ceil((offsetDistance + camera.radiusNM * 2) / step)))
            for index in first...last {
                let radius = Double(index) * step * scale
                let rect = CGRect(x: receiver.x - radius, y: receiver.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(RadarStyle.line.opacity(0.75)), lineWidth: 0.6)
                context.draw(Text(settings.distance(Double(index) * step)).font(.system(size: 9, design: .monospaced)).foregroundStyle(RadarStyle.muted), at: CGPoint(x: receiver.x + 4, y: receiver.y - radius - 4), anchor: .bottomLeading)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: receiver.x - 8, y: receiver.y)); cross.addLine(to: CGPoint(x: receiver.x + 8, y: receiver.y))
            cross.move(to: CGPoint(x: receiver.x, y: receiver.y - 8)); cross.addLine(to: CGPoint(x: receiver.x, y: receiver.y + 8))
            context.stroke(cross, with: .color(RadarStyle.bright), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct SweepCanvas: View {
    let camera: RadarCamera
    let angle: Double

    var body: some View {
        Canvas { context, size in
            let screen = camera.screen(RadarPoint(), width: size.width, height: size.height)
            let receiver = CGPoint(x: screen.x, y: screen.y)
            let extent = hypot(size.width + abs(receiver.x), size.height + abs(receiver.y)) + 20
            for index in 0..<20 {
                let from = angle - Double(index + 1) * 0.012
                let to = angle - Double(index) * 0.012
                var fan = Path()
                fan.move(to: receiver)
                fan.addLine(to: CGPoint(x: receiver.x + sin(from) * extent, y: receiver.y - cos(from) * extent))
                fan.addLine(to: CGPoint(x: receiver.x + sin(to) * extent, y: receiver.y - cos(to) * extent))
                fan.closeSubpath()
                context.fill(fan, with: .color(RadarStyle.green.opacity(0.035 * (1 - Double(index) / 20))))
            }
            var beam = Path()
            beam.move(to: receiver)
            beam.addLine(to: CGPoint(x: receiver.x + sin(angle) * extent, y: receiver.y - cos(angle) * extent))
            context.stroke(beam, with: .color(RadarStyle.green.opacity(0.32)), lineWidth: 0.8)
        }
    }
}

struct AircraftCanvas: View {
    let contacts: [PresentedContact]
    let camera: RadarCamera
    let settings: RadarSettings
    let selected: String?

    var body: some View {
        Canvas { context, size in
            guard let receiver = settings.receiver else { return }
            let projection = ReceiverProjection(origin: receiver)
            for contact in contacts {
                guard let position = contact.observation.position else { continue }
                let screen = camera.screen(projection.project(position), width: size.width, height: size.height)
                let point = CGPoint(x: screen.x, y: screen.y)
                let color = contact.stale ? RadarStyle.amber.opacity(0.55) : contact.id == selected ? RadarStyle.bright : RadarStyle.green
                drawTrail(contact, projection: projection, context: context, size: size, color: color)
                guard CGRect(origin: .zero, size: size).insetBy(dx: -100, dy: -40).contains(point) else { continue }
                if let heading = contact.observation.directionDegrees {
                    let direction = projection.direction(at: position, headingDegrees: heading)
                    var vector = Path()
                    vector.move(to: point)
                    vector.addLine(to: CGPoint(x: point.x + direction.east * 22, y: point.y - direction.north * 22))
                    context.stroke(vector, with: .color(color), lineWidth: 0.8)
                }
                let marker = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                context.stroke(Path(marker), with: .color(color), lineWidth: 1)
                if selected == contact.id {
                    context.stroke(Path(CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)), with: .color(RadarStyle.bright), lineWidth: 0.8)
                }
                let callsign = contact.observation.callsign ?? contact.observation.address.uppercased()
                let label = "\(callsign)\n\(settings.altitude(contact.observation.altitude))"
                let text = context.resolve(Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(color))
                let labelOrigin = CGPoint(x: point.x + 12, y: point.y - 8)
                let labelSize = text.measure(in: CGSize(width: 200, height: 40))
                context.fill(Path(CGRect(origin: labelOrigin, size: labelSize).insetBy(dx: -2, dy: -1)), with: .color(RadarStyle.background.opacity(0.9)))
                context.draw(text, at: labelOrigin, anchor: .topLeading)
            }
        }
    }

    private func drawTrail(_ contact: PresentedContact, projection: ReceiverProjection, context: GraphicsContext, size: CGSize, color: Color) {
        let samples = contact.trail
        guard samples.count > 1 else { return }
        for index in 1..<samples.count {
            let a = camera.screen(projection.project(samples[index - 1].position), width: size.width, height: size.height)
            let b = camera.screen(projection.project(samples[index].position), width: size.width, height: size.height)
            var segment = Path()
            segment.move(to: CGPoint(x: a.x, y: a.y)); segment.addLine(to: CGPoint(x: b.x, y: b.y))
            let age = Date.now.timeIntervalSince(samples[index].time)
            let opacity = max(0.08, 0.55 * (1 - age / settings.trailSeconds))
            context.stroke(segment, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
        }
    }
}

struct OnlineBoundaryCanvas: View {
    let coverage: OnlineCoverage
    let origin: GeographicCoordinate
    let camera: RadarCamera

    var body: some View {
        Canvas { context, size in
            var boundary = Path()
            var previous: CGPoint?
            for sample in coverage.boundary(relativeTo: origin) {
                let screen = camera.screen(sample, width: size.width, height: size.height)
                let point = CGPoint(x: screen.x, y: screen.y)
                if let previous, hypot(point.x - previous.x, point.y - previous.y) < hypot(size.width, size.height) {
                    boundary.addLine(to: point)
                } else { boundary.move(to: point) }
                previous = point
            }
            context.stroke(boundary, with: .color(RadarStyle.amber.opacity(0.65)), style: StrokeStyle(lineWidth: 0.8, dash: [5, 5]))
        }
    }
}
