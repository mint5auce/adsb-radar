# Online source verification

## Issue #15: Online mode

The existing 18 core tests passed before implementation.
The completed slice passes 24 tests across the core and application model, including deterministic online payloads, millisecond timestamps, missing optional values, request spacing and priority, queued cancellation, increasing retry delays, older preferences, obsolete responses, and contact ageing during a suspended poll.
The app source loop is independent of the display loop.
Native debug packaging and release compilation passed.

On 6 October 2026, the documented adsb.fi geographic endpoint returned HTTP 200 and 14 aircraft within 25 NM of the bundled example location.
The native app then displayed hundreds of real contacts at the default 250 NM search radius, with a selected contact reporting adsb.fi and a genuine position age.
Offscreen native previews were inspected for Immediate, Sweep, contact inspection, settings, and an unavailable-provider state at the minimum window size.
Preview preferences are isolated from saved user preferences.
Dense live traffic retains the existing label-overlap limitation; zooming reduces the clutter.
A new physical-receiver disconnection exercise was not performed for this slice.
Owned receiver process stop/restart is covered by the existing child-process fixture.

Build and start after quitting any running copy:

```sh
./scripts/build-app.sh
open 'build/ADSB Radar.app'
```

1. Open Settings, choose Online / adsb.fi, enter latitude 51.5 and longitude -2.5 for the example Home location, and save.
2. Confirm Online health becomes active and aircraft appear without a dongle.
3. Select a contact and inspect its source, position age, trail, and explicit unknown fields.
4. Switch between Immediate and Sweep, pan away from home, and use Return home.
5. Set a different refresh interval and search limit; relaunch and verify they persist.
6. Temporarily disconnect networking and confirm the failure status appears, the map remains responsive, and existing contacts become stale and disappear at the configured thresholds.
7. Restore networking and confirm automatic recovery; switch to Synthetic and confirm the real contacts and selection clear.
8. Switch back to Local and confirm the usual receiver status; quit and confirm the owned decoder stops.

Repeatable offscreen Online fixtures, requiring no internet or hardware:

```sh
swift build
"$(swift build --show-bin-path)/ADSB Radar" --render-online-preview /tmp/adsb-radar-online-preview
```

These renders exercise native views with fixtures and do not constitute an interactive network-outage or physical-receiver test.

## Issue #16: visible-map searches

The completed slice passes 28 tests.
Additional deterministic checks cover inverse projection and date-line wrapping, extreme pans, viewport coverage, configured limits, boundary geometry, contact retention outside the search, settled-pan coalescing, changing limits without clearing selection, and Return home.
The native normal and minimum-window previews show the dashed boundary and a 60 NM limit displayed as 111 KM, confirming that the notice uses the chosen limit and distance units.
Search changes cancel pending requests and reject obsolete results without resetting the contact session.
The live native candidate was also exercised through repeated zooms and a pan; the 250 NM boundary and notice appeared while Online reception remained active.

Using the build and launch commands above:

1. Choose Online, select a contact, and drag the map repeatedly; confirm the search follows the final view while the home origin remains fixed.
2. Zoom out until the view exceeds the configured limit and confirm the dashed amber boundary and limit notice appear.
3. Change the search limit to 60 NM and distance units to kilometres; confirm the notice reports 111 KM and pan/zoom remain unrestricted.
4. Pan away from the selected aircraft and verify its inspector and trail remain until the usual removal age, without a separate tracking query.
5. Use Return home and verify that the map and search return to the saved origin.
6. Repeat at the minimum 800 by 560 window size and restore preferred settings afterwards.

## Issue #17: combined reception

The completed slice passes 34 tests.
New deterministic checks cover local preference, fallback and recovery, actual source timestamps, missing-position provenance, non-ICAO identity collisions, chronological trails, removal, sweep source handover, source disabling, preserved selection, shared-source lifecycle, and automatic local retries while Online continues.
Test preferences are isolated from the user's saved settings.

Build and launch using the commands above, then:

1. Choose Local + Online and confirm separate Local and Online health rows.
2. With reception available, select an aircraft supplied by both sources and confirm one contact using the local position.
3. Interrupt local reception, wait for its position to become stale, and confirm adsb.fi takes over with its original observation age.
4. Restore reception and confirm local precedence resumes while selection and trails remain.
5. Switch to Online, then Local + Online, then Local; confirm shared sources continue, contacts supported only by disabled sources disappear, and the owned decoder runs only in modes using Local.
6. Interrupt networking while local reception continues and check that local movement remains responsive.
7. Enter and leave Synthetic and confirm the previous picture and selection clear; quit and check owned decoder cleanup.

Repeatable native views for local preference, fallback, and recovery:

```sh
swift build
"$(swift build --show-bin-path)/ADSB Radar" --render-combined-preview /tmp/adsb-radar-combined-preview
```

The fixture simulates local failure and recovery through the normal model and source loops.
The normal and minimum-window views were inspected for separate health, retained selection, local attribution, online fallback, and local recovery.
The live native candidate exposes all four source choices; selecting Local + Online kept Online active while the unavailable receiver was retried automatically.
The live Local health row displayed the missing-dongle message and Retry control while Online remained active with hundreds of contacts.
Debug packaging, release compilation, and the final full test suite passed.
A physical receiver failure/recovery exercise remains to be confirmed.

