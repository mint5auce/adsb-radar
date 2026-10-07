import AppKit
import RadarCore
import SwiftUI

struct RadarWindow: View {
    @Bindable var model: RadarModel
    let updater: AppUpdater?
    @State private var showingSettings = false
    @State private var topBarHeight: CGFloat = 0
    @State private var bottomBarHeight: CGFloat = 0
    @State private var controls: RadarControlVisibility
    @State private var trackingMenus: Set<ObjectIdentifier> = []

    init(model: RadarModel, updater: AppUpdater? = nil) {
        self.model = model
        self.updater = updater
        // Visibility is window-owned; saved mode changes are observed below, not reseeded on redraw.
        _controls = State(initialValue: RadarControlVisibility(mode: model.settings.controlVisibility,
                                                               now: ProcessInfo.processInfo.systemUptime))
    }

    private var caretInset: CGFloat { controls.mode == .caretButtons ? 22 : 0 }
    private var topInset: CGFloat { (controls.isVisible(.top) ? topBarHeight : 0) + caretInset }
    private var bottomInset: CGFloat { (controls.isVisible(.bottom) ? bottomBarHeight : 0) + caretInset }

    var body: some View {
        HStack(spacing: 0) {
            RadarSurface(model: model, topInset: topInset, bottomInset: bottomInset,
                         openSettings: { showingSettings = true })
            if let contact = model.selectedContact {
                ContactInspector(contact: contact, identity: model.selectedIdentity, settings: model.settings, route: model.selectedRoute, category: model.reportedCategory(for: contact), showOnMap: model.showSelectedOnMap, outsideFilters: model.selectedOutsideFilters) { model.selectedAddress = nil }
                    .frame(width: 256)
                    .padding(.top, topInset).padding(.bottom, bottomInset)
            } else if let feature = model.selectedMapFeature {
                MapFeatureInspector(feature: feature, snapshot: model.mapLayers.snapshot(for: feature), preferences: model.settings.mapLayers) { model.selection = nil }
                    .frame(width: 256)
                    .padding(.top, topInset).padding(.bottom, bottomInset)
            }
        }
        .overlay(alignment: .top) {
            RadarControlBar(visibility: $controls, bar: .top, heightChanged: { topBarHeight = $0 }) {
                VStack(spacing: 0) {
                    RadarHeader(model: model, showingSettings: $showingSettings, interactionChanged: {
                        controls.setInteraction(.popover, active: $0, bar: .top, now: ProcessInfo.processInfo.systemUptime)
                    })
                    Rectangle().fill(RadarStyle.line).frame(height: 1)
                }
            }
        }
        .overlay(alignment: .bottom) {
            RadarControlBar(visibility: $controls, bar: .bottom, heightChanged: { bottomBarHeight = $0 }) {
                VStack(spacing: 0) {
                    Rectangle().fill(RadarStyle.line).frame(height: 1)
                    RadarReceptionStatus(model: model)
                }
            }
        }
        .clipped()
        .background(RadarStyle.background)
        .foregroundStyle(RadarStyle.green)
        .font(RadarStyle.mono)
        .tint(RadarStyle.green)
        .task(id: controls.nextDeadline) {
            guard let deadline = controls.nextDeadline else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime)))
                controls.advance(to: ProcessInfo.processInfo.systemUptime)
            } catch { /* A new interaction or a closed window cancels the old deadline. */ }
        }
        .onChange(of: model.settings.controlVisibility) { _, mode in
            controls.setMode(mode, now: ProcessInfo.processInfo.systemUptime)
        }
        .onChange(of: showingSettings) { _, showing in
            controls.setInteraction(.settings, active: showing, bar: .top, now: ProcessInfo.processInfo.systemUptime)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            trackingMenus.insert(ObjectIdentifier(menu))
            for bar in RadarControlVisibility.Bar.allCases where controls.isVisible(bar) {
                controls.setInteraction(.menu, active: true, bar: bar, now: ProcessInfo.processInfo.systemUptime)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { notification in
            guard let menu = notification.object as? NSMenu else { return }
            trackingMenus.remove(ObjectIdentifier(menu))
            if trackingMenus.isEmpty {
                for bar in RadarControlVisibility.Bar.allCases {
                    controls.setInteraction(.menu, active: false, bar: bar, now: ProcessInfo.processInfo.systemUptime)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            RadarSettingsView(model: model, updater: updater, save: model.apply)
        }
    }

}

// Keep menu and popover ownership independent of reception and contact redraws.
private struct RadarHeader: View {
    @Bindable var model: RadarModel
    @Binding var showingSettings: Bool
    var interactionChanged: (Bool) -> Void = { _ in }
    @State private var showingFilters = false
    @State private var showingContacts = false
    @State private var showingMap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    brand
                    Spacer(minLength: 8)
                    actions
                    settingsButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { brand; Spacer(); settingsButton }
                    actions
                }
            }
            HStack {
                Text("NORTH UP / \(model.displaySettings.distance(model.camera.radiusNM)) RADIUS")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                Spacer(minLength: 0)
            }
            if model.settings.aircraftFilters.isActive {
                Text(model.filterSummary)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.amber)
            }
        }
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .onChange(of: showingFilters || showingContacts || showingMap) { _, isPresented in interactionChanged(isPresented) }
        .onDisappear { interactionChanged(false) }
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PHOSPHOR")
                .font(.system(size: 16, weight: .semibold, design: .monospaced)).tracking(2)
            Text(model.settings.source == .synthetic ? "SYNTHETIC / \(model.settings.scenario.rawValue.uppercased())" : model.settings.source == .online ? "ONLINE / ADSB.FI" : model.settings.source == .combined ? "LOCAL + ONLINE / ADSB.FI" : "LOCAL AIR PICTURE")
                .font(.system(size: 9, design: .monospaced)).tracking(1)
                .foregroundStyle(model.settings.source == .synthetic ? RadarStyle.amber : RadarStyle.muted)
        }.fixedSize()
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: { Label("SETTINGS", systemImage: "slider.horizontal.3") }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .padding(6)
            .overlay(Rectangle().stroke(RadarStyle.line, lineWidth: 1))
            .fixedSize()
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if model.settings.source == .synthetic {
                Button { Task { await model.retry() } } label: { Label("RESTART", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.plain).disabled(model.retrying)
                    .help("Restart the synthetic scenario")
            }
            Menu {
                ForEach(UpdateMode.allCases, id: \.self) { mode in
                    Button(mode == .sweep ? "Sweep-timed updates" : "Immediate updates") { model.setMode(mode) }
                }
            } label: {
                Label(model.settings.mode == .sweep ? "SWEEP" : "IMMEDIATE", systemImage: "scope")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button { showingFilters.toggle() } label: {
                Label(model.settings.aircraftFilters.isActive ? "FILTERS •" : "FILTERS", systemImage: "line.3.horizontal.decrease")
            }
            .buttonStyle(.plain).help(model.filterSummary)
            .popover(isPresented: $showingFilters) { AircraftFiltersView(model: model) }
            presentationMenu
            Button { showingMap.toggle() } label: { Label("MAP", systemImage: "map") }
                .buttonStyle(.plain).fixedSize()
                .popover(isPresented: $showingMap) { MapLayerControls(model: model) }
            Button { showingContacts.toggle() } label: { Label("CONTACTS", systemImage: "airplane") }
                .buttonStyle(.plain).fixedSize()
                .popover(isPresented: $showingContacts) { AircraftContactsView(model: model) }
        }.fixedSize()
    }

    private var presentationMenu: some View {
        Menu {
            Picker("Labels", selection: Binding(get: { model.settings.labelMode }, set: { value in
                var settings = model.settings; settings.labelMode = value; model.apply(settings)
            })) {
                ForEach(AircraftLabelMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Trails", selection: Binding(get: { model.settings.trailMode }, set: { value in
                var settings = model.settings; settings.trailMode = value; model.apply(settings)
            })) {
                ForEach(AircraftTrailMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Direction vectors", isOn: Binding(get: { model.settings.directionVectors }, set: { value in
                var settings = model.settings; settings.directionVectors = value; model.apply(settings)
            }))
        } label: { Label("VIEW", systemImage: "eye") }
        .menuStyle(.borderlessButton).fixedSize()
    }

}

