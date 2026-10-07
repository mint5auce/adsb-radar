# Likely flight-route verification

The inspector design was accepted on 7 October 2026 in the departure/arrival design interview.
The agreed automated seams are route-provider response handling and RadarModel's selected-route state.
The implementation adds selected-contact enrichment independently of aircraft identities and reception.

## Provider and reuse terms

Use [Virtual Radar Server standing data](https://github.com/vradarserver/standing-data), which publishes its route data under [CC0 1.0](https://github.com/vradarserver/standing-data/blob/main/LICENSE).
The [adsb.lol mirror](https://github.com/adsblol/vrs-standing-data) also carries CC0, documents per-callsign JSON access, and refreshes its copy hourly.
The app requests `https://vrs-standing-data.adsb.lol/routes/<first-two-characters>/<callsign>.json` anonymously, without payment, accounts, or receiver sharing.
Only the selected normalized callsign is sent; no position, ICAO address, registration, or Home location is part of this request.
Use a separate one-request-per-second scheduler so route requests cannot consume adsb.fi's position allowance.
The mirror does not publish a fixed request allowance; this pacing is a conservative application policy, not a provider guarantee.
Respect HTTP Retry-After and back off after failures.
Attribute Virtual Radar Server and adsb.lol in the inspector and Settings.

adsbdb was not selected because its [README](https://github.com/mrjackwills/adsbdb#readme) restricts route-data reuse and did not clearly establish permission for our display and session cache.
The adsb.lol batch endpoint returned HTTP 201 with an empty body during this check, so the documented standing-data mirror is used directly.

## Live smoke sample

On 7 October 2026, adsb.fi's southern-UK circle returned HTTP 403 from this environment.
To avoid claiming an unperformed adsb.fi coverage check, obtain the sample from adsb.lol's public live circle centred at 51.5, -0.1 with radius 100 NM instead.
The live response contained 161 aircraft.
Query the first 20 positioned contacts with non-empty callsigns at one request per second against the route mirror.
This is a small provider-order smoke sample, including airline, business/private and placeholder callsigns, rather than an unbiased estimate of coverage.
Fourteen returned HTTP 200 with matching callsign echoes and complete ordered airport records; six returned HTTP 404.
All returned airport-code sequences matched their airport records, with no obvious structural mismatch.
These checks establish access and response usability, not current-flight accuracy, diversion handling, or direction of travel.

| Callsign | Result | Database airports |
| --- | --- | --- |
| AAL141 | Match | EGLL - KJFK |
| EZY9003 | Unknown | - |
| RYR25SX | Match | EGKK - EINN |
| RYR9LY | Match | LFMN - EIDW |
| BAW6NC | Match | EGLL - CYUL |
| LOG22MP | Match | EGPD - EGBB |
| N78KN | Unknown | - |
| SWR9MY | Match | EGBB - LSZH |
| AUR9LG | Match | EGKK - EGJB |
| EZY912P | Match | EGBB - EGPH |
| RYR92LR | Match | EGCC - LFOB |
| RYR5074 | Match | EGBB - EPPO |
| VIR26Q | Match | KJFK - EGLL |
| VJT451 | Unknown | - |
| NJU254W | Unknown | - |
| EAI8C | Match | EIDW - EGHI |
| 00000000 | Unknown | - |
| SHT4G | Match | EGLL - EGAC |
| REV2145 | Unknown | - |
| EIN723 | Match | EGLL - EICK |

The app rejects numeric-only placeholder callsigns before requesting them.
The decoded response has no flight date, effective route date, or diversion indicator.
The inspector always says LIKELY ROUTE and labels its timestamp Looked up.

## Automated and native rendering checks

Provider tests cover ordered intermediate airports, missing IATA codes, callsign association, malformed coordinates, incomplete airport records, HTTP 404, invalid callsigns, and HTTP 429 retry dates.
Model tests cover selected-only requests, callsign and selection changes with delayed responses, thirty-minute expiry, five-minute missing-result caching, failure backoff and recovery, disabled enrichment, relaunch isolation, and Synthetic isolation across all three real source modes.
Tests use deterministic provider/source responses and an injected route clock, without live network dependencies.
The full `swift test` run passed 149 tests across the two test targets (96 RadarCore tests and 53 Phosphor tests).
The candidate application build and code typechecking passed.
Separate Standards and Spec reviews found no actionable implementation issues; the representative candidate live check remains a documented release gate.

Build and render the candidate:

```sh
./scripts/build-app.sh
build/Phosphor.app/Contents/MacOS/Phosphor --render-preview build/route-preview --preview-routes
swift test --filter 'FlightRouteProviderTests|FlightRouteModelTests'
swift test
```

The debug-only route preview uses fixtures, isolated preferences, and fixture identity storage; it does not contact providers or open a desktop window.
Inspect `build/route-preview/inspection.png`, `minimum-window.png`, `matched-route.png`, `cached-route.png`, `loading-route.png`, `unknown-route.png`, and `settings.png`.
Native SwiftUI/AppKit rendering was inspected at 1200 x 800 and 800 x 560, including long airport names, intermediate stops, unknown/loading states, and cache attribution.
Airport names and source notes wrap within the 256-point inspector.
The inspector remains scrollable, with lower route and aircraft details below the fold at minimum size.

## Interactive manual checks

The current environment's adsb.fi HTTP 403 prevented exercising the complete live adsb.fi-to-inspector flow.
Physical receiver reception and interactive scrolling/settings checks were not performed as part of the offscreen rendering verification.

1. Build with `./scripts/build-app.sh`, quit any running copy, and start `open build/Phosphor.app`.
2. Choose Online with a saved Home, or Local/Local + Online with a working receiver, and enable Enrich aircraft details online.
3. Select an airline contact with a callsign and check Looking up… followed by airport fields or Unknown.
4. Scroll the inspector at normal and minimum window sizes, checking long airport names, source links, and lookup time.
5. Deselect and reselect a matched contact within 30 minutes; check Cached for this session.
6. Select a different contact while lookup is pending; check that the first contact's airports never appear under the second.
7. Disable enrichment and save; fresh cached results remain available, new contacts do not trigger lookups, and reception continues.
8. With enrichment enabled, disconnect the network; verify cached results remain until expiry, expired/missing results become Unknown, and Local reception continues.
9. Switch to Synthetic; verify there is no real route section or route activity, then return to a real mode and select a contact again.
10. Quit and relaunch; check that routes are looked up anew while ordinary persisted aircraft identities remain available.

Before release, repeat the live smoke check from the candidate when adsb.fi access is available and investigate any routinely misleading matches.
No release or deployment was performed.
