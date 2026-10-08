import RadarCore
import SwiftUI

struct FlightRouteInspector: View {
    let state: FlightRouteLookupState
    @State private var disclosure = FlightRouteDisclosure()

    private var heading: String {
        switch state {
        case .unknown: "LIKELY ROUTE - UNKNOWN"
        case .lookingUp: "LIKELY ROUTE - LOOKING UP…"
        case .matched: "LIKELY ROUTE"
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { disclosure.isExpanded(for: state) }, set: { disclosure.setExpanded($0) })) {
            VStack(alignment: .leading, spacing: 24) {
                InspectorField(title: "DEPARTURE", value: state.match?.route.airports.first?.displayName ?? "UNKNOWN")
                if let match = state.match, match.route.airports.count > 2 {
                    InspectorField(title: "VIA", value: match.route.airports.dropFirst().dropLast().map(\.displayName).joined(separator: "\n\n"))
                }
                InspectorField(title: "DESTINATION", value: state.match?.route.airports.last?.displayName ?? "UNKNOWN")
            }
        } label: {
            Text(heading).font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(RadarStyle.muted)
        }
        .disclosureGroupStyle(RadarRouteDisclosureStyle())
        .help("Callsign database match, not a confirmed current flight or diversion. Show or hide likely route details.")
    }
}

/// An explicit user choice wins over automatic defaults as lookup state changes.
struct FlightRouteDisclosure {
    private var manualExpansion: Bool?

    func isExpanded(for state: FlightRouteLookupState) -> Bool {
        manualExpansion ?? (state.match != nil)
    }

    mutating func setExpanded(_ expanded: Bool) { manualExpansion = expanded }
}

private struct RadarRouteDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    configuration.label
                    Spacer(minLength: 0)
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(RadarStyle.muted)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}
