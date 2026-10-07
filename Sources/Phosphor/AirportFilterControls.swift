import RadarCore
import SwiftUI

struct AirportFilterControls: View {
    @Binding var filters: AirportFilters

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ForEach(AirportSize.allCases, id: \.self) { size in
                    Toggle(size.title, isOn: Binding(get: { filters.sizes.contains(size) }, set: { enabled in
                        if enabled { filters.sizes.insert(size) } else { filters.sizes.remove(size) }
                    }))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(size.title) airports")
                }
            }
            Picker(selection: $filters.service) {
                ForEach(AirportServiceFilter.allCases, id: \.self) { service in
                    Text(service.title).tag(service)
                }
            } label: { Text("Scheduled service") }
            .pickerStyle(.menu)
            Toggle("Include unknown", isOn: $filters.includeUnknownService)
                .toggleStyle(.checkbox)
                .disabled(filters.service == .all)
                .help("Include airports with unknown service information when filtering by scheduled service.")
            if filters.sizes.isEmpty {
                Text("No airport sizes selected.").foregroundStyle(RadarStyle.amber)
            }
        }
    }
}
