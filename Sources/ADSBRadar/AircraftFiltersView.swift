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
        _minimumText = State(initialValue: Self.altitudeText(model.settings.aircraftFilters.minimumAltitudeFeet, settings: model.settings))
        _maximumText = State(initialValue: Self.altitudeText(model.settings.aircraftFilters.maximumAltitudeFeet, settings: model.settings))
        _distanceText = State(initialValue: Self.number(model.settings.distanceValue(model.settings.aircraftFilters.homeDistanceNM ?? 50)))
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AIRCRAFT FILTERS").font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
                Button("Clear filters") { applyPreset(.overview) }
            }
            Text(model.filterSummary).foregroundStyle(RadarStyle.muted).font(.system(size: 11, design: .monospaced))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(AircraftViewPreset.allCases, id: \.self) { preset in
                    Button(preset.title) { applyPreset(preset) }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        .tint(model.settings.aircraftFilters == preset.filters ? RadarStyle.green : RadarStyle.muted)
                }
            }
            Divider()
            if let error { Text(error).foregroundStyle(RadarStyle.amber).font(.system(size: 11, design: .monospaced)) }
            distanceControls
            Divider()
            altitudeControls
            Divider()
            AircraftCategoryControls(model: model)
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
        let factor = model.settings.altitudeValue(1)
        var filters = model.settings.aircraftFilters
        if minimumText == Self.altitudeText(filters.minimumAltitudeFeet, settings: model.settings),
           maximumText == Self.altitudeText(filters.maximumAltitudeFeet, settings: model.settings) { error = nil; return }
        filters.minimumAltitudeFeet = minBlank ? nil : parsed(minimumText).map { $0 / factor }
        filters.maximumAltitudeFeet = maxBlank ? nil : parsed(maximumText).map { $0 / factor }
        if let message = filters.validationMessage { error = message; return }
        model.setAircraftFilters(filters); error = nil
    }

    private func updateAltitudeText() {
        minimumText = Self.altitudeText(model.settings.aircraftFilters.minimumAltitudeFeet, settings: model.settings)
        maximumText = Self.altitudeText(model.settings.aircraftFilters.maximumAltitudeFeet, settings: model.settings)
    }

    private func applyPreset(_ preset: AircraftViewPreset) {
        model.applyAircraftPreset(preset)
        updateDistanceText(); updateAltitudeText()
        error = nil
        distanceFocused = false; altitudeFocused = nil
    }

    private func commitDistance(enable: Bool = false) {
        guard model.settings.receiver != nil, enable || model.settings.aircraftFilters.homeDistanceNM != nil else { return }
        guard let entered = Double(distanceText), entered.isFinite, entered > 0 else {
            error = "Enter a positive Home distance."; return
        }
        var filters = model.settings.aircraftFilters
        if let current = filters.homeDistanceNM, distanceText == Self.number(model.settings.distanceValue(current)) { error = nil; return }
        filters.homeDistanceNM = entered / model.settings.distanceValue(1)
        model.setAircraftFilters(filters); error = nil
    }
    private func updateDistanceText() {
        distanceText = Self.number(model.settings.distanceValue(model.settings.aircraftFilters.homeDistanceNM ?? 50))
    }
    private static func altitudeText(_ feet: Double?, settings: RadarSettings) -> String {
        feet.map { number(settings.altitudeValue($0)) } ?? ""
    }
    private static func number(_ value: Double) -> String {
        String(format: "%.12g", value)
    }
}

struct AircraftCategoryControls: View {
    @Bindable var model: RadarModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reported category").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("All") { var filters = model.settings.aircraftFilters; filters.categories = Set(AircraftCategoryGroup.allCases); model.setAircraftFilters(filters) }
                Button("Larger aircraft") { var filters = model.settings.aircraftFilters; filters.categories = AircraftCategoryGroup.largerAircraft; model.setAircraftFilters(filters) }
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(AircraftCategoryGroup.allCases, id: \.self) { group in
                    Toggle(group.title, isOn: Binding(get: { model.settings.aircraftFilters.categories.contains(group) }, set: { included in
                        var filters = model.settings.aircraftFilters
                        if included { filters.categories.insert(group) } else { filters.categories.remove(group) }
                        model.setAircraftFilters(filters)
                    }))
                }
            }
            Toggle("Include unknown category", isOn: Binding(get: { model.settings.aircraftFilters.includeUnknownCategory }, set: { value in
                var filters = model.settings.aircraftFilters; filters.includeUnknownCategory = value; model.setAircraftFilters(filters)
            }))
            Text("Larger includes Small, Large, and Heavy (A2-A5), including larger business jets. Category does not establish commercial or private operation.")
                .font(.system(size: 11)).foregroundStyle(RadarStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

}
