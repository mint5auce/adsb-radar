# Phosphor product specification

This is the accepted design for a personal macOS application that displays live aircraft information from an RTL-SDR receiver in the style of a vintage military tactical display.
The initial hardware is a generic dongle, with compatible RTL-SDR V4 support retained.
The product is for enjoyment and exploration, with testing and hardening proportionate to that use.

Use the vocabulary in [GLOSSARY.md](../GLOSSARY.md).
The choice of native SwiftUI, including acceptance of a separate future Linux interface, is recorded in [ADR 0001](adr/0001-native-swiftui-for-macos.md).

## Initial scope

Build a native SwiftUI macOS application using local ADS-B reception first.
Keep aircraft data sources replaceable so an online feed can supplement coverage later.
Linux is a future release with a potentially different interface.
Direct macOS distribution uses signed, notarised application archives on GitHub Releases with Sparkle updates.

## Application updates

Keep the existing SwiftPM workflow and macOS 14 minimum.
Distribute a universal application for Apple silicon and Intel with bundle identifier `dev.mint5auce.phosphor`.
The Phosphor rename starts a fresh application identity, with no migration of ADSB Radar preferences or caches.
Leave the old application's local data untouched.
Use `phosphor-settings` for preferences, `dev.mint5auce.phosphor` for aircraft identities, and `Phosphor/MapData` for downloaded map snapshots.
Use `PHOSPHOR_LATITUDE` and `PHOSPHOR_LONGITUDE` for development location overrides, without aliases for the former environment variables.
Use Sparkle's standard update dialogs, an application-menu Check for Updates action, and update preferences in Settings.
Ask permission for automatic checks and use a daily interval once enabled.
Allow users to opt into automatic download and installation; leave that choice off initially.
Update preferences apply immediately and persist through Sparkle rather than the phosphor-settings draft.
Keep update startup disabled in development builds, previews and tests.
Update checks and failures must leave normal radar operation usable, including offline operation.
During update installation, preserve the existing shutdown path so the app-owned decoder stops and cached aircraft identities finish saving before relaunch.
Preserve the user's settings and cached data across application updates.

Sign and notarise the app with Developer ID, and sign both update archives and the appcast with Sparkle's EdDSA key.
Publish version-specific downloads on GitHub Releases and the signed appcast on GitHub Pages.
Verify the anonymous archive download before deploying a feed that advertises it.
Keep build numbers increasing and reject attempts to replace published release assets.
Start with full archives and one stable update channel.
The first Phosphor release requires manual installation, including for existing ADSB Radar users.
Keep version `0.2.0`, build `2`, and reuse the configured Developer ID and Sparkle signing keys.
Prepare the update feed at `https://jon-hadley.com/phosphor/appcast.xml`; deployment and live update verification follow the first signed release.
Use GitHub Release asset download counts for distribution metrics, with no usage heartbeat or system profiling.
Document release preparation, credentials, verification and recovery in [the release guide](releasing.md).

## Visual direction and exploration

