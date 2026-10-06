# Airway layers: data and verification

Implemented scope: [ATS routes #10](https://github.com/mint5auce/adsb-radar/issues/10), [controlled airspace #11](https://github.com/mint5auce/adsb-radar/issues/11), [airports #12](https://github.com/mint5auce/adsb-radar/issues/12), [flight levels #13](https://github.com/mint5auce/adsb-radar/issues/13), and [updates #14](https://github.com/mint5auce/adsb-radar/issues/14).

## Bundled sources

| Provider | Date | Included features | Coverage |
| --- | --- | --- | --- |
| NATS UK AIP | Effective 2026-10-01 | 1,217 ATS route segments; 446 CTA/CTR/TMA regions | NATS-published UK and Crown Dependency extent |
| OurAirports | Retrieved 2026-10-06 | 1,061 large, medium and small airports | GB, GG, JE, IM |

Sources: [NATS catalogue](https://nats-uk.ead-it.com/cms-nats/opencms/en/Publications/digital-datasets/), [NATS source package](https://nats-uk.ead-it.com/cms-nats/export/sites/default/en/Publications/digital-datasets/ICAO_AIP/EG_AIP_DS_20261001_XML.zip), and [OurAirports CSV](https://davidmegginson.github.io/ourairports-data/airports.csv).
NATS permits aviation use, with unrestricted access/usage and no resale; its data is not public domain.
OurAirports data is public domain.
The source and terms remain available in the app's Map data popover and normalized snapshots.

SHA256 fingerprints of the retrieved inputs:

```text
NATS ZIP     53f72afcba1f3e9d34e9942c0f10e0dbfffed74cf8e9fa3f762cf5bf1e543914
Airports CSV fad6af8c5e7f86a15559af2394b20bb0cb1e3759cd7dc831c1ae287859ae6947
```

The NATS FULL XML was checked against the checksum supplied inside its ZIP.
Both normalized resources were reproduced byte-for-byte through the live download/import path on 6 October 2026.
OurAirports changes nightly, so reproducing this exact snapshot later requires the original CSV matching the fingerprint above.

## Import and refresh

Generate normalized resources from saved source files:

```sh
swift run MapDataTool nats /path/to/EG_AIP_DS_FULL_20261001.xml 2026-10-01 /tmp/NATSMap.json
swift run MapDataTool airports /path/to/airports.csv 2026-10-06 /tmp/AirportsMap.json
```

Download and validate the currently effective datasets into a staging directory:

```sh
swift run MapDataTool refresh /tmp/adsb-map-download
```

Review those files before replacing the corresponding resources in `Sources/ADSBRadar/Resources`.
Do not manually edit the generated JSON.
The app's Check for map updates uses the same importers and validates NATS checksums before activation.
Each provider is stored atomically under `~/Library/Application Support/ADSB Radar/MapData`.
NATS routes and regions share a single generation.
Startup uses the newer valid cached or bundled snapshot, falling back to the bundle for a corrupt, older or future-dated cache.
No map requests run automatically.

The importer supports all geometry used by the included 2026-10-01 regions: BASE components, polygon exterior/interior rings, curve references, geodesic strings, linear segments, centre-point arcs and circles in EPSG:4326.
Curves use the published signed sweep and radius; geodesics are sampled at most every two nautical miles and arcs every degree before projection.
Short joins tolerate the source's rounded endpoint coordinates.
Unsupported composition or geometry rejects the whole incoming NATS generation and leaves the existing one installed.
This does not claim general support for every future AIXM construct.
Published routes with unknown widths remain centrelines, and operational activation is not inferred.

Small airports appear at a radius of 35 NM or less.
Flight levels accept whole values from 0 to 660, with ten-level steps and inclusive bounds.
Only compatible standard-pressure FL, FT or M limits are compared; incomparable or missing limits remain uncertain and dimmed.
Airport markers and aircraft contacts are unaffected by the slice.

## Build and exercise

Quit an existing candidate first, then launch the isolated dense synthetic fixture:

```sh
./scripts/build-app.sh
'build/ADSB Radar.app/Contents/MacOS/ADSB Radar' --ui-fixture
```

The fixture uses separate preferences and `/tmp/adsb-radar-ui-map-data` for downloaded map snapshots.
It retains previous fixture settings, including aircraft filters.
For ordinary moving synthetic traffic, launch with `--synthetic --scenario demo` instead.

1. Switch Routes, Airspace and Airports independently and confirm the remaining layers and aircraft stay visible.
2. Click a route or airspace boundary away from aircraft, choose an item if needed, and inspect its own limits and source date.
3. Click an airport and inspect codes and elevation, including unavailable fields shown as Unknown.
4. Disable the selected feature's layer and confirm its inspector closes.
5. Click a cluster of aircraft over airspace: primary click offers aircraft only; secondary click includes the map features underneath.
6. Choose a map feature, then select an aircraft and confirm there is only one inspector.
7. Pan, zoom and return home; zoom below 35 NM to reveal small airports and waypoint detail.
8. Choose All levels, a preset, custom FL 145 and the step buttons; invalid text must leave the last valid slice unchanged.
9. Select a standard-pressure route and slice outside its limits to clear it; inspect a region with MSL/SFC limits for the small Uncertain slice-status note.
10. Open Map data, run Check for map updates, and confirm the camera, layer switches and selected visible object survive.
11. Repeat at 1200 × 800 and the minimum 800 × 560 window sizes, including an open inspector and scrolling overlap chooser.
12. Change Home in Settings and confirm map geometry stays aligned with the geography and aircraft.

For a deterministic failed-update/offline restart, quit the fixture and relaunch it with map networking disabled:

```sh
'build/ADSB Radar.app/Contents/MacOS/ADSB Radar' --ui-fixture --map-offline
```

Confirm the saved slice and switches return, the map renders from bundled/cached data, and Check for map updates reports that existing data was kept.
This simulates the map provider outage without changing the computer's network settings.

Generate native rendered evidence for the normal and minimum layouts, each inspector, FL 100, and near-scale detail:

```sh
swift run 'ADSB Radar' --render-preview /tmp/adsb-map-preview --preview-airspace
```

## Verification record: 6 October 2026

The full `swift test` run passed: 69 RadarCore tests and 31 app tests, with no failures.
Focused checks cover real route reference resolution and unknown widths; polygon/arc/circle imports and signed arc direction; unsupported geometry; CSV exclusions and missing codes; inclusive altitude bounds and uncertainty; preference compatibility; projection hit testing; selection priority and clearing; checksum/reference/parse failures; atomic storage and restart; and failed refresh retention.
Native interaction verified preset/custom/invalid flight levels, stepping, airport overlap selection, layer-driven deselection, primary aircraft priority, secondary mixed-object choices, return to the aircraft inspector, pan/zoom, successful updates, and offline restart with retained preferences and failed-update feedback.
The live NATS download, checksum verification and full import also succeeded through MapDataTool.
Native rendered layouts were inspected at 1200 × 800 and 800 × 560 with synthetic traffic.
The initial secondary-click failure was reproduced in the native app and repaired with an AppKit event observer scoped to the map.
No physical receiver or real-flight operational validation was performed for this presentation feature.
