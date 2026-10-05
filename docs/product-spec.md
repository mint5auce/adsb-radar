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

## Reception lifecycle

The application starts the installed `readsb` decoder when it opens and stops the process it started when it quits.
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
