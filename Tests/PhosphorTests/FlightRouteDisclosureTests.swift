import Foundation
import RadarCore
import Testing
@testable import Phosphor

struct FlightRouteDisclosureTests {
    @Test func automaticDisclosureTracksLookupAvailabilityIncludingCachedMatches() {
        let disclosure = FlightRouteDisclosure()
        #expect(!disclosure.isExpanded(for: .unknown))
        #expect(!disclosure.isExpanded(for: .lookingUp))
        #expect(disclosure.isExpanded(for: matched()))
        #expect(disclosure.isExpanded(for: matched(cached: true)))
        // An expired match becomes unknown, so an untouched disclosure closes again.
        #expect(!disclosure.isExpanded(for: .unknown))
    }

    @Test func manualCollapseSurvivesRefreshAndCacheUpdates() {
        var disclosure = FlightRouteDisclosure()
        disclosure.setExpanded(false)
        for state in [matched(), .unknown, .lookingUp, matched(cached: true)] {
            #expect(!disclosure.isExpanded(for: state))
        }
    }

    @Test func manualExpansionSurvivesMissingAndLoadingResults() {
        var disclosure = FlightRouteDisclosure()
        disclosure.setExpanded(true)
        for state in [FlightRouteLookupState.unknown, .lookingUp, matched(), .unknown] {
            #expect(disclosure.isExpanded(for: state))
        }
        disclosure.setExpanded(false)
        #expect(!disclosure.isExpanded(for: matched()))
    }

    private func matched(cached: Bool = false) -> FlightRouteLookupState {
        let route = FlightRoute(callsign: "TEST123", airports: [
            FlightRouteAirport(name: "Departure", icao: "EGLL", coordinate: SyntheticSource.exampleLocation),
            FlightRouteAirport(name: "Destination", icao: "EGGD", coordinate: SyntheticSource.exampleLocation)
        ], provider: "Fixture", sourceURL: URL(string: "https://example.test/routes")!)
        return .matched(FlightRouteMatch(route: route, lookedUpAt: Date(timeIntervalSince1970: 0), cached: cached))
    }
}
