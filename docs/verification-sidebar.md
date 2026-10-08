# Aircraft sidebar verification

The compact aircraft sidebar design and behaviour were accepted on 8 October 2026.
The agreed layout supersedes the sidebar presentation and route attribution described in earlier verification records.
The accepted behaviour is recorded in [the product specification](product-spec.md#selected-aircraft-sidebar).

## Changes

The CONTACT header now contains the Show on map pin icon and the deselect action.
The map pin distinguishes this action from the top bar's scan-mode scope icon.
The title combines distinct registration and callsign identifiers in the configured preference order, with an uppercase address fallback.
Registration and callsign appear on separate lines without a slash, with long identifiers wrapping without reducing the title font size.
Available category, model, owner/operator, and ICAO type information sits beneath the title, followed by the address.
Missing optional identity lines disappear, and a type-code-only model is not repeated as ICAO TYPE.
The owner/operator retains its source-meaning tooltip and an explicit accessibility label.

Telemetry follows in the order Altitude, Ground speed, Direction, Displayed position, Position age.
Position age provides the active position source in its tooltip.
Stale and outside-filter warnings remain available.
The separate POSITION subtitle and DETAIL section are removed.
Details updated remains at the end, with UNKNOWN when no identity update date exists.

Likely route is a native disclosure with the existing phosphor styling.
Known routes start expanded; unknown and loading routes start collapsed.
Without a manual choice, the disclosure follows lookup availability.
A manual choice persists through route updates for the current contact and resets on a new aircraft selection.
An expanded unavailable route shows UNKNOWN departure and destination.
Intermediate airports remain under VIA, while the multi-leg explanation, provider, lookup time, and cache attribution are removed.
Synthetic does not display or request real routes.

## Automated checks

The baseline identifier, identity-enrichment, and route-model checks passed before implementation.
The focused checks and full `swift test` suite passed after the layout and disclosure changes.
New disclosure tests cover automatic defaults, valid cached matches, expiry to unknown, manual collapse across refreshes, and manual expansion across missing/loading/matched states.
Existing route-model tests continue to cover selection changes, delayed responses, cache expiry, permissions, failures, and Synthetic isolation.
The candidate application build and signature verification passed.
After the visual refinements, all seven focused identifier and disclosure tests, the candidate build, and `git diff --check` passed again.

```sh
swift test --filter 'FlightRouteDisclosureTests|FlightRouteModelTests|AircraftIdentifierTests|AircraftIdentifierModelTests|IdentityEnrichmentTests'
swift test
./scripts/build-app.sh
build/Phosphor.app/Contents/MacOS/Phosphor --render-preview build/sidebar-preview --preview-routes
```

## Native rendering and live interaction

The debug route previews use isolated preferences, fixture identities, and fixture route responses.
Inspect `build/sidebar-preview/inspection.png` and `minimum-window.png` for the actual radar/sidebar layout at 1200 x 800 and 800 x 560.
Inspect `matched-sidebar.png`, `unknown-sidebar.png`, `loading-sidebar.png`, `callsign-sidebar.png`, and `missing-stale-sidebar.png` for full-height native sidebar content.
The previews cover long owner/operator names, title wrapping, reversed identifier preference, intermediate airports, type-code fallback, missing identity/telemetry, stale warnings, and the update-date fallback.
The refined layout was rendered to `build/sidebar-preview-refined` and checked in both identifier orders and at the minimum window size.
It shows separate identifier lines, ICAO type beneath the owner/operator, and intermediate airports without a multi-leg explanation.
The final map-pin icon change passed the candidate build and `git diff --check`.
Native rendering in `build/sidebar-preview-map-pin/minimum-window.png` confirms the sidebar action is visually distinct from the scan-mode scope icon.

The running candidate was also exercised with live Online contacts.
Known routes were expanded by default and could be collapsed manually.
That choice persisted while positions updated and when Show on map centred the selected aircraft.
Unknown routes were collapsed by default and could be expanded to show UNKNOWN departure and destination.
Switching between known and unknown contacts, then returning to each, restored the correct automatic default rather than reusing the earlier manual choice.
Scrolling reached the complete route and Details updated without navigating the map.
Live captures are saved as `build/sidebar-preview/live-expanded.png` and `live-scrolled.png`.

The computer-use tool blocked Ghostty access for launching the interactive fixture with arguments.
Live loading-to-match transitions were therefore verified through deterministic disclosure tests and native state previews rather than the interactive delayed fixture.
Keyboard-only disclosure operation and interactive minimum-window resizing remain manual checks.

## Repeatable manual checks

Build the candidate and start the isolated fixture:

```sh
./scripts/build-app.sh
open -n build/Phosphor.app --args --ui-fixture --preview-routes --map-offline
```

The fixture uses separate preferences under `phosphor-sidebar-ui-verification`, temporary identity storage, and an offline map updater.
It does not contact external aircraft or route services or start a radio decoder.

1. In Contacts, choose VH-LONG8 (QFA31) and inspect the separate identifier lines, long owner/operator name above ICAO type, and expanded multi-stop route without a multi-leg explanation.
2. Collapse LIKELY ROUTE, allow position updates to arrive, and confirm it stays collapsed.
3. Select NOMATCH and confirm UNKNOWN is initially collapsed, optional identity lines are absent, telemetry is UNKNOWN, and stale status remains amber.
4. Expand its route and confirm both airport fields say UNKNOWN.
5. Return to VH-LONG8 and confirm its route starts expanded again.
6. Select G-WPDD (DELAY1) and immediately check LOOKING UP; after six seconds, confirm automatic expansion when the match arrives.
7. Repeat the delayed lookup after restarting the fixture, manually expanding or collapsing during loading, and confirm the choice survives the response.
8. Check that G-WPDD shows EC35 only once and omits the unavailable owner/operator.
9. Use the map pin and deselect icons, checking their help and accessible names.
10. With macOS keyboard navigation enabled, tab to the route disclosure and use Space to expand and collapse it.
11. Resize the window to 800 x 560, scroll to Details updated, and confirm that sidebar scrolling does not pan or zoom the map.
12. In Settings, select Callsign as the aircraft identifier, save, and confirm the heading order reverses while selection stays unchanged.

The separate live app can be started with `open -n build/Phosphor.app` using the existing saved source settings.