private struct RadarReceptionStatus: View {
    @Bindable var model: RadarModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                feeds.fixedSize()
                Spacer(minLength: 8)
                counts.fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                feeds
                counts
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RadarStyle.panel)
    }

    private var feeds: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(model.feedHealth) { health in
                FeedStatusIndicator(feed: health.feed, status: health.status,
                    scenario: model.settings.scenario, localReceptionPaused: model.localReceptionPaused)
            }
        }
    }

    private var counts: some View {
        HStack(spacing: 12) {
            if model.showsOnlineAttribution {
                Link("adsb.fi", destination: URL(string: "https://adsb.fi")!).foregroundStyle(RadarStyle.muted)
            }
            let counts = model.contactCounts
            Text("\(counts.inView) IN VIEW  /  \(counts.outsideView) OUTSIDE VIEW  /  \(counts.filtered) FILTERED")
                .foregroundStyle(RadarStyle.green)
            Text("\(model.heardWithoutPosition) WITHOUT POSITION").foregroundStyle(RadarStyle.muted)
        }.fixedSize()
    }
}

private struct FeedStatusIndicator: View {
    let feed: AircraftFeed
    let status: ReceptionStatus
    let scenario: SyntheticScenario
    let localReceptionPaused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).foregroundStyle(color).help(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var color: Color {
        if case .failed = status { return RadarStyle.amber }
        return status == .receiving ? RadarStyle.green : RadarStyle.muted
    }
    private var text: String {
        if feed == .local, localReceptionPaused { return "LOCAL: No dongle found. Retry in Settings." }
        let name = feed == .local ? "LOCAL" : feed == .online ? "ONLINE / ADSB.FI" : "SYNTHETIC \(scenario.rawValue.uppercased())"
        switch status {
        case .stopped: return "\(name) STOPPED"
        case .starting: return "STARTING \(name)"
        case .waiting: return "\(name) ACTIVE / WAITING FOR AIRCRAFT"
        case .receiving: return feed == .synthetic ? "\(name) / GENERATED TRAFFIC" : "\(name) ACTIVE"
        case .failed(let message): return "\(name): \(message) Retry in Settings."
        }
    }

}

