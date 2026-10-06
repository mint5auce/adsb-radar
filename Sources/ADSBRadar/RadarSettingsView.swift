import RadarCore
import SwiftUI

struct RadarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RadarSettings
    @State private var latitude: String
    @State private var longitude: String
    let model: RadarModel
    let save: (RadarSettings) -> Void

    init(model: RadarModel, save: @escaping (RadarSettings) -> Void) {
        let settings = model.settings
        draft = settings
        latitude = settings.receiver.map { String($0.latitude) } ?? ""
        longitude = settings.receiver.map { String($0.longitude) } ?? ""
        self.model = model
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RADAR SETTINGS").font(.system(size: 18, weight: .medium, design: .monospaced))
                Spacer()
            }.padding(24)
            Form {
                if model.settings.source != .synthetic {
                    Section("Reception") { ReceptionSettingsControls(model: model) }
                }
                Section("Aircraft data") {
                    Picker("Source", selection: $draft.source) {
                        Text("Local receiver").tag(AircraftSourceKind.local)
                        Text("Online / adsb.fi").tag(AircraftSourceKind.online)
                        Text("Local + Online").tag(AircraftSourceKind.combined)
                        Text("Synthetic / offline").tag(AircraftSourceKind.synthetic)
                    }
                    if draft.source.feeds.contains(.local) {
                        TextField("Missing receiver attempts", value: $draft.localReceiverAttemptLimit, format: .number)
                        Text("Includes the initial attempt. After this many missing-dongle failures, reception waits for Retry here.")
                            .foregroundStyle(.secondary)
                        if draft.localReceiverAttemptLimit < 1 {
                            Text("Enter at least one receiver attempt.").foregroundStyle(RadarStyle.amber)
                        }
                    }
                    if draft.source != .synthetic {
                        Toggle("Enrich aircraft details online", isOn: $draft.enrichIdentities)
                        TextField("Refresh aircraft details after (days)", value: $draft.identityRefreshDays, format: .number)
                            .help("From one hour (0.0417 days) to ten years (3650 days).")
                        Text("Known details remain available offline. Refresh happens when aircraft are encountered.").foregroundStyle(.secondary)
                        Text("Optional registration and aircraft type from adsb.fi, including in Local mode.").foregroundStyle(.secondary)
                        Link("Aircraft data from adsb.fi", destination: URL(string: "https://adsb.fi")!)
                    }
                    if draft.source == .synthetic {
                        Picker("Scenario", selection: $draft.scenario) {
                            Text("Test / lifecycle and missing data").tag(SyntheticScenario.test)
                            Text("Demo / clean traffic").tag(SyntheticScenario.demo)
                        }
                        if draft.scenario == .demo {
                            TextField("Demo aircraft (25 to 250)", value: $draft.demoCount, format: .number)
                            if !countValid { Text("Enter an aircraft count from 25 to 250.").foregroundStyle(RadarStyle.amber) }
                        }
                        Text("Generated traffic only. No dongle, decoder, or internet needed.").foregroundStyle(.secondary)
                        if draft.receiver == nil, latitude.isEmpty, longitude.isEmpty {
                            Text("Without a saved position, traffic uses the bundled example at 51.5, -2.5.").foregroundStyle(.secondary)
                        }
                    }
                }
                Section(draft.source == .online ? "Home location" : "Receiver position") {
                    TextField("Latitude", text: $latitude).accessibilityIdentifier("receiver-latitude")
                    TextField("Longitude", text: $longitude).accessibilityIdentifier("receiver-longitude")
                    Text("The sweep and range rings stay anchored here.").foregroundStyle(.secondary)
                    if !locationValid { Text("Enter latitude from -90 to 90 and longitude from -180 to 180.").foregroundStyle(RadarStyle.amber) }
                }
                if draft.source.usesOnline {
                    Section("Online feed") {
                        Stepper("Refresh: \(Int(draft.onlineRefreshSeconds)) seconds", value: $draft.onlineRefreshSeconds, in: 1...300)
                        TextField("Search limit (\(draft.distanceSymbol))", value: onlineRadiusBinding, format: .number)
                        Text("Maximum: \(draft.distance(250)). Shared allowance: one request per second.").foregroundStyle(.secondary)
                    }
                }
                Section("Control visibility") {
                    Picker("Show controls", selection: Binding(get: { model.settings.controlVisibility }, set: { mode in
                        draft.controlVisibility = mode
                        var settings = model.settings
                        settings.controlVisibility = mode
                        save(settings)
                    })) {
                        ForEach(ControlVisibilityMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text("Applies immediately. Bars start visible for 15 seconds unless Always visible is selected.")
                        .foregroundStyle(.secondary)
                }
                Section("Presentation") {
                    Picker("Contact updates", selection: $draft.mode) {
                        Text("Sweep-timed").tag(UpdateMode.sweep)
                        Text("Immediate").tag(UpdateMode.immediate)
                    }
                    Stepper("Sweep revolution: \(draft.sweepSeconds.formatted()) seconds", value: $draft.sweepSeconds, in: 0.5...30, step: 0.5)
                    TextField("Initial radius (\(draft.distanceSymbol))", value: radiusBinding, format: .number)
                    Stepper("Trail history: \(Int(draft.trailSeconds)) seconds", value: $draft.trailSeconds, in: 5...600, step: 5)
                }
                Section("Position freshness") {
                    Stepper("Stale after: \(Int(draft.staleSeconds)) seconds", value: $draft.staleSeconds, in: 1...300)
                    Stepper("Remove after: \(Int(draft.removalSeconds)) seconds", value: $draft.removalSeconds, in: draft.staleSeconds...900)
                    Text("Both thresholds count from the last position observation.").foregroundStyle(.secondary)
                }
                Section("Units") {
                    Picker("Altitude", selection: $draft.altitudeUnit) {
                        Text("Feet").tag(AltitudeUnit.feet)
                        Text("Metres").tag(AltitudeUnit.metres)
                    }
                    Picker("Speed", selection: $draft.speedUnit) {
                        Text("Knots").tag(SpeedUnit.knots)
                        Text("Kilometres per hour").tag(SpeedUnit.kilometresPerHour)
                        Text("Miles per hour").tag(SpeedUnit.milesPerHour)
                    }
                    Picker("Distance", selection: $draft.distanceUnit) {
                        Text("Nautical miles").tag(DistanceUnit.nauticalMiles)
                        Text("Kilometres").tag(DistanceUnit.kilometres)
                        Text("Miles").tag(DistanceUnit.miles)
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: draft.staleSeconds) { draft.removalSeconds = max(draft.removalSeconds, draft.staleSeconds) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain).padding(8).overlay(Rectangle().stroke(RadarStyle.line))
                Spacer()
                Button("Save settings", action: saveSettings).keyboardShortcut(.defaultAction)
                    .disabled(!locationValid || !countValid || (draft.source.feeds.contains(.local) && draft.localReceiverAttemptLimit < 1))
                    .buttonStyle(.plain).padding(8).background(RadarStyle.green.opacity(0.12))
                    .overlay(Rectangle().stroke(RadarStyle.line))
            }.padding(24)
        }
        .frame(width: 560, height: 680)
        .background(RadarStyle.panel)
        .foregroundStyle(RadarStyle.green)
        .font(RadarStyle.mono)
        .preferredColorScheme(.dark)
        .tint(RadarStyle.green)
    }

    private var radiusBinding: Binding<Double> {
        Binding(get: { draft.distanceValue(draft.initialRadiusNM) }, set: { draft.initialRadiusNM = $0 / draft.distanceValue(1) })
    }

    private var onlineRadiusBinding: Binding<Double> {
        Binding(get: { draft.distanceValue(draft.onlineRadiusNM) }, set: { draft.onlineRadiusNM = $0 / draft.distanceValue(1) })
    }

    private var locationValid: Bool {
        if latitude.isEmpty, longitude.isEmpty { return !draft.source.usesOnline }
        guard let lat = Double(latitude), let lon = Double(longitude) else { return false }
        return GeographicCoordinate(latitude: lat, longitude: lon) != nil
    }

    private var countValid: Bool {
        draft.source != .synthetic || draft.scenario != .demo || (25...250).contains(draft.demoCount)
    }

    private func saveSettings() {
        if let lat = Double(latitude), let lon = Double(longitude) {
            draft.receiver = GeographicCoordinate(latitude: lat, longitude: lon)
        } else { draft.receiver = nil }
        save(draft)
        dismiss()
    }
}

private struct ReceptionSettingsControls: View {
    let model: RadarModel

    var body: some View {
        ForEach(model.feedHealth) { health in
            VStack(alignment: .leading, spacing: 8) {
                Text(health.feed == .local ? "Local receiver" : "Online / adsb.fi")
                Text(message(health.status))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(hasFailed(health.status) ? RadarStyle.amber : RadarStyle.muted)
                if health.feed == .local, model.localReceptionPaused {
                    Text("Automatic attempts stopped.").foregroundStyle(RadarStyle.amber)
                }
                Button(health.feed == .local ? "Retry Local receiver" : "Retry Online feed") {
                    Task { await model.retry(feed: health.feed) }
                }
                .disabled(!hasFailed(health.status))
            }
        }
        Text("Save settings to apply source or attempt-limit changes.").foregroundStyle(.secondary)
    }

    private func hasFailed(_ status: ReceptionStatus) -> Bool {
        if case .failed = status { return true }
        return false
    }

    private func message(_ status: ReceptionStatus) -> String {
        switch status {
        case .stopped: "Stopped"
        case .starting: "Starting reception"
        case .waiting: "Active / waiting for aircraft"
        case .receiving: "Active"
        case .failed(let message): message
        }
    }
}
