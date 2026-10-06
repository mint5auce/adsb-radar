import RadarCore
import SwiftUI

struct RadarWindow: View {
    @Bindable var model: RadarModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(RadarStyle.line).frame(height: 1)
            HStack(spacing: 0) {
                RadarSurface(model: model, openSettings: { showingSettings = true })
                if let contact = model.selectedContact {
                    ContactInspector(contact: contact, settings: model.settings) { model.selectedAddress = nil }
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
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ADSB / RADAR").font(.system(size: 19, weight: .semibold, design: .monospaced)).tracking(2)
                Text(model.settings.source == .synthetic ? "SYNTHETIC / \(model.settings.scenario.rawValue.uppercased())" : model.settings.source == .online ? "ONLINE / ADSB.FI" : "LOCAL AIR PICTURE")
                    .font(.system(size: 10, design: .monospaced)).tracking(2)
                    .foregroundStyle(model.settings.source == .synthetic ? RadarStyle.amber : RadarStyle.muted)
            }
            Spacer(minLength: 8)
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
            Menu {
                if model.contacts.isEmpty { Text("No positioned contacts") }
                ForEach(model.contacts) { contact in
                    Button(contact.observation.callsign ?? contact.id.uppercased()) { model.selectedAddress = contact.id }
                }
            } label: { Label("CONTACTS", systemImage: "airplane") }
                .menuStyle(.borderlessButton).fixedSize()
            Button { showingSettings = true } label: { Label("SETTINGS", systemImage: "slider.horizontal.3") }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                .padding(8)
                .overlay(Rectangle().stroke(RadarStyle.line, lineWidth: 1))
        }
        .padding(.leading, 80)
        .padding(.trailing, 24)
        .padding(.vertical, 20)
    }

    private var status: some View {
        HStack(spacing: 16) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).lineLimit(2).foregroundStyle(statusColor)
            if case .failed = model.reception {
                Button("RETRY") { Task { await model.retry() } }
                    .disabled(model.retrying)
            }
            Spacer(minLength: 8)
            if model.settings.source == .online {
                Link("adsb.fi", destination: URL(string: "https://adsb.fi")!).foregroundStyle(RadarStyle.muted)
            }
            Text("\(model.contacts.count) POSITIONED").foregroundStyle(RadarStyle.green)
            Text("\(model.heardWithoutPosition) WITHOUT POSITION").foregroundStyle(RadarStyle.muted)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(RadarStyle.panel)
    }

    private var statusColor: Color {
        if case .failed = model.reception { return RadarStyle.amber }
        return model.reception == .receiving ? RadarStyle.green : RadarStyle.muted
    }

    private var statusText: String {
        if model.settings.source == .synthetic {
            switch model.reception {
            case .stopped: return "SYNTHETIC STOPPED"
            case .starting: return "STARTING SYNTHETIC \(model.settings.scenario.rawValue.uppercased())"
            case .waiting, .receiving:
                return "SYNTHETIC \(model.settings.scenario.rawValue.uppercased()) / GENERATED TRAFFIC"
            case .failed(let message): return message
            }
        }
        if model.settings.source == .online {
            switch model.reception {
            case .stopped: return "ONLINE STOPPED"
            case .starting: return "CONNECTING TO ADSB.FI"
            case .waiting: return "ONLINE ACTIVE / WAITING FOR AIRCRAFT"
            case .receiving: return "ONLINE / ADSB.FI ACTIVE"
            case .failed(let message): return message
            }
        }
        switch model.reception {
        case .stopped: return "RECEPTION STOPPED"
        case .starting: return "STARTING LOCAL RECEPTION"
        case .waiting: return "RECEIVER ACTIVE / WAITING FOR AIRCRAFT"
        case .receiving: return "LOCAL RECEPTION ACTIVE"
        case .failed(let message): return message
        }
    }
}

struct ContactInspector: View {
    let contact: PresentedContact
    let settings: RadarSettings
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
                    Text(contact.observation.callsign ?? contact.id.uppercased())
                        .font(.system(size: 23, weight: .medium, design: .monospaced))
                        .foregroundStyle(RadarStyle.bright)
                    Text("ICAO \(contact.id.uppercased())").font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
                Rectangle().fill(RadarStyle.line).frame(height: 1)
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
