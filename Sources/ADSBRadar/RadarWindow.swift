import RadarCore
import SwiftUI

struct RadarWindow: View {
    @Bindable var model: RadarModel
    @State private var showingSettings = false
    @State private var showingFilters = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(RadarStyle.line).frame(height: 1)
            HStack(spacing: 0) {
                RadarSurface(model: model, openSettings: { showingSettings = true })
                if let contact = model.selectedContact {
                    ContactInspector(contact: contact, identity: model.selectedIdentity, settings: model.settings, outsideFilters: model.selectedOutsideFilters) { model.selectedAddress = nil }
                        .frame(width: 256)
                }
            }
            Rectangle().fill(RadarStyle.line).frame(height: 1)
            status
        }
        .background(RadarStyle.background)
        .foregroundStyle(RadarStyle.green)
        .font(RadarStyle.mono)
        .tint(RadarStyle.green)
        .sheet(isPresented: $showingSettings) {
            RadarSettingsView(settings: model.settings, save: model.apply)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ADSB / RADAR").font(.system(size: 19, weight: .semibold, design: .monospaced)).tracking(2)
                Text(model.settings.source == .synthetic ? "SYNTHETIC / \(model.settings.scenario.rawValue.uppercased())" : model.settings.source == .online ? "ONLINE / ADSB.FI" : model.settings.source == .combined ? "LOCAL + ONLINE / ADSB.FI" : "LOCAL AIR PICTURE")
                    .font(.system(size: 10, design: .monospaced)).tracking(2)
                    .foregroundStyle(model.settings.source == .synthetic ? RadarStyle.amber : RadarStyle.muted)
            }
            Spacer(minLength: 8)
            Button { showingSettings = true } label: { Label("SETTINGS", systemImage: "slider.horizontal.3") }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                .padding(8)
                .overlay(Rectangle().stroke(RadarStyle.line, lineWidth: 1))
            }
            HStack(spacing: 24) {
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
            Menu {
                Text("\(model.contacts.count) received positioned contacts")
                if model.eligibleContacts.isEmpty { Text("No matching contacts") }
                ForEach(model.eligibleContacts) { contact in
                    Button(contact.observation.callsign ?? contact.observation.address.uppercased()) { model.selectedAddress = contact.id }
                }
            } label: { Label("CONTACTS", systemImage: "airplane") }
                .menuStyle(.borderlessButton).fixedSize()
            Spacer(minLength: 0)
            }
            if model.settings.aircraftFilters.isActive {
                Text(model.filterSummary).font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.amber)
            }
        }
        .padding(.leading, 80)
        .padding(.trailing, 24)
        .padding(.vertical, 12)
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

    private var status: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.feedHealth) { health in
                    FeedStatusIndicator(feed: health.feed, status: health.status,
                        scenario: model.settings.scenario) { Task { await model.retry(feed: health.feed) } }
                }
            }
            Spacer(minLength: 8)
            if model.showsOnlineAttribution {
                Link("adsb.fi", destination: URL(string: "https://adsb.fi")!).foregroundStyle(RadarStyle.muted)
            }
            let counts = model.contactCounts
            Text("\(counts.inView) IN VIEW  /  \(counts.outsideView) OUTSIDE VIEW  /  \(counts.filtered) FILTERED")
                .foregroundStyle(RadarStyle.green)
            Text("\(model.heardWithoutPosition) WITHOUT POSITION").foregroundStyle(RadarStyle.muted)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(RadarStyle.panel)
    }
}

private struct FeedStatusIndicator: View {
    let feed: AircraftFeed
    let status: ReceptionStatus
    let scenario: SyntheticScenario
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(2).foregroundStyle(color)
            if case .failed = status { Button("RETRY", action: retry) }
        }
    }
    private var color: Color {
        if case .failed = status { return RadarStyle.amber }
        return status == .receiving ? RadarStyle.green : RadarStyle.muted
    }
    private var text: String {
        let name = feed == .local ? "LOCAL" : feed == .online ? "ONLINE / ADSB.FI" : "SYNTHETIC \(scenario.rawValue.uppercased())"
        switch status {
        case .stopped: return "\(name) STOPPED"
        case .starting: return "STARTING \(name)"
        case .waiting: return "\(name) ACTIVE / WAITING FOR AIRCRAFT"
        case .receiving: return feed == .synthetic ? "\(name) / GENERATED TRAFFIC" : "\(name) ACTIVE"
        case .failed(let message): return "\(name): \(message)"
        }
    }

}

struct ContactInspector: View {
    let contact: PresentedContact
    let identity: AircraftIdentity?
    let settings: RadarSettings
    var outsideFilters: Bool = false
    let dismiss: () -> Void

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
                    Text(contact.observation.callsign ?? contact.observation.address.uppercased())
                        .font(.system(size: 23, weight: .medium, design: .monospaced))
                        .foregroundStyle(RadarStyle.bright)
                    Text("\(contact.observation.address.hasPrefix("~") ? "NON-ICAO" : "ICAO") \(contact.observation.address.uppercased())").font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
                if outsideFilters { Text("OUTSIDE FILTERS").foregroundStyle(RadarStyle.amber) }
                Rectangle().fill(RadarStyle.line).frame(height: 1)
                field("REGISTRATION", identity?.registration?.value ?? "UNKNOWN")
                field("AIRCRAFT TYPE", identity?.aircraftType?.value ?? "UNKNOWN")
                if let identity {
                    field("DETAILS UPDATED", identity.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "UNKNOWN")
                        .help("The oldest successful update of the known identity fields. Missing fields retain their previous dates.")
                    field("DETAILS FROM", Array(Set([identity.registration?.provider, identity.aircraftType?.provider].compactMap { $0 })).sorted().joined(separator: ", "))
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
        }
    }
}
