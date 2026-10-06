# Startup presentation and control visibility verification

The accepted design is in [the product specification](product-spec.md#startup-presentation-and-control-visibility).
Map options use a MAP popover beside Sweep, Filters, View, and Contacts.

## Build and launch

Build the debug candidate with `./scripts/build-app.sh`.
Launch an isolated native fixture with `open 'build/ADSB Radar.app' --args --ui-fixture --map-offline`.
Quit any existing ADSB Radar process first so the launch arguments reach the new process.
The fixture uses its own saved preferences and synthetic contacts, independently of the normal app's preferences and real data sources.

For normal generated traffic, use `open 'build/ADSB Radar.app' --args --synthetic --scenario demo --demo-count 250`.
That command retains the normal app's saved presentation preferences and only overrides the aircraft source for the launch.
Fresh defaults are verified through isolated preference tests without deleting the user's settings.
Run `swift test --filter PreferencesTests` for fresh, legacy, and saved settings, and `swift test --filter ControlVisibilityTests` for deterministic timing and interaction checks.

## Native exercise

1. Open Settings with Command-comma and choose Pointer at edge under Control visibility.
   The change applies immediately, independently of Save settings or Cancel.
2. Close Settings and leave the pointer over the map for 15 seconds.
   Both bars disappear, including North up and radius, while the clock, Synthetic badge, origin, zoom/home controls, and any selected-object inspector remain available.
3. Move the pointer to the top edge of the map, immediately below the macOS title area, then to the bottom edge.
   Each edge reveals only its own bar, and each bar hides 15 seconds after the pointer leaves its controls.
4. Open MAP, toggle Routes, Airspace, and Airports, apply a flight-level preset or valid direct entry, and inspect Map data and updates.
   The top bar stays visible while the popover is open, including its nested map-data popover.
5. Open a Sweep or View menu and leave it open longer than 15 seconds.
   The top bar remains available while the menu is in use.
6. Choose Caret buttons in Settings.
   After the initial display, use the downward top caret and upward bottom caret to reveal each bar independently.
   An explicitly revealed bar stays open until its reversed caret is clicked again.
7. Choose Always visible and wait longer than 15 seconds.
   Both bars remain visible and caret buttons are absent.
   Relaunch to confirm the selected mode is saved.
8. Repeat with a selected aircraft at 1200 by 800 and the minimum 800 by 560 window size.
   Check that clock, controls, source health, and counts remain readable and that toggling a bar does not shift map geography or the Home crosshair.
9. With Always visible, pan contacts underneath a bar and right-click that bar.
   No map chooser opens through the panel, while a secondary click on an exposed contact still opens the chooser.
10. Inspect a source failure and any applicable missing-Home or online-search-limit message.
    Reception status updates remain in the footer without forcing it open; map messages remain independently visible.

## Results

The isolated candidate passed all 108 tests (76 RadarCore and 32 ADSBRadar tests), plus debug and release builds.
Preference, visibility-controller, and reception-layout tests were rerun after the final native hit-testing adjustment.
Native previews were inspected at normal and minimum sizes with an open aircraft inspector.
Interactive fixture checks covered independent top and bottom pointer-edge reveal, hiding again after leaving controls, startup hiding, hidden-bar access to Settings, immediate mode changes, independent caret toggles, caret pinning, Always visible, mode persistence across relaunch, MAP layer toggles, flight-level selection, and nested map-data access.
The native review reproduced secondary-click selection through a visible top panel; the corrected candidate blocks that click while retaining selection on the exposed map.
The standards review found no actionable issues.
The specification review's secondary-click finding was fixed and its recheck found no remaining issues.

The suite ran from an isolated export of the staged candidate so concurrent navigation-control work was excluded.
Live receiver hardware and live online-provider availability are outside this presentation change and were not rechecked.
