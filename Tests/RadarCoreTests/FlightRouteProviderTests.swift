import Foundation
import Testing
import RadarCore

struct FlightRouteProviderTests {
    @Test func unrelatedMalformedAndIncompleteRoutesAreRejected() throws {
        #expect(throws: (any Error).self) { try VirtualRadarRouteProvider.decode(Data(routeJSON.utf8), callsign: "BAW123") }
        for malformed in [
            routeJSON.replacingOccurrences(of: "YSSY-WSSS-EGLL", with: "YSSY-EGLL-WSSS"),
            routeJSON.replacingOccurrences(of: "151.177", with: "181"),
            routeJSON.replacingOccurrences(of: "Sydney Airport", with: " "),
            "{}", "[]", ""
        ] {
            #expect(throws: (any Error).self) { try VirtualRadarRouteProvider.decode(Data(malformed.utf8), callsign: "QFA31") }
        }
    }

    @Test func missingRouteAndInvalidCallsignDoNotProduceMatches() async throws {
        let missing = RouteHTTPTransport(response: OnlineHTTPResponse(data: Data(), status: 404))
        let provider = VirtualRadarRouteProvider(scheduler: OnlineRequestScheduler(transport: missing))
        #expect(try await provider.route(for: " QFA31 ") == nil)
        for invalid in ["", "00000000", "a/b", "../BAW123", "TOOLONG123"] {
            #expect(try await provider.route(for: invalid) == nil)
        }
        #expect(await missing.urls.map(\.absoluteString) == ["https://vrs-standing-data.adsb.lol/routes/QF/QFA31.json"])
    }

    @Test func rateLimitResponseRetainsTheProviderRetryDate() async throws {
        let date = Date.now.addingTimeInterval(120)
        let transport = RouteHTTPTransport(response: OnlineHTTPResponse(data: Data(), status: 429, retryAfter: date))
        let provider = VirtualRadarRouteProvider(scheduler: OnlineRequestScheduler(transport: transport))
        do {
            _ = try await provider.route(for: "QFA31")
            Issue.record("Rate limiting should be retried, not cached as a missing route")
        } catch FlightRouteProviderError.http(let status, let retryAfter) {
            #expect(status == 429 && retryAfter == date)
        }
    }
    @Test func matchingRoutePreservesOrderedAirportsAndMissingIATA() throws {
        let route = try #require(try VirtualRadarRouteProvider.decode(Data(routeJSON.utf8), callsign: "QFA31"))
        #expect(route.callsign == "QFA31")
        #expect(route.airports.map(\.icao) == ["YSSY", "WSSS", "EGLL"])
        #expect(route.airports[1].displayName == "Singapore Changi Airport (WSSS)")
        #expect(route.airports[0].displayName == "Sydney Airport (SYD / YSSY)")
        #expect(route.provider == "Virtual Radar Server / adsb.lol")
    }
}

private actor RouteHTTPTransport: OnlineHTTPTransport {
    let response: OnlineHTTPResponse
    var urls: [URL] = []
    init(response: OnlineHTTPResponse) { self.response = response }
    func get(_ url: URL) async throws -> OnlineHTTPResponse {
        urls.append(url)
        return response
    }
}

private let routeJSON = """
{"callsign":"QFA31","airport_codes":"YSSY-WSSS-EGLL","_airports":[
 {"name":"Sydney Airport","icao":"YSSY","iata":"SYD","lat":-33.9461,"lon":151.177},
 {"name":"Singapore Changi Airport","icao":"WSSS","iata":null,"lat":1.35019,"lon":103.994},
 {"name":"London Heathrow Airport","icao":"EGLL","iata":"LHR","lat":51.4706,"lon":-0.461941}
]}
"""
