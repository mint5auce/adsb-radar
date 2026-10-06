# Aircraft view decluttering and filtering

The design interview is complete.
The recommendations through Q27 were accepted on 6 October 2026.
Implementation is complete in issues #20-26.
See [the verification record](../decluttering-verification.md) for automated and native checks and exact manual exercise steps.

## Accepted foundations

Use automatic label decluttering alongside explicit aircraft view filters.
Suppress overlapping labels while retaining aircraft symbols, and always show the selected aircraft's label.
The main interests are traffic near Home, altitude, larger and commercial aircraft, and a general overview.
Keep receiving and ageing hidden aircraft normally, preserving their trails so clearing a filter can restore the current picture immediately.
Show a clear filtered count and provide one Clear filters action.

## Accepted distance, altitude, and type controls

Anchor the optional distance filter to saved Home, independently of panning.
Provide configurable distance entry and 25, 50, and 100 NM shortcuts displayed in the chosen units.
Use an independent minimum/maximum reported-altitude filter in the chosen altitude units, unrestricted in the general overview.
Keep aircraft altitude filtering independent of the separately agreed airspace flight-level slice.
Do not interpret reported altitude as height above terrain.
Provide a Larger aircraft shortcut and individual size/category choices, including larger business jets alongside airliners and freighters.
Do not claim commercial/private operation without reliable data.
Provide an Include unknown option for each applicable filter, enabled by default.
Keep unknown aircraft eligible for enrichment so filtering cannot prevent their later classification.

## Accepted presentation behaviour

Keep a selected aircraft eligible for display outside active filters until deselected, with an Outside filters note.
The exception does not force it into the viewport or make the map follow it.
Normal ageing and removal still apply to the selected aircraft.
Try several nearby label positions and suppress labels that still overlap, preferring stable placement and always prioritising the selected label.
Reveal more labels as zoom creates space.
Draw aircraft symbols above label backgrounds so labels cannot cover contacts.
Default to the selected aircraft's trail only, with All, Selected, and None trail-display choices.
Continue retaining normal trail history regardless of its display choice.
Keep short direction vectors visible by default and provide an independent display switch.

## Accepted classification and ground policy

Use reported emitter categories for size filtering in the first version, without inferring weight categories from an aircraft-model database.
Keep unavailable categories explicitly unknown, and support searches for model codes such as A320.
Provide Light, Small, Large, Heavy, High-performance, Helicopters, and Other category choices.
Group the reported high-vortex large category with Large while preserving its specific category in the inspector.
The Larger aircraft shortcut selects Small, Large, and Heavy, corresponding to reported categories A2 through A5.
These weight categories cover aircraft from approximately seven tonnes maximum takeoff weight upwards.
High-performance and rotorcraft categories do not establish weight, so the shortcut does not include them automatically.
Include unknown remains independently configurable and enabled by default.
Retain the last known reported category with provenance and update date, using the existing identity-cache and refresh policy.
Prefer a valid current Local category report over Online or cached category information.
Missing or unknown later reports must not erase a useful known category or falsely advance its update date.
When permitted, enrichment can fill category information without adding contacts or changing their movement, position age, or active position source.
Ordinary reception can still supply category information when dedicated enrichment is disabled.
Keep Synthetic isolated from real identity and category information.
Include ground aircraft in the unrestricted general overview and provide an accessible Hide ground aircraft switch.
Hide ground aircraft only when ground status is explicitly reported, not inferred from low altitude or zero speed.
An active numeric altitude range also excludes explicitly grounded aircraft because Ground is not a numeric altitude.
Explain this alongside the altitude controls.
Unknown numeric altitude follows its separate Include unknown setting.

## Accepted controls, persistence, and selection

Provide a Filters button opening a compact panel and display summaries of active filters alongside it.
Apply toggles and category choices immediately, and apply numeric entries when committed.
Remember active aircraft filters and presentation choices between launches, with an obvious active-filter indicator on startup.
First launch uses an unrestricted overview, Automatic labels, Selected trails, and enabled direction vectors.
The Contacts list contains matching contacts and the selected exception, identifying contacts outside the current map view.
Search callsign, ICAO address, registration, and aircraft-model code within the Contacts list without changing map filters.
Provide Automatic, All, and Selected only label modes, defaulting to Automatic.
Keep callsign and altitude readable rather than shrinking text to fit dense traffic.
In Automatic, prioritise selection and fresh contacts, retain existing label placement where practical, and favour contacts nearer Home when space remains contested.
An ambiguous aircraft click opens a short chooser identifying nearby candidates by callsign/address, altitude, and known model.
Retain individual aircraft symbols instead of adding clusters in the first version.
Require all active filter criteria to match, while any selected category matches within the category criterion.
Apply Include unknown independently to the field it concerns, and retain the explicit selected-aircraft exception.
Apply inclusive distance and altitude limits to the values used for the displayed contact, without an invisible buffer or delay.
Clear filters restores unrestricted aircraft criteria while preserving labels, trails, direction-vector preferences, and selection.
Contacts search has its own clear action.
Selecting an offscreen aircraft does not pan the map automatically.
Provide Show on map to centre the selected aircraft explicitly, without moving saved Home.
Changing aircraft criteria leaves existing pan and zoom available; Return home remains the explicit control for returning to Home.

