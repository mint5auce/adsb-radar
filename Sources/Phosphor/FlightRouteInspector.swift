import RadarCore
import SwiftUI

struct FlightRouteInspector: View {
    let state: FlightRouteLookupState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(RadarStyle.line).frame(height: 1)
            Text("LIKELY ROUTE")
                .font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(RadarStyle.muted)
            if state == .lookingUp {
                Text("Looking up…").font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
            }
            field("DEPARTURE", state.match?.route.airports.first?.displayName ?? "UNKNOWN")
            if let match = state.match {
                if match.route.airports.count > 2 {
                    field("VIA", match.route.airports.dropFirst().dropLast().map(\.displayName).joined(separator: "\n\n"))
                    Text("May cover multiple legs.")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
            }
            field("DESTINATION", state.match?.route.airports.last?.displayName ?? "UNKNOWN")
            if let match = state.match {
                VStack(alignment: .leading, spacing: 6) {
                    Link(match.route.provider, destination: match.route.sourceURL)
                    Text("Looked up \(match.lookedUpAt.formatted(date: .abbreviated, time: .shortened))")
                    if match.cached { Text("Cached for this session") }
                }
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(RadarStyle.line).frame(height: 1)
        }
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(RadarStyle.muted)
            Text(value)
                .font(.system(size: 13, design: .monospaced)).foregroundStyle(RadarStyle.green)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
