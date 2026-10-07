import RadarCore
import SwiftUI

struct MapLayerControls: View {
    @Bindable var model: RadarModel
    @State private var showingData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MAP LAYERS").foregroundStyle(RadarStyle.muted)
            layer("Routes", key: \.routes)
            layer("Airspace", key: \.airspace)
            layer("Airports", key: \.airports)
            AirportFilterControls(filters: Binding(get: { model.settings.mapLayers.airportFilters }, set: { filters in
                var settings = model.settings
                settings.mapLayers.airportFilters = filters
                model.apply(settings)
            }))
            .padding(.leading, 20)
            .disabled(!model.settings.mapLayers.airports)
            Divider().overlay(RadarStyle.line)
            MapAltitudeControl(model: model)
            Divider().overlay(RadarStyle.line)
            Button { showingData.toggle() } label: { Label("Map data and updates", systemImage: "info.circle") }
                .buttonStyle(.plain)
                .popover(isPresented: $showingData) { MapDataView(model: model) }
        }
        .padding(20)
        .font(RadarStyle.mono)
        .foregroundStyle(RadarStyle.green)
        .tint(RadarStyle.green)
        .background(RadarStyle.panel)
    }

    private func layer(_ title: String, key: WritableKeyPath<MapLayerPreferences, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.settings.mapLayers[keyPath: key] }, set: { enabled in
            var settings = model.settings
            settings.mapLayers[keyPath: key] = enabled
            model.apply(settings)
        }))
        .toggleStyle(.checkbox)
    }
}

struct MapAltitudeControl: View {
    @Bindable var model: RadarModel
    @State private var entry = ""
    @State private var invalid = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AIRSPACE LEVEL").foregroundStyle(RadarStyle.muted)
            Button("All levels") { set(nil) }
            HStack {
                ForEach([50, 100, 200, 300], id: \.self) { level in Button("FL \(level)") { set(level) } }
            }
            HStack {
                Text("FL")
                TextField("0-660", text: $entry).textFieldStyle(.roundedBorder).frame(width: 70).onSubmit(commit)
                    .accessibilityLabel("Flight level")
                Button("Apply", action: commit)
                Button { set(max(0, (model.settings.mapLayers.flightLevel ?? 100) - 10)) } label: { Image(systemName: "minus") }.accessibilityLabel("Decrease flight level by ten")
                Button { set(min(660, (model.settings.mapLayers.flightLevel ?? 100) + 10)) } label: { Image(systemName: "plus") }.accessibilityLabel("Increase flight level by ten")
            }
            if invalid { Text("Enter a whole flight level from 0 to 660.").foregroundStyle(RadarStyle.amber) }
            Text("Routes and airspace only.\nUncertain limits remain dimly visible.")
                .foregroundStyle(RadarStyle.muted).font(.system(size: 11, design: .monospaced))
        }
        .font(RadarStyle.mono).frame(width: 370).background(RadarStyle.panel)
        .onAppear { entry = model.settings.mapLayers.flightLevel.map(String.init) ?? "100" }
    }
    private func commit() {
        var settings = model.settings
        guard settings.mapLayers.setFlightLevel(entry) else { invalid = true; return }
        invalid = false; model.apply(settings)
    }
    private func set(_ level: Int?) {
        var settings = model.settings; settings.mapLayers.flightLevel = level; model.apply(settings)
        if let level { entry = String(level) }; invalid = false
    }
}

struct MapDataView: View {
    @Bindable var model: RadarModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MAP DATA / UK").foregroundStyle(RadarStyle.bright)
            ForEach(MapProvider.allCases, id: \.self) { provider in
                VStack(alignment: .leading, spacing: 7) {
                    Text(provider.title).foregroundStyle(RadarStyle.green)
                    if let snapshot = model.mapLayers.snapshots.first(where: { $0.provider == provider }) {
                        Text("\(provider == .nats ? "EFFECTIVE" : "SNAPSHOT")  \(snapshot.date)")
                        Text(snapshot.coverage)
                        Text(snapshot.terms)
                        if let url = URL(string: snapshot.sourceURL) { Link("Source and terms", destination: url) }
                    }
                    if let message = model.mapLayers.messages[provider] { Text(message).foregroundStyle(RadarStyle.green).textSelection(.enabled) }
                }
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
            }
            Button(model.mapLayers.updating ? "Checking map updates…" : "Check for map updates") {
                Task { await model.checkForMapUpdates() }
            }.disabled(model.mapLayers.updating || model.mapLayers.loading)
            Text("Bundled or last downloaded data works offline.").font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
        }
        .padding(24).frame(width: 410).background(RadarStyle.panel)
    }
}

struct MapFeatureInspector: View {
    let feature: MapFeature
    let snapshot: MapSnapshot?
    let preferences: MapLayerPreferences
    let dismiss: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(feature.kind == .route ? "ATS ROUTE" : feature.kind == .airspace ? "CONTROLLED AIRSPACE" : "AIRPORT")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                    Spacer()
                    Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Deselect map feature")
                }
                Text(feature.name).font(.system(size: feature.kind == .route ? 25 : 19, weight: .medium, design: .monospaced)).foregroundStyle(RadarStyle.bright)
                Rectangle().fill(RadarStyle.line).frame(height: 1)
                if feature.kind != .airport {
                    field("FLOOR", feature.lower.description); field("CEILING", feature.upper.description)
                    if feature.slice(at: preferences.flightLevel) == .uncertain { field("SLICE STATUS", "Uncertain") }
                }
                ForEach(Array(feature.inspectionDetails.enumerated()), id: \.offset) { _, detail in field(detail.title, detail.value) }
                if let snapshot {
                    field("SOURCE", snapshot.provider.title)
                    field(snapshot.provider == .nats ? "EFFECTIVE" : "SNAPSHOT", snapshot.date)
                }
                if feature.kind == .airspace {
                    Text("Published boundary. Current activation is not represented.").font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RadarStyle.panel)
        .overlay(alignment: .leading) { Rectangle().fill(RadarStyle.line).frame(width: 1) }
    }
    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
            Text(value).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
        }
    }
}