## Accepted presets

| Preset | Home distance | Reported altitude | Categories | Hide ground |
| --- | --- | --- | --- | --- |
| Overview | Unrestricted | Unrestricted | All | Off |
| Near Home | 50 NM | Unrestricted | All | On |
| Larger near Home | 50 NM | Unrestricted | Small, Large, Heavy | On |
| Higher traffic | Unrestricted | Minimum 10,000 FT | All | On |

Display preset distance and altitude values in the user's chosen units.
Presets are editable starting points, and the current filter configuration is remembered between launches.
Include unknown remains configurable for each applicable filter, enabled by default.
Named custom presets are outside this first version.
Presets configure aircraft criteria, independently of label, trail, and vector display preferences.

## Accepted counts and validation

Report In view, Outside view, and Filtered as distinct counts.
In view and Outside view partition the eligible positioned contacts, including a selected-aircraft exception.
Filtered counts the other retained positioned contacts excluded by aircraft criteria.
Make the total received positioned-contact count available in the Contacts panel.
Keep the count heard without positions separate from presentation filtering.
List search does not change these map counts.
Show invalid numeric input inline and retain the last valid filter until it is corrected.
Reject a minimum altitude greater than its maximum and require a positive Home distance.
If Home is unavailable, clearly mark the distance filter unavailable while other filters continue working.
The Home distance filter does not inherit adsb.fi's 250 NM request-radius cap.
Aircraft filtering changes neither the provider's viewport search nor its shared allowance.
Moving or clearing aircraft filters must not discard received history or manufacture fresh position observations.

## Constraints recorded before implementation

The original renderer put a two-line label at a fixed offset beside every positioned aircraft, without collision handling.
Every aircraft also drew its available trail and direction vector.
Registration and aircraft-type codes are optional enriched fields; commercial/private operation and broad aircraft classes are not currently represented.
Both the compatible online schema and local readsb output support optional reported emitter categories, which the original app discarded.
These categories describe airframe size or characteristics rather than commercial/private operation.
Reported altitude may come from barometric or geometric observations, and the current contact model does not preserve that distinction.
The separately planned flight-level slice concerns airway and controlled-airspace overlays, not aircraft visibility.

## Verification brief

Test independent filter criteria, inclusive boundaries, AND composition across criteria, OR composition within categories, unknown values, explicit ground status, last-known categories, valid Local precedence, cache provenance, and failed enrichment.
Check that hidden aircraft keep ageing and receiving updates, retain trails, reappear immediately when criteria are cleared, and cannot be selected through invisible map hit targets.
Test selection exceptions, removal, offscreen selection, Show on map, matching Contacts entries, list-only searches, and consistent counts.
Verify unit changes, invalid numeric input, missing Home, preset changes, preference migration, relaunch persistence, and isolation of Synthetic identities.
Exercise stable label placement and priorities, zoom-dependent label availability, readable label modes, symbol visibility above backgrounds, trail/vector switches, and ambiguous-click selection.
Inspect the native app with sparse and dense fixtures, including 250-aircraft Demo traffic and dense airport-like clusters, at normal and minimum window sizes.
Include ground aircraft, unknown values, stale contacts, coincident markers, selected contacts outside filters, and map pans away from Home.
Verify both Immediate and Sweep modes and the distinction between aircraft altitude filtering and the separate airspace flight-level slice.
Document exact candidate build/start and manual steps during implementation.

## Source findings

[adsb.fi](https://github.com/adsbfi/opendata/blob/main/README.md) declares compatibility with the [v2 response fields](https://www.adsbexchange.com/version-2-api/), including optional emitter category and model code.
[Reported category definitions](https://support.adsbexchange.com/hc/en-us/articles/44705224053517-Emitter-Category-ADS-B-DO-260B-2-2-3-2-5-2) separate light, small, large, high-vortex large, heavy, high-performance, and rotorcraft categories.
[Local readsb JSON](https://github.com/wiedehopf/readsb/blob/dev/README-json.md) supplies category independently of a type database.
[Mictronics' licensed type export](https://github.com/Mictronics/aircraft-database) supplies structural descriptions and wake categories, but its inspected fields do not distinguish airliners from business jets or commercial from private operations.
Do not equate a wake category from a type database with a reported emitter weight category.