## Issue #18: optional identity enrichment

The completed slice passes 46 tests.
New checks cover optional and missing identity fields, batched ICAO lookups, selection priority, deduplication, pending cancellation, increasing retries, preserved provenance, shared pacing and Retry-After, and position updates continuing during a slow identity response.
Application checks cover Local enrichment, dedicated-request disabling without restarting reception, metadata reuse from Online snapshots with lookups disabled, Synthetic isolation, and offline failure without changing movement or introducing contacts.
Debug packaging and release compilation passed.
The live batched ICAO endpoint returned HTTP 200 with G-JZHX/B738 and G-VBOW/B789 on 6 October 2026.
The live native inspector showed BAW19N / G-VIIG / B772 with adsb.fi as the position source and a genuine position age.
Native Local fixture views were inspected at normal and minimum window sizes with enrichment enabled and disabled.
The inspector retains Local as the position source and shows G-TEST/A320; the settings toggle defaults to enabled and remains available in Local mode.
Fixture failure tests confirm Local reception continues with unknown details.
Physical Local reception and its real-aircraft enrichment could not be checked without a dongle.

Build and launch using the commands above, then:

1. Choose Local with a connected receiver and enable Enrich aircraft details online.
2. Select a visible aircraft with a reliable ICAO address; confirm registration and aircraft type appear when adsb.fi has them, while position source and age continue to reflect Local reception.
3. Disable enrichment and confirm reception continues, known details remain, and newly encountered aircraft can show unknown details.
4. Re-enable enrichment, disconnect networking, and confirm the radar remains responsive and known values remain; restore networking and check later lookups recover.
5. Choose Online with enrichment disabled and confirm ordinary position responses can still supply identity fields.
6. Switch to Synthetic and confirm real identities disappear and no online identity work runs.

Repeatable native Local enrichment views:

```sh
swift build
"$(swift build --show-bin-path)/ADSB Radar" --render-local-enrichment-preview /tmp/adsb-radar-local-enrichment-preview
```

## Issue #19: persistent identities

The completed implementation passes 56 tests across the core and application model.
Additional checks cover atomic file round trips, per-field provenance and timestamps, reliable identity filtering, missing/corrupt/unsupported/unwritable storage, preference migration, configurable refresh age, encountered-only refreshes, partial updates, failed-refresh backoff with complete expired entries, and late cache loads preserving newer responses.
Application checks exercise an actual file-cache restart with dedicated lookups disabled, offline retention, refresh-age changes without position changes, no queries for unseen cached aircraft, and continued operation after storage failures.
The default refresh age is seven days, with fractional days supported from one hour through 3650 days.
Identity data is saved under `~/Library/Application Support/dev.mint5auce.adsb-radar/aircraft-identities.json`.
The versioned file contains registration/type values, their providers, and successful field-update dates; movement is excluded.
Saving is atomic, occurs independently of the display, and flushes on clean shutdown.
The inspector's Details updated date conservatively represents the oldest successful update among known fields, so a missing field cannot acquire a false new verification date.

Native fixture views were inspected across three model lifecycles using the same isolated file cache.
They show G-CACHED/A319 dated 28 September after restart with failed online refreshes and after disabling enrichment, then G-REFRESH/B738 dated 6 October after successful refresh.
The minimum-window inspector remains scrollable and the seven-day refresh setting is visible in Local mode.
Preview preferences and cache files are isolated from normal user storage.

Local hardware reception became available during the final release check.
The live native Local inspector showed RYR85TC / EI-IGI / B38M with adsb.fi identity provenance, LOCAL RTL-SDR position source, and a one-second position age.
Disabling enrichment retained those details while reception continued.
After a normal quit and relaunch in Local with enrichment disabled, the live inspector retained EI-IGI/B38M and its 14:40 update date while displaying newly received Local positions.
The normal cache stored 644 identity entries from the live Online and Local session.
Quitting stopped the owned readsb process.
Release packaging and strict signature verification passed.
Physical dongle disconnection/reconnection and a live operating-system network outage remain unverified; deterministic source/provider failures cover those transitions.

Build and launch using the commands above, then:

1. In Local mode, enable enrichment and select an aircraft whose registration and type become known; note its Details updated date.
2. Quit, disable networking, relaunch in Local, and select that aircraft when locally received again; confirm cached details and their original update date remain while position age reflects new Local reception.
3. Disable enrichment, quit, relaunch, and confirm cached details remain usable and the setting persists.
4. Restore networking and enable enrichment; reduce Refresh aircraft details after (days) to an age below the cached entry's age and confirm a successful encountered-aircraft refresh updates only returned fields and their dates.
5. If a refresh returns incomplete information or fails, confirm previous values and dates remain and Local reception continues.
6. Restore the preferred refresh age and switch to Synthetic; confirm no real identity details appear.

Repeat the native restart/offline/refresh sequence without internet or hardware:

```sh
swift build
"$(swift build --show-bin-path)/ADSB Radar" --render-cache-preview /tmp/adsb-radar-cache-preview
```

This uses actual identity-file saves and loads across model lifecycles with deterministic source/provider fixtures.
It does not disable the computer's network or physically disconnect a receiver.
