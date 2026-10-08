import RadarCore
import SwiftUI

/// A separate invalidation boundary keeps radar redraws from resetting native submenu tracking.
struct RadarPresentationMenu: View {
    let model: RadarModel

    var body: some View {
        let labelMode = model.settings.labelMode
        let trailMode = model.settings.trailMode
        let directionVectors = model.settings.directionVectors
        Menu {
            Picker("Labels", selection: Binding(get: { labelMode }, set: { value in
                var settings = model.settings; settings.labelMode = value; model.apply(settings)
            })) {
                ForEach(AircraftLabelMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Trails", selection: Binding(get: { trailMode }, set: { value in
                var settings = model.settings; settings.trailMode = value; model.apply(settings)
            })) {
                ForEach(AircraftTrailMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Direction vectors", isOn: Binding(get: { directionVectors }, set: { value in
                var settings = model.settings; settings.directionVectors = value; model.apply(settings)
            }))
        } label: { Label("VIEW", systemImage: "eye") }
        .menuStyle(.borderlessButton).fixedSize()
    }
}