Use [Air Defender](https://airdefendergame.com/) as the visual reference: a rectangular tactical map with a black background, fine green geography, compact monospaced labels, aircraft direction vectors, and trails.
Use callsign and altitude for aircraft labels, subject to the chosen label mode and automatic decluttering.
Selecting a contact reveals its available details, including the source and age of its last position.
Show unavailable fields explicitly as unknown.

The map is north-up and supports free pan and zoom.
Start centred on a saved, manually entered home location, which can be changed in settings and represents the receiver location when using local reception.
Reuse this saved location across real-data source modes, labelling it Home location in Online mode.
Require a manually entered location before starting Online mode if none is saved; do not detect the user's location automatically.
Keep range rings and the simulated sweep anchored to that geographic location when panning.
Provide a return-to-receiver control, labelled Return home in Online mode.

Bundle a lightweight coastline and border background so the geographic display and local reception work offline.

## Startup presentation and control visibility

The following visual changes were accepted on 6 October 2026 and are implemented.
See [the verification record](control-visibility-verification.md) for automated checks and native exercise steps.
They supersede the earlier first-launch presentation defaults in the aircraft-view and airway designs.

### First-launch preferences

When no saved preferences exist, start with Routes, Airspace, and Airports disabled, Labels set to All, Trails set to All, and direction vectors enabled.
Keep the bundled coastline and border background visible.
All labels intentionally permits overlaps in dense traffic; Automatic and Selected only remain available.
Preserve existing saved presentation choices, including when an installation is replaced but preferences remain.
Retain the previous presentation defaults when decoding older saved preferences that lack those fields, rather than treating them as a fresh installation.
Use Pointer at edge as the default for the new control-visibility preference, including existing installations without that preference.

### Compact layout

Keep the established phosphor colours and monospaced typography.
Combine compact branding and aircraft actions into the top row, retaining access to source identification, update mode, Filters, View, Contacts, Settings, and the Synthetic restart action.
Put a Map button beside Sweep, Filters, View, and Contacts, with the same visual treatment and a popover containing map-layer switches, flight-level controls, and map-data information.
Move North up and the current viewing radius into the top bar, so they hide with it.
Arrange source health and contact counts horizontally in a compact footer, retaining separate Local and Online status and existing attribution.
Keep controls and status readable at the minimum window size, adapting the layout rather than clipping essential content.

The top controls and footer slide independently over the radar map on opaque dark panels.
Revealing or hiding them keeps the map dimensions and geographic framing stable.
Keep the UTC clock visible on the map with a small black background tightly surrounding its text, removing the full-width black strip behind the current top map information.
Keep a small Synthetic badge beside the clock while synthetic aircraft data is active, including when both bars are hidden.
Origin coordinates, home/receiver and zoom controls, range-ring labels, and the selected-object sidebar remain available independently of bar visibility.
Existing map messages, including missing Home, no positioned contacts, geography status, and the online search-limit notice, remain visible when applicable.

### Visibility modes and persistence

Offer Pointer at edge, Always visible, and Caret buttons in Settings and remember the selected mode between launches.
Apply mode changes immediately.
Remember the mode rather than each bar's last expanded or collapsed state.
On each launch, initially show both bars for 15 seconds in Pointer at edge and Caret buttons modes, keeping controls visible while they are being used.
Always visible keeps both bars expanded and bypasses automatic hiding.

In Pointer at edge mode, approaching the top edge reveals the top controls and approaching the bottom edge reveals the footer.
After a reveal, hide the corresponding bar after the pointer has been away from its controls for 15 seconds.
Keep the associated controls visible while their menus, popovers, or settings sheet are open.

In Caret buttons mode, leave a visible downward-pointing caret at the top and an upward-pointing caret at the bottom when the respective bars are hidden.
Each caret reveals only its associated bar and reverses direction while that bar is expanded.
After an explicit reveal, keep that bar open until its caret is clicked again.
The initial 15-second startup display still applies before any explicit reveal.

Reception failures do not automatically reveal a hidden footer.
Show the current source status when the footer is revealed, while preserving the independently visible map messages.
Hiding controls changes presentation only; normal reception, contact updates, and ageing continue.

### Verification brief

Check fresh preferences, existing explicit preferences, and older saved preferences missing presentation fields separately.
Verify all three visibility modes, independent bar state, the startup timer, pointer-away timing, caret toggles, interaction holds, immediate settings changes, and relaunch behaviour.
Inspect normal and minimum window sizes, including an open inspector, active filters, long source failures, and both Test and dense Demo traffic.
Check that North up and radius hide with the top bar while the clock, Synthetic badge, and retained map information remain legible and unobscured.
Confirm that showing and hiding bars does not change map framing, trigger map interactions through the panels, or interrupt reception.
Record exact candidate build/start commands and manual exercise steps when implementing these changes.

## Aircraft view decluttering and filtering

The accepted design is recorded in [the detailed design](design/aircraft-view-decluttering.md).
Offer automatic label decluttering alongside explicit aircraft view filters, retaining individual aircraft symbols.
Prioritise the selected label and fresh contacts, prefer stable nearby label placement, and suppress labels that still overlap.
Reveal more labels as zoom creates space and draw symbols above label backgrounds.
Provide Automatic, All, and Selected only label modes without shrinking callsign/altitude text to fit crowded traffic.
Use the [startup presentation policy](#startup-presentation-and-control-visibility) for initial label, trail, and direction-vector preferences.
Provide All, Selected, and None trail-display choices plus an independent direction-vector switch, while retaining normal trail history regardless of its display.

Offer an optional distance limit around saved Home, independent minimum/maximum reported-altitude limits, reported aircraft categories, and Hide ground aircraft.
Distance shortcuts start at 25, 50, and 100 NM, with custom values and chosen distance units.
Altitude limits use chosen altitude units and remain independent of the airspace flight-level slice.
Do not interpret Ground as zero altitude or reported altitude as height above terrain.
Hide only explicitly grounded aircraft when Hide ground aircraft is enabled, and exclude them from active numeric altitude bands with an explanatory note.
Provide Light, Small, Large, Heavy, High-performance, Helicopters, and Other categories, grouping high-vortex large with Large.
The Larger aircraft shortcut includes Small, Large, and Heavy reported categories, approximately seven tonnes maximum takeoff weight and upwards.
Do not infer commercial/private operation or emitter weight categories from a model's wake category.
Keep an independent Include unknown choice for each applicable field, enabled by default.
Retain last-known reported category information with provenance and successful update date, using the existing cache/refresh approach and preferring valid current Local reports.
Permitted enrichment may fill category information but must not add contacts or change movement, position age, or active position source.

Combine active criteria with AND, and selected categories within their criterion with OR.
Apply inclusive boundaries to the displayed contact values without a hidden tolerance or delay.
Keep receiving and ageing filtered aircraft normally, preserving selection eligibility and history independently of their display.
A selected aircraft remains eligible outside filters until deselected, with an Outside filters note, but normal removal still applies.
This exception does not force the aircraft onscreen or make the map follow it.
Selecting an offscreen aircraft opens its details without automatic panning; Show on map centres it explicitly without moving Home.

Provide a Filters panel accessible from the map, visible active-filter summaries, and one Clear filters action.
Toggles and categories apply immediately, while numeric entries apply when committed and valid.
Invalid entries explain the problem inline and leave the previous valid filter active.
Require positive distance and a valid altitude range, and mark Home distance unavailable if no Home is saved while other criteria continue to work.
Do not impose the provider's search-radius cap on the presentation distance limit.
Clear filters restores unrestricted criteria while retaining presentation preferences and selection.

Provide editable Overview, Near Home, Larger near Home, and Higher traffic starting presets with the values in the detailed design.
Remember the active aircraft criteria and presentation choices between launches, with an obvious active-filter indicator.
First launch uses unrestricted aircraft criteria, including ground aircraft.
Named custom presets and aircraft clusters are outside this first version.
Use the same presentation controls across source modes while retaining the existing real/Synthetic isolation and source-transition rules.

The Contacts list follows aircraft criteria plus the selected exception, marking contacts outside the current view.
Search callsign, ICAO address, registration, and model code within that list without changing map filters or counts, and provide a separate clear-search action.
An ambiguous aircraft click opens a short chooser of eligible nearby contacts with callsign/address, altitude, and known model.
Report In view, Outside view, and Filtered separately, making the total received positioned contacts available in the Contacts panel and keeping heard-without-position counts separate.
Aircraft filters do not alter the existing online viewport request, provider allowance, or ordinary contact lifecycle.
Unknown aircraft in the viewed area remain eligible for permitted enrichment even when filtering hides them.

Verify filtering, category ingestion and caching, provenance, selection exceptions, counts, search, boundaries, preferences, and display-only lifecycle effects with focused deterministic checks.
Inspect sparse and dense native views, including 250-aircraft Demo traffic and airport-like clusters, at normal and minimum window sizes in both update modes.

## Airway visualisation

The design and implementation-ticket breakdown are accepted.
Implementation is tracked in [ATS routes #10](https://github.com/mint5auce/phosphor/issues/10), [controlled airspace #11](https://github.com/mint5auce/phosphor/issues/11), [airport markers #12](https://github.com/mint5auce/phosphor/issues/12), [flight-level slicing #13](https://github.com/mint5auce/phosphor/issues/13), and [map-data updates #14](https://github.com/mint5auce/phosphor/issues/14).
Provide independently switchable layers for airways, wider controlled airspace, and simple airport markers sourced from OurAirports.
Exclude detailed airport layouts, arrival and departure procedures, and restricted-area overlays from this feature.
Initially use the UK coverage supplied by NATS, make the dataset extent explicit, and retain normal radar operation outside that extent.
Allow additional country datasets in future.
Default to an All levels view of the network, with an optional flight-level slice to reduce overlay clutter.
The slice filters route and controlled-airspace overlays while aircraft contacts and airport markers remain visible.
Selecting an airway segment reveals its floor and ceiling.
Preserve the established phosphor style, with subtle overlay fills and boundaries and brighter aircraft contacts.
Use the [concept mockup](design/airway-visualisation-concept.png) as a visual reference for contrast, density, and layout.
Its invented corridor widths and geometry are illustrative; the source-backed representation below governs implementation.

Draw published controlled-airspace boundaries alongside ATS route centrelines.
The current NATS sample contains route centrelines with unknown widths, so do not invent widths or depict per-route corridor boundaries unsupported by the data.
Selecting a route highlights its centreline; selecting an airspace region highlights its published boundary.
Show unknown width explicitly when inspecting a route segment.

Provide a bundled map-data snapshot and a manual Check for map updates control.
Show the effective date of each dataset, validate downloaded replacements before activation, and retain the previous snapshot if an update fails.
The map layers work offline from the bundled or last successfully downloaded snapshot.

For a flight-level slice, filter limits that can be directly compared with the selected level.
Keep regions with incomparable or missing altitude limits dimly visible and show an Uncertain slice status in their inspector.
Preserve published altitude references and units in the inspector.
This remains a novelty feature for enjoyment and exploration: uncertainty handling is a small inspector note, without pressure setup, terrain modelling, or warning banners.

Show large and medium airports at normal viewing scales and introduce small airports as the user zooms in.
Exclude closed airports, heliports, and seaplane bases initially.
Selecting an airport shows its name, codes, and elevation.

Use the [startup presentation policy](#startup-presentation-and-control-visibility) for initial layer switches and remember layer switches and the altitude view between launches.
Show airport codes and sparse route names, introducing waypoint names and smaller features as the user zooms in.
Keep aircraft labels visually dominant and always label the selected feature.

Normal clicks prioritise aircraft contacts.
Clicking overlapping map features opens a short chooser, and a secondary click lists all selectable objects beneath the pointer, including aircraft contacts.
Use the existing sidebar for one selected object at a time, with published limits specific to the selected segment or region.
Clear a selected map feature and its inspector when a layer switch or altitude filter hides it.

Provide a compact All levels / At FL control with presets, direct flight-level entry, and small up/down steps.
Keep altitude uncertainty handling proportionate to the app's novelty purpose.

Verify data import, geometry, altitude-reference handling, layer preferences, selection, and failed-update retention with focused checks.
Inspect the native app with synthetic traffic at normal and minimum window sizes, including overlapping features, zoom-dependent detail, all-level and sliced views, offline startup, and return to normal aircraft selection.
See [the data-source investigation](research/aviation-data-sources.md) for verified source capabilities.

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

When Local or Local + Online is selected, the application starts the installed `readsb` decoder when it opens and stops the process it started when it quits or changes to a mode without local reception.
A one-time receiver software setup is acceptable.
If the dongle is missing or busy, keep the interface usable and show a clear reception status with Retry in Settings.
Stop automatic Local reception attempts when a missing dongle reaches the configured attempt limit, defaulting to three attempts including the initial start.
Show the missing-dongle status in orange with a direction to retry in Settings.
Retry in Settings starts a fresh attempt budget without restarting a working Online feed.
Empty decoder startup snapshots do not reset the missing-dongle attempt count.

Only plot aircraft contacts when a position is available.
Show a count of aircraft heard without positions in reception status.

## Sweep modes and contact freshness

Support immediate update mode and sweep-timed update mode.
In immediate update mode, update contacts as new information arrives while the sweep provides atmosphere.
In sweep-timed update mode, update contacts when the simulated sweep reaches them.
Both modes keep the sweep anchored to the home location.

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
| Missing receiver attempt limit | 3 attempts, including the initial start |
| Aircraft view criteria | Unrestricted, including ground |
| Label mode | All on first launch |
| Trail display | All aircraft on first launch |
| Direction vectors | Enabled |
| Routes, Airspace, Airports | Disabled on first launch |
| Control visibility | Pointer at edge |
| Include unknown filter values | Enabled for each applicable field |
| Online refresh interval | 5 seconds |
| Online search radius limit | 250 nautical miles |
| Enrich aircraft details online | Enabled |
| Identity enrichment refresh age | 7 days |

All settings in this table are configurable.
The stale and removal thresholds are both measured from the last available position observation.
The online search radius limit may be reduced but must not exceed adsb.fi's 250-nautical-mile maximum.
The online refresh interval must respect the provider's request-rate limit, currently no more than one request per second across all online requests.
Render search-limit notices using the configured radius and distance unit rather than hard-coded defaults.

## Synthetic aircraft data for offline use

Implementation is tracked in [issue #8](https://github.com/mint5auce/phosphor/issues/8).

Provide an interactive synthetic aircraft data source that works without a dongle, decoder installation, or network access.
Use the same radar display, contact lifecycle, selection, trails, units, pan, zoom, and update modes as local reception.
Keep synthetic operation clearly identified in the window and contact details.
Do not switch to synthetic aircraft data automatically when local reception fails.

Allow source selection between Local, Online, Local + Online, and Synthetic in settings and provide a `--synthetic` launch option for repeatable offline launches.
Keep synthetic aircraft data separate from real aircraft information.
Offer two synthetic scenarios: Test and Demo.
Remember the selected source and scenario between launches, with Local as the first-launch default.
Launch options override saved choices for that launch without rewriting them.
Switching between Local, Online, and Local + Online preserves selection and trails for contacts supported by a source that remains enabled.
Remove contacts available only from a disabled source.
Entering or leaving Synthetic clears contacts, trails, and selection while preserving location and display settings.
Stop sources that are no longer enabled, including any app-owned decoder process, while keeping sources shared by the old and new mode running.

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

## Online coverage

Support Online operation without a receiver and Local + Online operation that supplements local reception in the same view.
Represent each aircraft as one contact even when multiple sources provide information about it.
Prefer local positions while fresh and fall back automatically to fresh online positions when local reception becomes stale.
Mark the contact stale only when neither source has a fresh position.
Keep the active source identifiable in the contact details.

Request online traffic for the visible map area as the user pans and zooms, using one search circle centred on the map and bounded by the configured online search radius limit.
Preserve unrestricted pan and zoom even when the visible map exceeds that search circle.
When the search circle cannot cover the whole view, show its boundary and a short notice identifying the online search limit.
The boundary represents the requested area, not a guarantee of receiver coverage.
Local contacts may appear outside the online search circle.
When a contact leaves the online search area, retain its selection and trail while it ages normally until the configured removal threshold.
Continue updating that contact through local reception when available.
Do not make additional position-tracking requests outside the online search area to follow selected contacts.
Keep the sweep and range rings anchored to the saved home location when panning.

Refresh online traffic at the configured interval and request an update after panning settles, respecting the provider's request-rate limit.
Show Local and Online health separately in Local + Online mode.
Retry failed sources automatically with increasing delays, keeping any working source running without changing the selected source mode.
The configured missing-dongle attempt limit stops automatic Local retries until Retry in Settings starts a fresh cycle.
Continue applying the configured stale and removal thresholds to genuine position observation times during an outage.
Network activity must not block local reception, display updates, or contact ageing.

Include registration and aircraft type when supplied by the online feed, including for contacts whose active position comes from local reception.
Keep identity enrichment independent of position selection and position age.
Provide an Enrich aircraft details online setting, enabled by default, that permits adsb.fi lookups in Local mode.
Disabling this setting stops dedicated enrichment requests while leaving online position requests governed by the selected source mode.
Enrich visible contacts, prioritising the selected aircraft, reusing identity information from normal online position responses and batching missing lookups where supported.
Enrichment requests must share the provider's request allowance without delaying position updates.
Cache registration, aircraft type, and reported category between launches, with a configurable refresh age defaulting to seven days.
Refresh due identity information when the contact is encountered again rather than querying the entire stored cache in the background.
If a refresh fails, retain cached details and make their last-updated date available in the contact inspector.
Local mode continues to obtain its live aircraft positions solely from local reception, even when an enrichment response contains online positions.
Identity-only lookups must not introduce contacts, update their movement, refresh their position age, or change their active position source.
Enrichment failures must not interrupt reception or the radar display; retain known identity information and leave unavailable fields unknown.
Apply the provider's shared request-rate limit to both position requests and identity-enrichment requests.
Synthetic operation remains isolated from real aircraft data and does not perform online enrichment.
Photos, route lookups, and additional cockpit telemetry are outside the first online-feed addition.

Prefer free access; account registration is acceptable.
Use adsb.fi as the first online feed, keeping the provider replaceable.
Sharing receiver data or paying for access has not been agreed.
Local reception remains available independently of the online feed.

Verify provider response handling, observation timestamps, source preference and fallback, duplicate-contact handling, viewport search limits, request pacing, enrichment caching, mode transitions, and graceful failure with focused automated checks.
Use deterministic provider responses for automated checks so normal tests do not depend on internet access or live traffic.
Manually inspect all four source modes, configurable limits, panning beyond the search area, source health, offline operation, and persisted identity details in the native app.
Verify available live adsb.fi data during implementation and explicitly report any provider access or physical receiver checks that could not be completed.

## Verification and first milestone

Use focused automated checks for decoded data handling, position freshness, and display timing.
Manually verify the actual receiver lifecycle and inspect the native interface for visual quality, selection, pan, zoom, both sweep modes, settings, and offline operation.
Keep the effort appropriate to a personal project while making the core behaviour reliable.

The first milestone is a native macOS application displaying real locally received aircraft against the offline geographic background with the agreed interactions and configurable defaults.
Actual radio reception remains unverified at design acceptance.