struct ContactInspector: View {
    let contact: PresentedContact
    let identity: AircraftIdentity?
    let settings: RadarSettings
    var route: FlightRouteLookupState = .unknown
    var category: AircraftCategoryValue? = nil
    var showOnMap: (() -> Void)? = nil
    var outsideFilters: Bool = false
    let dismiss: () -> Void

    private var identifiers: AircraftIdentifiers {
        AircraftIdentifiers(observation: contact.observation, identity: identity, preferred: settings.aircraftIdentifier)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(contact.stale ? "CONTACT / STALE" : "CONTACT / CURRENT")
                        .font(.system(size: 10, design: .monospaced)).tracking(1)
                    Spacer()
                    Button(action: dismiss) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Deselect aircraft")
                }
                .foregroundStyle(contact.stale ? RadarStyle.amber : RadarStyle.muted)
                VStack(alignment: .leading, spacing: 8) {
                    Text(identifiers.primary)
                        .font(.system(size: 23, weight: .medium, design: .monospaced))
                        .foregroundStyle(RadarStyle.bright)
                    Text("\(contact.observation.address.hasPrefix("~") ? "NON-ICAO" : "ICAO") \(contact.observation.address.uppercased())").font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
                if let showOnMap { Button("Show on map", action: showOnMap) }
                if outsideFilters { Text("OUTSIDE FILTERS").foregroundStyle(RadarStyle.amber) }
                Rectangle().fill(RadarStyle.line).frame(height: 1)
                field("REGISTRATION", identifiers.registration ?? "UNKNOWN")
                field("CALLSIGN", identifiers.callsign ?? "UNKNOWN")
                if settings.source != .synthetic {
                    FlightRouteInspector(state: route)
                }
                field("AIRCRAFT TYPE", identity?.aircraftLabel ?? "UNKNOWN")
                if identity?.modelDescription != nil, let code = identity?.aircraftType?.value {
                    field("ICAO TYPE", code)
                }
                field("OWNER / OPERATOR", identity?.ownerOperator?.value ?? "UNKNOWN")
                    .help("Owner or operator reported by the aircraft data source. This may be a registered owner rather than the airline operating this flight.")
                if let identity {
                    field("DETAILS UPDATED", identity.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "UNKNOWN")
                        .help("The oldest successful update of the known identity fields. Missing fields retain their previous dates.")
                    field("DETAILS FROM", Array(Set(identity.detailFields.map(\.provider))).sorted().joined(separator: ", "))
                }
                field("REPORTED CATEGORY", category.map { "\($0.value.title) / \($0.value.rawValue)" } ?? "UNKNOWN")
                if let category {
                    field("CATEGORY FROM", category.provider)
                    field("CATEGORY UPDATED", category.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                field("ALTITUDE", settings.altitude(contact.observation.altitude))
                field("GROUND SPEED", settings.speed(contact.observation.speedKnots))
                field("DIRECTION", contact.observation.directionDegrees.map { String(format: "%03.0f°", $0) } ?? "UNKNOWN")
                field("SOURCE", contact.observation.source)
                field("POSITION AGE", "\(Int(contact.positionAge)) SEC")
                if let position = contact.observation.position {
                    field("DISPLAYED POSITION", String(format: "%.5f\n%.5f", position.latitude, position.longitude))
                }
                if contact.stale {
                    Text("LAST KNOWN POSITION\nAwaiting a fresh observation.")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.amber)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(RadarStyle.panel)
        .overlay(alignment: .leading) { Rectangle().fill(RadarStyle.line).frame(width: 1) }
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(RadarStyle.muted)
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundStyle(RadarStyle.green)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
