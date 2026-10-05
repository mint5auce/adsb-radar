# ADSB Radar product specification

This is the accepted design for a personal macOS application that displays live aircraft information from an RTL-SDR receiver in the style of a vintage military tactical display.
The initial hardware is a generic dongle, with compatible RTL-SDR V4 support retained.
The product is for enjoyment and exploration, with testing and hardening proportionate to that use.

Use the vocabulary in [GLOSSARY.md](../GLOSSARY.md).
The choice of native SwiftUI, including acceptance of a separate future Linux interface, is recorded in [ADR 0001](adr/0001-native-swiftui-for-macos.md).

## Initial scope

Build a native SwiftUI macOS application using local ADS-B reception first.
Keep aircraft data sources replaceable so an online feed can supplement coverage later.
Linux is a future release with a potentially different interface.
Consumer distribution is outside the initial scope.

## Visual direction and exploration

Use [Air Defender](https://airdefendergame.com/) as the visual reference: a rectangular tactical map with a black background, fine green geography, compact monospaced labels, aircraft direction vectors, and trails.
Show callsign and altitude beside aircraft contacts.
Selecting a contact reveals its available details, including the source and age of its last position.
Show unavailable fields explicitly as unknown.

The map is north-up and supports free pan and zoom.
Start centred on a saved, manually entered receiver location, which can be changed in settings.
Keep range rings and the simulated sweep anchored to that geographic location when panning.
Provide a return-to-receiver control.

Bundle a lightweight coastline and border background so the geographic display and local reception work offline.

## Application icon

Use the [supplied artwork](design/app-icon-reference.png) as the source for the macOS application icon.
Preserve its glossy dark rounded tile, green aircraft pointing towards the upper-right corner, green glow, and three short fading trail dashes running towards the lower-left corner.
Remove the white exterior background and presentation shadow, leaving transparent space around the tile.
Keep the tile's own shading and reflections.

Allow restrained simplification of glow and fine tile details at the smallest sizes while preserving the aircraft silhouette, direction, colours, and three-dash composition.
Do not redesign the artwork or add text, radar rings, or other motifs.
Keep the supplied reference and cleaned master artwork in tracked repository locations.
Generate the native icon representations reproducibly and install the application icon in both debug and release app bundles.
Retain macOS 14 support and the existing SwiftPM build workflow.

Verify the packaged icon and inspect small-size previews, Finder, and the running Dock icon.
Keep verification proportionate to an asset and packaging change.

## Reception lifecycle

When local reception is selected, the application starts the installed `readsb` decoder when it opens and stops the process it started when it quits or switches to synthetic aircraft data.
A one-time receiver software setup is acceptable.
If the dongle is missing or busy, keep the interface usable and show a clear reception status with a retry control.

Only plot aircraft contacts when a position is available.
Show a count of aircraft heard without positions in reception status.

## Sweep modes and contact freshness

Support immediate update mode and sweep-timed update mode.
In immediate update mode, update contacts as new information arrives while the sweep provides atmosphere.
In sweep-timed update mode, update contacts when the simulated sweep reaches them.
Both modes keep the sweep anchored to the receiver.

Measure position age from the source observation, independently of when the sweep or interface last refreshed.
When a contact becomes stale, dim it in amber at its last known position before removing it at the removal threshold.
Keep stale text in the selected contact's sidebar, with only callsign and altitude beside the map plot.
Expose position age in the selected contact's details.

## Configurable defaults

| Setting | Default |
| --- | --- |
| Update mode | Sweep-timed |
| Sweep revolution | 4 seconds |
| Altitude unit | Feet |
| Speed unit | Knots |
| Distance unit | Nautical miles |
| Stale position threshold | Position age of 15 seconds |
| Contact removal threshold | Position age of 60 seconds |
| Trail duration | 2 minutes during the current session |
| Initial viewing radius | 100 nautical miles |

All settings in this table are configurable.
The stale and removal thresholds are both measured from the last available position observation.

## Synthetic aircraft data for offline use

Implementation is tracked in [issue #8](https://github.com/mint5auce/adsb-radar/issues/8).

Provide an interactive synthetic aircraft data source that works without a dongle, decoder installation, or network access.
Use the same radar display, contact lifecycle, selection, trails, units, pan, zoom, and update modes as local reception.
Keep synthetic operation clearly identified in the window and contact details.
Do not switch to synthetic aircraft data automatically when local reception fails.

Allow source selection between Local and Synthetic in settings and provide a `--synthetic` launch option for repeatable offline launches.
Offer two synthetic scenarios: Test and Demo.
Remember the selected source and scenario between launches, with Local as the first-launch default.
Launch options override saved choices for that launch without rewriting them.
Switching sources clears contacts, trails, and selection while preserving receiver and display settings.
Stop the previous source before starting its replacement, including any app-owned decoder process.

Generate traffic around the saved receiver location.
If no receiver location is saved, use a documented bundled example location without saving it as the user's receiver location.
Keep the sweep and range rings anchored to the scenario's geographic origin.

The Test scenario is a repeatable sequence with moving aircraft, trails, missing optional fields, aircraft heard without positions, and stale contacts that disappear and recover.
Exercise the configured stale and removal thresholds in real time using genuine position age, including continued messages without new positions.
The Demo scenario shows many moving aircraft with fresh positions and complete callsign, altitude, speed, and direction information on varied routes.
Default Demo to 100 aircraft and allow counts from 25 to 250.

Provide a Restart control that clears scenario contacts, trails, and selection and restarts the same repeatable sequence with current observation timestamps.
Document offline launch commands and manual checks for both scenarios.
Use focused automated checks for repeatability, movement, timestamps, lifecycle transitions, and clean Demo data, with manual inspection of the normal native interface.

## Future online coverage

An online feed will supplement areas beyond local reception in the same view.
Represent each aircraft as one contact even when multiple sources provide information about it.
Prefer local positions while fresh and fall back automatically to fresh online positions when local reception becomes stale.
Mark the contact stale only when neither source has a fresh position.
Keep the active source identifiable in the contact details.

Prefer free access; account registration is acceptable.
Provider selection remains open, and sharing receiver data or paying for access has not been agreed.
The online feed is a later addition rather than a dependency of the initial local viewer.

## Verification and first milestone

Use focused automated checks for decoded data handling, position freshness, and display timing.
Manually verify the actual receiver lifecycle and inspect the native interface for visual quality, selection, pan, zoom, both sweep modes, settings, and offline operation.
Keep the effort appropriate to a personal project while making the core behaviour reliable.

The first milestone is a native macOS application displaying real locally received aircraft against the offline geographic background with the agreed interactions and configurable defaults.
Actual radio reception remains unverified at design acceptance.
