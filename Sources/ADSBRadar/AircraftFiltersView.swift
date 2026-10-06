import RadarCore
import SwiftUI

struct AircraftFiltersView: View {
    @Bindable var model: RadarModel
    @State private var distanceText: String
    @State private var minimumText: String
    @State private var maximumText: String
    @State private var error: String?
    @FocusState private var altitudeFocused: AltitudeField?
    private enum AltitudeField: Hashable { case minimum, maximum }
    @FocusState private var distanceFocused: Bool

    init(model: RadarModel) {
        self.model = model
        _minimumText = State(initialValue: model.settings.aircraftFilters.minimumAltitudeFeet.map { Self.number($0 * (model.settings.altitudeUnit == .feet ? 1 : 0.3048)) } ?? "")
        _maximumText = State(initialValue: model.settings.aircraftFilters.maximumAltitudeFeet.map { Self.number($0 * (model.settings.altitudeUnit == .feet ? 1 : 0.3048)) } ?? "")
        _distanceText = State(initialValue: Self.number(model.settings.distanceValue(model.settings.aircraftFilters.homeDistanceNM ?? 50)))
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AIRCRAFT FILTERS").font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
                Button("Clear filters") { error = nil; model.clearAircraftFilters() }
            }
            Text(model.filterSummary).foregroundStyle(RadarStyle.muted).font(.system(size: 11, design: .monospaced))
            Divider()
            if let error { Text(error).foregroundStyle(RadarStyle.amber).font(.system(size: 11, design: .monospaced)) }
            distanceControls
            Divider()
            altitudeControls
        }
        .padding(20)
        }
        .frame(width: 400, height: 460)
        .background(RadarStyle.panel).foregroundStyle(RadarStyle.green).tint(RadarStyle.green)
        .onChange(of: distanceFocused) { if !distanceFocused { commitDistance() } }
        .onChange(of: altitudeFocused) { old, _ in if old != nil { commitAltitude() } }
        .onChange(of: model.settings.altitudeUnit) { updateAltitudeText() }
        .onChange(of: model.settings.aircraftFilters.minimumAltitudeFeet) { updateAltitudeText() }
        .onChange(of: model.settings.aircraftFilters.maximumAltitudeFeet) { updateAltitudeText() }
        .onChange(of: model.settings.distanceUnit) { updateDistanceText() }
        .onChange(of: model.settings.aircraftFilters.homeDistanceNM) { updateDistanceText() }
    }

    private var distanceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Limit distance from Home", isOn: Binding(get: { model.settings.aircraftFilters.homeDistanceNM != nil }, set: { enabled in
                if enabled { commitDistance(enable: true) }
                else { var filters = model.settings.aircraftFilters; filters.homeDistanceNM = nil; model.setAircraftFilters(filters); error = nil }
            })).disabled(model.settings.receiver == nil)
            HStack {
                TextField("Distance", text: $distanceText).textFieldStyle(.roundedBorder)
                    .focused($distanceFocused).onSubmit { commitDistance(enable: true) }
                    .accessibilityLabel("Home distance")
                Text(model.settings.distanceSymbol).frame(width: 28, alignment: .leading)
            }.disabled(model.settings.receiver == nil)
            HStack {
                ForEach([25.0, 50, 100], id: \.self) { distance in
                    Button(model.settings.distance(distance)) {
                        var filters = model.settings.aircraftFilters; filters.homeDistanceNM = distance
                        model.setAircraftFilters(filters); error = nil
                    }
                }
            }.disabled(model.settings.receiver == nil)
            Text(model.settings.receiver == nil ? "Set Home in Settings to use distance filtering." : "Anchored to saved Home, independently of map pan.")
                .font(.system(size: 11)).foregroundStyle(RadarStyle.muted)
        }
    }

    private var altitudeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reported altitude").font(.system(size: 12, weight: .medium))
            HStack {
                VStack(alignment: .leading) {
                    Text("Minimum").font(.system(size: 11))
                    TextField("Unrestricted", text: $minimumText).textFieldStyle(.roundedBorder)
                        .focused($altitudeFocused, equals: .minimum).onSubmit { commitAltitude() }
                        .accessibilityLabel("Minimum reported altitude")
                }
                VStack(alignment: .leading) {
                    Text("Maximum").font(.system(size: 11))
                    TextField("Unrestricted", text: $maximumText).textFieldStyle(.roundedBorder)
                        .focused($altitudeFocused, equals: .maximum).onSubmit { commitAltitude() }
                        .accessibilityLabel("Maximum reported altitude")
                }
                Text(model.settings.altitudeUnit == .feet ? "FT" : "M")
            }
            Toggle("Include unknown altitude", isOn: filterBinding(\.includeUnknownAltitude))
            Toggle("Hide ground aircraft", isOn: filterBinding(\.hideGround))
            Text("A numeric altitude range excludes Ground. Reported altitude is not height above terrain.")
                .font(.system(size: 11)).foregroundStyle(RadarStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func filterBinding(_ keyPath: WritableKeyPath<AircraftViewFilters, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings.aircraftFilters[keyPath: keyPath] }, set: { value in
            var filters = model.settings.aircraftFilters; filters[keyPath: keyPath] = value
            model.setAircraftFilters(filters)
        })
    }

    private func commitAltitude() {
        func parsed(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let minBlank = minimumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let maxBlank = maximumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard (minBlank || parsed(minimumText)?.isFinite == true), (maxBlank || parsed(maximumText)?.isFinite == true) else {
            error = "Enter a valid reported altitude or leave the limit blank."; return
        }
        let factor = model.settings.altitudeUnit == .feet ? 1.0 : 0.3048
        var filters = model.settings.aircraftFilters
        filters.minimumAltitudeFeet = minBlank ? nil : parsed(minimumText).map { $0 / factor }
        filters.maximumAltitudeFeet = maxBlank ? nil : parsed(maximumText).map { $0 / factor }
        if let message = filters.validationMessage { error = message; return }
        model.setAircraftFilters(filters); error = nil
    }

    private func updateAltitudeText() {
        let factor = model.settings.altitudeUnit == .feet ? 1.0 : 0.3048
        minimumText = model.settings.aircraftFilters.minimumAltitudeFeet.map { Self.number($0 * factor) } ?? ""
        maximumText = model.settings.aircraftFilters.maximumAltitudeFeet.map { Self.number($0 * factor) } ?? ""
    }

    private func commitDistance(enable: Bool = false) {
        guard model.settings.receiver != nil, enable || model.settings.aircraftFilters.homeDistanceNM != nil else { return }
        guard let entered = Double(distanceText), entered.isFinite, entered > 0 else {
            error = "Enter a positive Home distance."; return
        }
        var filters = model.settings.aircraftFilters
        filters.homeDistanceNM = entered / model.settings.distanceValue(1)
        model.setAircraftFilters(filters); error = nil
    }
    private func updateDistanceText() {
        distanceText = Self.number(model.settings.distanceValue(model.settings.aircraftFilters.homeDistanceNM ?? 50))
    }
    private static func number(_ value: Double) -> String { String(format: "%.4g", value) }
}
