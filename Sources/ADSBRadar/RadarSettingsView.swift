import RadarCore
import SwiftUI

struct RadarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RadarSettings
    @State private var latitude: String
    @State private var longitude: String
    let save: (RadarSettings) -> Void

    init(settings: RadarSettings, save: @escaping (RadarSettings) -> Void) {
        draft = settings
        latitude = settings.receiver.map { String($0.latitude) } ?? ""
        longitude = settings.receiver.map { String($0.longitude) } ?? ""
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("RADAR SETTINGS").font(.system(size: 18, weight: .medium, design: .monospaced))
                Spacer()
            }.padding(24)
            Form {
                Section("Receiver position") {
                    TextField("Latitude", text: $latitude).accessibilityIdentifier("receiver-latitude")
                    TextField("Longitude", text: $longitude).accessibilityIdentifier("receiver-longitude")
                    Text("The sweep and range rings stay anchored here.").foregroundStyle(.secondary)
                    if !locationValid { Text("Enter latitude from -90 to 90 and longitude from -180 to 180.").foregroundStyle(RadarStyle.amber) }
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
                Spacer()
                Button("Save settings", action: saveSettings).keyboardShortcut(.defaultAction).disabled(!locationValid)
            }.padding(24)
        }
        .frame(width: 560, height: 680)
        .preferredColorScheme(.dark)
        .tint(RadarStyle.green)
    }

    private var radiusBinding: Binding<Double> {
        Binding(get: { draft.distanceValue(draft.initialRadiusNM) }, set: { draft.initialRadiusNM = $0 / draft.distanceValue(1) })
    }

    private var locationValid: Bool {
        if latitude.isEmpty, longitude.isEmpty { return true }
        guard let lat = Double(latitude), let lon = Double(longitude) else { return false }
        return GeographicCoordinate(latitude: lat, longitude: lon) != nil
    }

    private func saveSettings() {
        if let lat = Double(latitude), let lon = Double(longitude) {
            draft.receiver = GeographicCoordinate(latitude: lat, longitude: lon)
        } else { draft.receiver = nil }
        save(draft)
        dismiss()
    }
}
