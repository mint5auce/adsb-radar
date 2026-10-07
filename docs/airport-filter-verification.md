# Airport filters: design and verification

Airport filters control map markers independently of aircraft filters, reception, and the flight-level slice.
The accepted design places independent Large, Medium, and Small checkboxes beneath Airports in the Map popover.
Large and Medium start enabled; Small starts disabled, including for existing installations without saved airport filters.
Enabling Small permits its markers at every zoom level.
Airport labels retain their existing overlap suppression, with the selected visible airport always labelled.

Scheduled service offers All, With scheduled service, and Without scheduled service, defaulting to All.
Include unknown starts enabled and controls airports with missing service information when a service criterion is active.
An airport must match an enabled size and the service criterion.
Disabling all sizes hides all airport markers.
Changes apply immediately and persist between launches, while preserving all existing presentation choices and the Airports layer switch.
Hiding a selected airport clears its selection and inspector without changing the camera or aircraft.

## Source compatibility

Use the source's airport size and scheduled-service fields without inferring an airport's military, cargo, business aviation, or general aviation purpose.
Older airport snapshots retain their source-backed size from the existing Type detail; unavailable scheduled-service information remains unknown.
The original OurAirports CSV retrieved on 6 October 2026 has SHA256 `fad6af8c5e7f86a15559af2394b20bb0cb1e3759cd7dc831c1ae287859ae6947`.
Regenerate the bundled resource with MapDataTool instead of editing generated JSON.
The regenerated resource preserves all 1,061 original records, geometry, codes, and snapshot metadata, adding only typed size and scheduled-service fields.
It contains 18 large, 74 medium, and 969 small airports, with 57 reporting scheduled service and 1,004 reporting no scheduled service.

## Build and exercise

Build and launch the isolated native fixture:

```sh
./scripts/build-app.sh
build/Phosphor.app/Contents/MacOS/Phosphor --ui-fixture --map-offline
```

The fixture uses separate preferences under `phosphor-ui-verification` and map data under `/tmp/phosphor-ui-map-data`.
It does not change ordinary saved preferences or require receiver hardware.

1. Open Map and enable Airports, leaving Routes and Airspace disabled for a clear airport view.
2. Confirm Large and Medium are enabled and Small is disabled when no airport filters were previously saved.
3. Toggle each size independently and confirm disabling every size hides all airport markers.
4. Enable Small at a viewing radius above 35 NM, then pan and zoom out further; small-airport markers must remain eligible while labels stay sparse.
5. Choose With scheduled service and Without scheduled service, inspect known airports, and confirm service and size choices combine.
6. With an older cached airport snapshot, use Include unknown to show or hide airports with missing service information under an active service criterion; All includes every service status.
7. Select an airport, then exclude its size or service status; its inspector must close while map framing and aircraft stay unchanged.
8. Disable and re-enable Airports, then quit and relaunch; the chosen sizes, service criterion, and Include unknown must persist.
9. Inspect the Map popover at the normal 1200 × 800 and minimum 800 × 560 window sizes, including an open airport inspector.
10. Change the airspace flight-level slice and aircraft filters; eligible airport markers must remain unaffected.

Generate deterministic native layout evidence without launching a desktop window:

```sh
swift build
"$(swift build --show-bin-path)/Phosphor" --render-preview /tmp/phosphor-airport-filter-preview --preview-airports
```

This produces normal and minimum map views plus Map controls for the default filters, all sizes, scheduled service only, and no sizes selected.

## Verification record: 7 October 2026

The full Swift suite passed 130 tests: 89 RadarCore tests and 41 app tests.
All 13 release-script tests, shell syntax checks, the packaged debug build, and its ad hoc signature verification passed.
Focused checks cover source-field ingestion and offline snapshot encoding; default, independent, and empty size choices; service combinations and missing values; compatibility with older preferences and airport snapshots; selection clearing and hit targets; camera stability; preserved aircraft contacts; and persisted filters.
The staged airport-filter changes also built successfully from an isolated snapshot without unrelated checkout edits.
All 15 affected importer, preference, visibility, and map-model checks passed against that isolated snapshot.
Standards and spec reviews reported no findings.
Native rendered Map controls and radar views were inspected at normal and minimum window sizes, including the dense all-sizes display at a 100 NM viewing radius.
The live fixture launched successfully, but automated interactive acceptance could not target it reliably while another Phosphor instance was running.
The user subsequently reported that manual acceptance passed on 7 October 2026.
