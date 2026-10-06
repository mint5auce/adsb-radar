# Aircraft view decluttering verification

Build the candidate with `./scripts/build-app.sh`.
Start it with `open 'build/ADSB Radar.app' --args --synthetic --scenario demo --demo-count 250`.
These launch arguments use generated traffic without replacing the saved source preference.

## Labels, trails, and direction vectors (#20)

1. Inspect the 250-aircraft overview at normal size and at the 800 by 560 minimum window size.
2. Open View and compare Automatic, All, and Selected only labels.
3. Select an aircraft and check that its callsign and altitude remain readable in every label mode.
4. Zoom in and verify that additional automatic labels appear without shrinking text.
5. Compare All, Selected, and None trails, and toggle direction vectors.
6. Wait for movement, restore All trails, and confirm history was retained while hidden.
7. Repeat with Immediate and Sweep updates, then relaunch to confirm saved presentation choices.

The original problem was reproduced in the native app with 250 Demo aircraft before implementation.

## Home distance (#21)

1. Save a Home location in Settings, then open Filters and choose 25, 50, and 100 NM or enter a positive custom distance and press Return.
2. Pan away from Home and confirm the eligibility criteria stay anchored to Home while In view and Outside view change.
3. Select an aircraft, tighten the distance until it falls outside the criterion, and check the Outside filters note and counts.
4. Deselect it and confirm its marker and hit target disappear.
5. Enter zero, a negative value, or invalid text and confirm the inline explanation leaves the last valid filter active.
6. Wait while contacts are hidden, clear filters, and confirm their updated positions and retained trails reappear.
7. Change distance units and relaunch to verify the criterion retains its physical distance.
8. With Home unset, confirm distance controls explain their unavailability.

Home-distance model checks passed with retained contacts, selected exceptions, offscreen counts, and clearing without observation changes.

## Reported altitude and ground (#22)

1. Enter a minimum and/or maximum reported altitude and press Return or leave the field to commit it.
2. Verify that aircraft exactly at either limit remain eligible, Ground is excluded by numeric ranges, and Include unknown altitude controls missing altitude independently.
3. Enter a minimum above the maximum and confirm the inline error leaves the last valid range active.
4. Clear the range and toggle Hide ground aircraft, confirming zero numeric altitude does not imply Ground.
5. Change altitude units and relaunch, checking that physical limits remain unchanged.
6. Combine Home distance and altitude criteria and confirm both must match, with the explicit selected-aircraft exception retained.

Deterministic altitude checks passed for exact bounds, missing altitude, explicit Ground, numeric zero, and invalid range retention.

## Reported categories (#23)

1. Select Local or Combined traffic and inspect Reported category, Category from, and Category updated.
2. Confirm a current Local category takes priority even when an old Local position has fallen back to Online.
3. Disable Enrich aircraft details online and confirm categories from ordinary reception still appear.
4. Relaunch with enrichment disabled or the provider unavailable and verify known cached categories and their dates remain available.
5. Enter Synthetic and confirm generated categories appear with Synthetic provenance and no real cached identities.
6. Confirm missing category reports do not turn a known category into Unknown or advance its successful update date.

Category parsing, known-value retention, file restart, and independent Local precedence have deterministic checks.
The existing cache format accepts older entries with no category and refreshes encountered incomplete details under the existing configurable refresh/backoff policy.

## Category filters (#24)

1. Scroll the Filters panel to Reported category and choose Larger aircraft.
2. Verify Small, Large, and Heavy are selected; Light, High-performance, Helicopters, and Other are not.
3. Toggle individual categories and Include unknown category, combining them with distance and altitude criteria.
4. Inspect a high-vortex large contact and verify it belongs to Large while its inspector retains A4.
5. With enrichment enabled, hide unknown categories and verify an encountered unknown contact can appear when matching details arrive without changing its received position or source.
6. Relaunch and clear filters, confirming persisted criteria and independent presentation preferences.

Category checks cover A2-A5, high-performance and helicopter exclusion, unknown handling, AND composition, selection exceptions, and enrichment of hidden contacts.

## Contacts search and overlap selection (#25)

1. Open Contacts and search a callsign, ICAO address, known registration, and known model code such as A320.
2. Verify only list results change; map filters and In view, Outside view, and Filtered counts stay unchanged.
3. Use Clear search and Clear filters separately, confirming neither clears the other control's state.
4. Pan away, select an offscreen contact in Contacts, and confirm the map does not move until Show on map is clicked in the inspector.
5. Click a dense group of nearby markers and choose a contact by callsign/address, altitude, and known model.
6. Tighten a filter and verify hidden aircraft no longer appear as clickable markers or overlap candidates, while the selected exception remains eligible.
7. Compare the Contacts panel and chooser at normal and minimum window sizes in both display modes.

Model checks cover all search fields, independent map counts, filtered hit candidates, explicit centring, and Home preservation.

## Presets and full native verification (#26)

1. Open Filters and compare Overview, Near Home, Larger near Home, and Higher traffic.
2. Confirm Near Home uses 50 NM and hides Ground; Larger near Home additionally selects A2-A5.
3. Confirm Higher traffic uses a minimum reported altitude of 10,000 FT and hides Ground.
4. Edit each preset, change distance/altitude units, and relaunch to confirm the resulting physical criteria persist.
5. Keep an aircraft selected while applying a preset that excludes it; check Outside filters without automatic panning.
6. Pan offscreen and use Show on map, confirming Home and the active criteria remain unchanged.

For isolated interactive native checks, build debug and start with `open 'build/ADSB Radar.app' --args --ui-fixture`.
This debug-only fixture uses a separate preference domain and cache, with 250 positioned generated contacts plus one heard without a position.
It includes airport-like density, coincident markers, Ground, unknown categories and altitudes, and stale contacts.
Fixture preferences persist across relaunches independently of ordinary app preferences.
To render repeatable native verification images without opening a window, run `'.build/out/Products/Debug/ADSB Radar' --render-preview /tmp/adsb-declutter-verification --preview-declutter` after building debug.
For a separate 250-aircraft Demo rendering, use `'.build/out/Products/Debug/ADSB Radar' --synthetic --scenario demo --demo-count 250 --render-preview /tmp/adsb-declutter-demo --preview-filters`.
