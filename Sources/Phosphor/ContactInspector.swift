import RadarCore
import SwiftUI

struct ContactInspector: View {
    let contact: PresentedContact
    let identity: AircraftIdentity?
    let settings: RadarSettings
    var route: FlightRouteLookupState = .unknown
    var category: AircraftCategoryValue? = nil
    var showOnMap: (() -> Void)? = nil
    var outsideFilters: Bool = false
    let dismiss: () -> Void

    private var identifiers: AircraftIdentifiers {
        AircraftIdentifiers(observation: contact.observation, identity: identity, preferred: settings.aircraftIdentifier)
    }

    var body: some View {
        ScrollView { content }
            .frame(maxHeight: .infinity)
            .background(RadarStyle.panel)
            .overlay(alignment: .leading) { Rectangle().fill(RadarStyle.line).frame(width: 1) }
    }

    // The same content is rendered without a scroll viewport in native verification previews.
    var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Text(contact.stale ? "CONTACT / STALE" : "CONTACT")
                    .font(.system(size: 10, design: .monospaced)).tracking(1)
                    .foregroundStyle(contact.stale ? RadarStyle.amber : RadarStyle.muted)
                Spacer(minLength: 0)
                if let showOnMap {
                    Button(action: showOnMap) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 14))
                            .frame(width: 20, height: 20).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(RadarStyle.green)
                    .accessibilityLabel("Show on map").help("Show selected aircraft on map")
                }
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 12))
                        .frame(width: 16, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(RadarStyle.muted)
                .accessibilityLabel("Deselect aircraft").help("Deselect aircraft")
            }
            VStack(alignment: .leading, spacing: 8) {
                ContactInspectorHeading(identifiers: identifiers)
                if let category {
                    Text("\(category.value.title) / \(category.value.rawValue)")
                        .help("Reported category from \(category.provider)")
                }
                if let model = identity?.aircraftLabel {
                    Text(model)
                }
                if let ownerOperator = identity?.ownerOperator?.value {
                    Text(ownerOperator)
                        .accessibilityLabel("Owner / Operator: \(ownerOperator)")
                        .help("Owner or operator reported by the aircraft data source. This may be a registered owner rather than the airline operating this flight.")
                }
                if identity?.modelDescription != nil, let code = identity?.aircraftType?.value {
                    Text("ICAO TYPE \(code)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
                Text("\(contact.observation.address.hasPrefix("~") ? "NON-ICAO" : "ICAO") \(contact.observation.address.uppercased())")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
            }
            .font(.system(size: 13, design: .monospaced)).foregroundStyle(RadarStyle.green)
            .fixedSize(horizontal: false, vertical: true)
            if outsideFilters {
                Text("OUTSIDE FILTERS").font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.amber)
            }
            rule
            InspectorField(title: "ALTITUDE", value: settings.altitude(contact.observation.altitude))
            InspectorField(title: "GROUND SPEED", value: settings.speed(contact.observation.speedKnots))
            InspectorField(title: "DIRECTION", value: contact.observation.directionDegrees.map { String(format: "%03.0f°", $0) } ?? "UNKNOWN")
            InspectorField(title: "DISPLAYED POSITION", value: contact.observation.position.map {
                String(format: "%.5f\n%.5f", $0.latitude, $0.longitude)
            } ?? "UNKNOWN")
            InspectorField(title: "POSITION AGE", value: "\(Int(contact.positionAge)) SEC")
                .help("Position from \(contact.observation.source). Age since the source's last position observation.")
            if contact.stale {
                Text("LAST KNOWN POSITION\nAwaiting a fresh observation.")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.amber)
            }
            rule
            if settings.source != .synthetic {
                FlightRouteInspector(state: route)
                    // A new contact owns a fresh disclosure choice; route updates do not reset it.
                    .id(contact.id)
                rule
            }
            InspectorField(title: "DETAILS UPDATED", value: identity?.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "UNKNOWN")
                .help("The oldest successful update of the known identity fields. Missing fields retain their previous dates.")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rule: some View { Rectangle().fill(RadarStyle.line).frame(height: 1) }
}

private struct ContactInspectorHeading: View {
    let identifiers: AircraftIdentifiers

    private var secondary: String? {
        [identifiers.registration, identifiers.callsign].compactMap { $0 }
            .first { $0.caseInsensitiveCompare(identifiers.primary) != .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(identifiers.primary)
            if let secondary {
                Text(secondary)
            }
        }
        .font(.system(size: 23, weight: .medium, design: .monospaced))
        .foregroundStyle(RadarStyle.bright)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct InspectorField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(RadarStyle.muted)
            Text(value).font(.system(size: 13, design: .monospaced)).foregroundStyle(RadarStyle.green)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
