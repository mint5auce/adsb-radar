# Airport and route data sources

Research date: 6 October 2026.

## Recommendation

Use OurAirports for the first airport-location layer.
Investigate the NATS UK ICAO AIP Dataset for published UK airways and waypoints, with EUROCONTROL EAD as the broader European alternative.
Treat an aircraft contact's origin and destination as a separate enrichment feature, initially evaluating adsb.lol and considering FlightAware if stronger commercial support is needed.

These are different meanings of route: an airport-to-airport connection, a published airway made of waypoint segments, a filed flight plan, and the track an aircraft actually flew.
The proposed sources below do not provide all four interchangeably.

## Airport locations: OurAirports

[OurAirports publishes nightly UTF-8 CSV downloads](https://ourairports.com/data/) for airports, runways, airport frequencies, navaids, countries, and regions.
The data is public domain and attribution is appreciated rather than required.
Airport records include coordinates, elevation, name, type, and airport identifiers; the [data dictionary](https://ourairports.com/help/data-dictionary.html) documents the fields and joins.
The persistent numeric `id` survives airport-code changes, while `ident` is the interoperability identifier and is an ICAO code only when available.
Do not assume every airport has an IATA or ICAO code.

The direct [airports.csv download](https://davidmegginson.github.io/ourairports-data/airports.csv) is suitable for a small scheduled import into a local store.
This is the best initial choice for a cached airport layer that works without an API key or ongoing service dependence.
Runway and radio-navigation-aid files could extend that layer later.

## Published UK airways: NATS digital dataset

The [NATS digital datasets page](https://nats-uk.ead-it.com/cms-nats/opencms/en/Publications/digital-datasets/) lists a UK ICAO AIP Dataset on a 28-day cycle and showed an effective date of 1 October 2026 during research.
The current signed [UK digital dataset specification, version 2.0 dated 19 March 2026](https://nats-uk.ead-it.com/cms-nats/export/sites/default/en/Publications/digital-datasets/UK-Digital-Dataset-Specification-SPC_AIM006_04_V2.0-Signed.pdf) specifies AIXM 5.1, an XML-based aeronautical exchange format.
Its scope includes routes, route segments with start/end points and altitude limits, designated points, navaids, airports, and runways.
That is the relevant topology for drawing named airway segments, rather than simply joining departure and arrival airports.

The current specification states aviation-only use, no resale, and unrestricted access/usage; this is not a public-domain licence.
Follow-up inspection found download links in the raw page HTML that the initial web text extraction missed.
The [1 October 2026 XML package](https://nats-uk.ead-it.com/cms-nats/export/sites/default/en/Publications/digital-datasets/ICAO_AIP/EG_AIP_DS_20261001_XML.zip) downloaded without an account, parsed successfully, and matched its supplied SHA256 checksum.
Its XML contains 220 routes and 1,217 route segments, but every segment's left and right width is explicitly unknown.
These centrelines therefore cannot supply authoritative bounded corridors, and navigation-performance values must not be substituted for widths.
The package also contains 2,398 airspace volumes/surfaces, including published boundary geometry for control areas, control zones and terminal control areas.
These geometries include polygons, arcs and circles and are distinct airspace features rather than per-route corridor buffers.
Route lower limits include 1,183 standard-pressure references and 34 mean-sea-level references, while airspace limits also include surface-relative heights and some missing limits.
A flight-level filter must preserve these reference distinctions rather than comparing every limit as interchangeable feet.
Operational hours are represented in annotations rather than supported Timesheets, so the package alone does not establish that every displayed area is currently active.
Do not confuse the separate [dataset evaluation page](https://nats-uk.ead-it.com/cms-nats/opencms/en/Publications/Dataset-Evaluation/) with the regular AIP dataset; the evaluation page currently lists instrument-flight-procedure evaluation data.

## Wider airways: EUROCONTROL EAD

[EUROCONTROL static data operations](https://www.eurocontrol.int/service/static-data-operations) supports local database imports from AIXM 4.5 and AIXM 5.1 downloads.
The [EAD data-content catalogue](https://ext.eurocontrol.int/aixm_confluence/display/EDC) includes route segments and their start/end points, tracks, altitude limits, and availability.
[EAD access](https://www.eurocontrol.int/service/european-ais-database) includes an agreement-based professional service, with charging dependent on the user category and use case.
Its periodic data-download option is explicitly intended to populate local systems, including updates by AIRAC cycle.
EAD Basic is a free registration-based consultation service with limited content, not an equivalent unrestricted bulk API.

## Airspaces and navaids: openAIP

The directly fetched [openAIP OpenAPI schema](https://api.core.openaip.net/api/system/specs/v1/schema.json) describes JSON endpoints for airports, airspaces, navaids, reporting points, obstacles, and related objects.
It supports geographic filtering and pagination and requires an API key obtained from an account's API Clients page.
The same live schema declares CC BY-NC 4.0 and requests attribution to openAIP; commercial use therefore needs separate confirmation.
This differs from secondary descriptions that incorrectly add a ShareAlike requirement.

The inspected schema has no airway or route endpoint, so openAIP should be considered for adjacent map layers rather than assumed to supply an airway graph.
An [issue in the official repository](https://github.com/openAIP/openaip/issues/292) documents country exports in formats including GeoJSON, JSON, and OpenAir, but a sample legacy bucket URL did not successfully download during this research.
The API is the verified interface; current bulk-export access still needs validation.

## Aircraft contact origin and destination: adsb.lol and FlightAware

The [adsb.lol API](https://api.adsb.lol/docs) documents `POST /api/0/routeset`, taking `planes` entries containing `callsign`, `lat`, and `lng`.
Its [live OpenAPI schema](https://api.adsb.lol/api/openapi.json) describes a free API under ODbL 1.0, asks production users to contact the operator, and warns that API keys may become required in future.
The route response is not usefully typed in that schema, and one sample request returned an empty response, so route coverage and the current response contract were not validated.
Treat this as a candidate to test with representative live aircraft contacts, not a guaranteed complete route database.

[FlightAware AeroAPI](https://www.flightaware.com/commercial/aeroapi/) is a commercial REST/JSON alternative with flight lookup, origin/destination searches, filed-route, and recorded-track endpoints and usage-based billing.
Access requires an account and API key, and use is governed by its [standard licence](https://www.flightaware.com/commercial/aeroapi/AeroAPI_Standard_License.pdf).
Its own [support documentation](https://support.flightaware.com/hc/en-us/articles/33161341318935-Why-Is-A-Frequently-Used-Endpoint-Returning-A-Null-Value) warns that international waypoint decoding is unavailable for the route endpoint, so it should not be selected on the assumption of complete UK flight-plan geometry.
No paid API calls or account setup were performed.

## Sources to approach cautiously

[OpenFlights](https://openflights.org/data.html) offers CSV-style `.dat` downloads, including airline connections between airports, under ODbL terms.
Its [official page source](https://github.com/jpatokal/openflights/blob/master/data.php) explicitly says the route provider stopped updates in June 2014 and the route data has historical value only.
That makes it useful for demonstrations or historical network visualisation, not current route enrichment.

[X-Plane documents parseable navigation files](https://developer.x-plane.com/article/navdata-in-x-plane-11/), including `earth_awy.dat`, `earth_fix.dat`, and `earth_nav.dat`.
The supplied base cycle remains unchanged over the simulator version's lifetime; current cycles come from third-party subscriptions.
The [developer data overview](https://developer.x-plane.com/docs/data-development-documentation/) directs users to each file's source and copyright notice.
A published format specification does not establish permission to bundle or redistribute a particular provider's dataset, so simulator files are a possible licensed import path rather than the preferred default source.

## Integration implications

Keep airport locations and airway geometry separate from online enrichment of individual aircraft contacts.
Store source and effective-cycle metadata with imported map data, replace snapshots atomically, and retain the last valid snapshot when a refresh fails.
Do not label an airport-to-airport line as the aircraft's actual or filed path.
The most useful next step is to resolve the display policy for published airspace boundaries alongside widthless route centrelines, then validate representative geometry and altitude references before implementation.
