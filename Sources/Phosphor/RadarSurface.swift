import RadarCore
import SwiftUI

struct RadarSurface: View {
    @Bindable var model: RadarModel
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    let openSettings: () -> Void
    @State private var size = CGSize(width: 800, height: 600)
    @State private var dragOrigin: RadarCamera?
    @State private var showingChooser = false
    @State private var choices: [RadarObjectChoice] = []
    @State private var tapPoint = CGPoint.zero
    @State private var zoomOrigin: RadarCamera?
    @State private var topOverlayFrame = CGRect.zero
    @State private var bottomOverlayFrame = CGRect.zero
    @State private var navigationFrame = CGRect.zero
    @State private var homePromptFrame = CGRect.zero
    @Environment(\.scenePhase) private var scenePhase

    private var currentChoices: [RadarObjectChoice] { choices.compactMap(model.refreshedChoice) }

    var body: some View {
        ZStack {
            GeographyCanvas(paths: model.geography, camera: model.camera, settings: model.displaySettings)
            MapLayersCanvas(layers: model.mapLayers, camera: model.camera, preferences: model.settings.mapLayers,
                selected: model.selectedMapFeature?.id, reserved: reservedRegions)
            if model.displaySettings.receiver != nil {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: scenePhase != .active)) { timeline in
                    SweepCanvas(camera: model.camera, angle: SweepTiming.angle(at: timeline.date, startedAt: model.sweepStartedAt, period: model.displaySettings.sweepSeconds))
                }
                .allowsHitTesting(false)
                AircraftCanvas(contacts: model.eligibleContacts, camera: model.camera, settings: model.displaySettings, selected: model.selectedAddress,
                    reserved: reservedRegions, identities: model.settings.source == .synthetic ? [:] : model.identities)
                    .allowsHitTesting(false)
            }
            if let coverage = model.onlineCoverage, coverage.limited, let origin = model.origin {
                OnlineBoundaryCanvas(coverage: coverage, origin: origin, camera: model.camera).allowsHitTesting(false)
            }
            overlays
        }
        .background(RadarStyle.background)
        .coordinateSpace(name: "radar-map")
        .clipped()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            size = $0
            model.updateViewport(width: $0.width, height: $0.height)
        }
        .gesture(DragGesture(minimumDistance: 3).onChanged { event in
            guard !navigationFrame.contains(event.startLocation) else { return }
            if dragOrigin == nil { dragOrigin = model.camera }
            model.camera = (dragOrigin ?? model.camera).panned(dx: event.translation.width, dy: event.translation.height, width: size.width, height: size.height)
        }.onEnded { _ in dragOrigin = nil })
        .simultaneousGesture(MagnifyGesture().onChanged { event in
            guard acceptsNavigation(at: event.startLocation) else { return }
            if zoomOrigin == nil { zoomOrigin = model.camera }
            model.camera = (zoomOrigin ?? model.camera).zoomed(by: event.magnification,
                atX: event.startLocation.x, y: event.startLocation.y, width: size.width, height: size.height)
        }.onEnded { _ in zoomOrigin = nil })
        .simultaneousGesture(SpatialTapGesture().onEnded { event in select(at: event.location) })
        .overlay(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: 1).position(tapPoint)
                .popover(isPresented: $showingChooser) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SELECT OBJECT").font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted).padding(8)
                            ForEach(currentChoices) { choice in
                                Button { model.selection = choice.id; showingChooser = false } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(choice.title).foregroundStyle(RadarStyle.green)
                                        Text(choice.detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }.padding(8)
                    }.frame(width: 310, height: min(380, CGFloat(currentChoices.count * 58 + 50))).background(RadarStyle.panel)
                }
        }
        .overlay {
            MapScrollInput(accepts: acceptsNavigation) { point, motion in
                switch motion {
                case let .pan(dx, dy):
                    model.camera = model.camera.panned(dx: dx, dy: dy,
                        width: size.width, height: size.height)
                case let .zoom(factor):
                    model.camera = model.camera.zoomed(by: factor,
                        atX: point.x, y: point.y, width: size.width, height: size.height)
                }
            }.allowsHitTesting(false)
        }
        .overlay {
            MapSecondaryClick { point in
                // The AppKit event monitor also sees clicks on the bars layered above this map.
                guard point.y >= topInset, point.y < size.height - bottomInset else { return }
                guard !navigationFrame.contains(point) else { return }
                let candidates = model.objectChoices(at: point, secondary: true)
                if !candidates.isEmpty { tapPoint = point; choices = candidates; showingChooser = true }
            }.allowsHitTesting(false)
        }
        .accessibilityLabel("Aircraft radar map")
        .accessibilityHint("Drag or scroll with two fingers to pan. Use the mouse wheel, pinch, or zoom buttons to zoom. Use Contacts to select an aircraft with the keyboard.")
    }

    private var overlays: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
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
                HStack(spacing: 8) {
                    if model.settings.source == .synthetic {
                        Text("SYNTHETIC")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.amber)
                            .padding(3).background(Color.black)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text(timeline.date.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: Locale(identifier: "en_GB"), timeZone: .gmt)) + " UTC")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                            .padding(3).background(Color.black)
                    }
                }
            }
            .padding(6)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("radar-map")) } action: { topOverlayFrame = $0 }
            Spacer()
            if model.displaySettings.receiver == nil {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.settings.source == .online ? "SET HOME LOCATION" : "SET RECEIVER POSITION").font(.system(size: 15, weight: .medium, design: .monospaced))
                    Text("Choose the geographic origin for\nyour sweep and range rings.").foregroundStyle(RadarStyle.muted)
                    Button("Enter latitude and longitude", action: openSettings).buttonStyle(.bordered)
                }
                .padding(24).background(RadarStyle.panel).overlay(Rectangle().stroke(RadarStyle.line))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("radar-map")) } action: { homePromptFrame = $0 }
                .frame(maxWidth: .infinity, alignment: .center)
                .onDisappear { homePromptFrame = .zero }
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
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("radar-map")) } action: { navigationFrame = $0 }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("radar-map")) } action: { bottomOverlayFrame = $0 }
        }
        .padding(24)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
    }

    private var reservedRegions: [CGRect] {
        [topOverlayFrame, bottomOverlayFrame,
         CGRect(x: 0, y: 0, width: size.width, height: topInset),
         CGRect(x: 0, y: size.height - bottomInset, width: size.width, height: bottomInset)]
    }

    private func control(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 40, height: 36).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func acceptsNavigation(at point: CGPoint) -> Bool {
        point.y >= topInset && point.y < size.height - bottomInset
            && !navigationFrame.contains(point) && !homePromptFrame.contains(point) && !showingChooser
    }

    private func select(at point: CGPoint) {
        // Navigation owns its entire panel, including the space around button symbols.
        guard !navigationFrame.contains(point) else { return }
        let candidates = model.objectChoices(at: point)
        if candidates.count > 1 {
            tapPoint = point; choices = candidates; showingChooser = true
        } else {
            showingChooser = false; model.selection = candidates.first?.id
        }
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
    var reserved: [CGRect] = []
    var identities: [String: AircraftIdentity] = [:]

    @State private var labelLayout = AircraftLabelLayout()

    var body: some View {
        Canvas { context, size in
            guard let receiver = settings.receiver else { return }
            let projection = ReceiverProjection(origin: receiver)
            let viewport = CGRect(origin: .zero, size: size)
            let rows = contacts.compactMap { contact -> (contact: PresentedContact, point: CGPoint, color: Color, text: GraphicsContext.ResolvedText, candidate: AircraftLabelCandidate)? in
                guard let position = contact.observation.position else { return nil }
                let projected = projection.project(position)
                let screen = camera.screen(projected, width: size.width, height: size.height)
                let point = CGPoint(x: screen.x, y: screen.y)
                let color = contact.stale ? RadarStyle.amber.opacity(0.55) : contact.id == selected ? RadarStyle.bright : RadarStyle.green
                if settings.trailMode.shows(selected: contact.id == selected) {
                    drawTrail(contact, projection: projection, context: context, size: size, color: color)
                }
                guard viewport.insetBy(dx: -100, dy: -40).contains(point) else { return nil }
                if settings.directionVectors, let heading = contact.observation.directionDegrees {
                    let direction = projection.direction(at: position, headingDegrees: heading)
                    var vector = Path()
                    vector.move(to: point)
                    vector.addLine(to: CGPoint(x: point.x + direction.east * 22, y: point.y - direction.north * 22))
                    context.stroke(vector, with: .color(color), lineWidth: 0.8)
                }
                let identifiers = AircraftIdentifiers(observation: contact.observation, identity: identities[contact.observation.address],
                    preferred: settings.aircraftIdentifier)
                let label = "\(identifiers.primary)\n\(settings.altitude(contact.observation.altitude))"
                let text = context.resolve(Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(color))
                let candidate = AircraftLabelCandidate(id: contact.id, point: point,
                    size: text.measure(in: CGSize(width: 200, height: 40)), selected: contact.id == selected,
                    stale: contact.stale, homeDistance: hypot(projected.east, projected.north))
                return (contact, point, color, text, candidate)
            }
            let placements = labelLayout.place(rows.map(\.candidate), in: viewport, mode: settings.labelMode, reserved: reserved)
            // The selected callout remains legible when All allows other labels to overlap.
            let labelRows = rows.filter { $0.contact.id != selected } + rows.filter { $0.contact.id == selected }
            for row in labelRows {
                if let rect = placements[row.contact.id] {
                    if row.contact.id == selected {
                        var leader = Path()
                        leader.move(to: row.point)
                        leader.addLine(to: CGPoint(x: min(max(row.point.x, rect.minX), rect.maxX), y: min(max(row.point.y, rect.minY), rect.maxY)))
                        context.stroke(leader, with: .color(row.color.opacity(0.6)), lineWidth: 0.6)
                    }
                    context.fill(Path(rect.insetBy(dx: -2, dy: -1)), with: .color(RadarStyle.background.opacity(0.9)))
                    context.draw(row.text, at: rect.origin, anchor: .topLeading)
                }
            }
            // Every marker is drawn after every label background.
            for row in rows {
                let marker = CGRect(x: row.point.x - 3, y: row.point.y - 3, width: 6, height: 6)
                context.stroke(Path(marker), with: .color(row.color), lineWidth: 1)
                if selected == row.contact.id {
                    context.stroke(Path(CGRect(x: row.point.x - 8, y: row.point.y - 8, width: 16, height: 16)), with: .color(RadarStyle.bright), lineWidth: 0.8)
                }
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
