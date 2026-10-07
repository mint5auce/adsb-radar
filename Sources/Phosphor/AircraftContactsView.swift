import RadarCore
import SwiftUI

struct AircraftContactsView: View {
    @Bindable var model: RadarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTACTS").font(.system(size: 13, weight: .semibold, design: .monospaced))
            HStack {
                TextField("Callsign, ICAO, registration, model, or owner", text: $model.contactsSearch)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Search Contacts")
                Button("Clear search") { model.contactsSearch = "" }.disabled(model.contactsSearch.isEmpty)
            }
            Text("\(model.receivedPositionedCount) received positioned · \(model.heardWithoutPosition) heard without positions")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    if model.listedContacts.isEmpty { Text("No matching contacts").foregroundStyle(RadarStyle.muted).padding(.vertical, 20) }
                    ForEach(model.listedContacts) { contact in
                        Button { model.selectedAddress = contact.id } label: {
                            AircraftContactRow(contact: contact, identity: model.identity(for: contact), settings: model.settings,
                                outsideView: !model.isInView(contact), outsideFilters: !model.matchesFilters(contact))
                                .padding(8).background(contact.id == model.selectedAddress ? RadarStyle.green.opacity(0.1) : .clear)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20).frame(width: 440, height: 460)
        .background(RadarStyle.panel).foregroundStyle(RadarStyle.green).tint(RadarStyle.green)
    }
}

struct AircraftOverlapChooser: View {
    @Bindable var model: RadarModel
    let contactIDs: [String]
    let choose: (String) -> Void

    private var candidates: [PresentedContact] { model.eligibleContacts.filter { contactIDs.contains($0.id) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHOOSE AIRCRAFT").font(.system(size: 12, weight: .semibold, design: .monospaced))
            ScrollView {
                VStack(spacing: 4) {
                    if candidates.isEmpty { Text("No matching contacts") }
                    ForEach(candidates) { contact in
                        Button { choose(contact.id) } label: {
                            AircraftContactRow(contact: contact, identity: model.identity(for: contact), settings: model.settings)
                                .padding(8)
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: min(260, CGFloat(max(1, candidates.count)) * 60))
        }
        .padding(16).frame(width: 340)
        .background(RadarStyle.panel).foregroundStyle(RadarStyle.green).tint(RadarStyle.green)
    }
}

private struct AircraftContactRow: View {
    let contact: PresentedContact
    let identity: AircraftIdentity?
    let settings: RadarSettings
    var outsideView = false
    var outsideFilters = false

    private var identifiers: AircraftIdentifiers {
        AircraftIdentifiers(observation: contact.observation, identity: identity, preferred: settings.aircraftIdentifier)
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(identifiers.primary)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Text(identifiers.secondary.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                if let aircraft = identity?.aircraftLabel {
                    Text(aircraft).font(.system(size: 11, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
                if let owner = identity?.ownerOperator?.value {
                    Text("Owner / Operator: \(owner)")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.muted)
                }
                if outsideFilters || outsideView {
                    Text([outsideFilters ? "Outside filters" : nil, outsideView ? "Outside view" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(RadarStyle.amber)
                }
            }
            Spacer(minLength: 8)
            Text(settings.altitude(contact.observation.altitude)).font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(contact.stale ? RadarStyle.amber.opacity(0.7) : RadarStyle.green)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
