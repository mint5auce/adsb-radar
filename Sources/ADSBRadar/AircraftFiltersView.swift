import RadarCore
import SwiftUI

struct AircraftFiltersView: View {
    @Bindable var model: RadarModel
    @State private var distanceText: String
    @State private var error: String?
    @FocusState private var distanceFocused: Bool

    init(model: RadarModel) {
        self.model = model
        _distanceText = State(initialValue: Self.number(model.settings.distanceValue(model.settings.aircraftFilters.homeDistanceNM ?? 50)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AIRCRAFT FILTERS").font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
                Button("Clear filters") { error = nil; model.clearAircraftFilters() }
            }
            Text(model.filterSummary).foregroundStyle(RadarStyle.muted).font(.system(size: 11, design: .monospaced))
            Divider()
            distanceControls
            if let error { Text(error).foregroundStyle(RadarStyle.amber).font(.system(size: 11, design: .monospaced)) }
        }
        .padding(20).frame(width: 360)
        .background(RadarStyle.panel).foregroundStyle(RadarStyle.green).tint(RadarStyle.green)
        .onChange(of: distanceFocused) { if !distanceFocused { commitDistance() } }
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
