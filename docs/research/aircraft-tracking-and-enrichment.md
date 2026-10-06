# Aircraft tracking and enrichment sources

Research checked on 6 October 2026 against official documentation and provider source repositories.
This is a provider assessment, not an accepted change to the product specification.
The project currently prefers free online coverage and has not agreed to receiver sharing or paid access.

## Suggested shortlist

For the personal macOS application, evaluate adsb.fi and adsb.lol first for additional positions, then add an independent aircraft-information lookup for selected contacts.
OpenSky is useful for comparison and research, while Flightradar24 and ADS-B Exchange are paid alternatives with different enrichment and historical capabilities.
An online provider often redistributes ADS-B observations; choosing another provider does not itself introduce a different positioning technology.
Compare actual coverage around the receiver before deciding, because none of the documentation establishes which network will be best at that location.

| Provider | Access and practical limits | Useful additions |
| --- | --- | --- |
| adsb.fi | Public personal/non-commercial API, one request per second; attribution and link required | ADS-B/MLAT coverage and compatible aircraft metadata |
| adsb.lol | Public free API currently, dynamic rate limits; future feeder-issued keys mentioned | ADS-B/MLAT coverage, aircraft metadata, plausible routes and open historical traces |
| OpenSky | Anonymous or account access with daily credits; more credits for active feeders | Position provenance and timestamps, historical movements, aircraft categories |
| ADS-B Exchange | Current developer offering is paid; enterprise licensing for larger/commercial use | Positions, registration/type/flags, richer raw surveillance fields; enterprise history/enrichment |
| Flightradar24 | Paid API subscription separate from consumer plans, charged by returned entities | Registration/type, operator, route, ETA, flight summaries and tracks |

The provider sections below supply the sources and qualifications for this comparison.

## adsb.fi

The public API supports hex, callsign, registration, squawk, military filtering, and a geographic circle up to 250 nautical miles.
New integrations should use the `/v3/lat/.../lon/.../dist/...` circle endpoint because its v2 predecessor has a different response format and is deprecated.
Public endpoints allow one request per second for personal, non-commercial use and require attribution with a homepage link.
Feeding is encouraged but not required for public endpoints; the feeder-only global snapshot updates twice per minute and is authorised by feeder IP address.
Responses are documented as ADS-B Exchange v2 compatible. [Official open-data documentation](https://github.com/adsbfi/opendata/blob/main/README.md)

The network's receiver client also returns MLAT results into readsb, which can locate some Mode S aircraft that do not broadcast ADS-B positions.
This is an additional benefit of participating in its receiver network, subject to coverage and a suitable receiver setup. [Official feeder client](https://github.com/adsbfi/adsb-fi-scripts)

## adsb.lol

The public API currently offers free access and a circle search up to 250 nautical miles, with registration, callsign, type and military filters.
Its data documentation specifies ODbL licensing.
The API documentation warns that future access will require a key obtained by feeding, and asks production users to contact the operator. [API documentation](https://api.adsb.lol/docs)
Rate limits are dynamic rather than a fixed published allowance. [API repository](https://github.com/adsblol/api)

The published schema includes registration, aircraft type, database flags, MLAT/TIS-B provenance arrays, position age, emergency state, selected altitude, heading, airspeed, Mach and quality indicators when available.
Some fields are decoded surveillance information rather than external database enrichment. [Published schema](https://api.adsb.lol/api/openapi.json)
The documented routeset endpoint and repository describe plausible route enrichment; it should be presented as a lookup rather than a confirmed current flight plan. [API repository](https://github.com/adsblol/api)
Daily historical archives contain per-aircraft traces under ODbL. [Historical data](https://www.adsb.lol/docs/open-data/historical/)
Feeders can access a direct network-wide readsb API from their feeder IP address. [Feeder API](https://www.adsb.lol/docs/feeders-only/re-api/)

## OpenSky

OpenSky's live state API exposes callsign, squawk, altitude, speed, vertical rate, aircraft category and separate last-position and last-message timestamps.
Its position-source enumeration includes ADS-B, ASTERIX, MLAT and FLARM; an enumerated value does not establish current availability or coverage for that source.
The standard live response lacks aircraft registration, detailed type, operator and intended route.
Anonymous users receive 400 daily credits, standard accounts 4,000 and active feeders 8,000, with separate buckets for states, tracks and flights.
A small state query costs one credit and a global query four.
Authenticated access uses OAuth2 client credentials, with five-second state resolution versus ten seconds anonymously.
Flight records are batch updated overnight, and the track endpoint is experimental. [REST API documentation](https://openskynetwork.github.io/opensky-api/rest.html)

The service describes the API as intended for research and non-commercial use and explicitly excludes schedules and delays. [API introduction](https://openskynetwork.github.io/opensky-api/)

## ADS-B Exchange

The current Developer Hub advertises paid personal API access via RapidAPI, with location and identifier queries.
Its Community API link leads to that offering, so a free member account must not be confused with free API access.
Enterprise offerings add higher volume, historical and enriched datasets.
Current public documentation reviewed here does not establish a general free feeder API entitlement. [Developer Hub](https://www.adsbexchange.com/community/developer-hub/)

The v2 aircraft schema includes registration, type, database flags, observation age and extensive surveillance fields, with source information for ADS-B, MLAT and other message types.
Do not assume the aircraft endpoint supplies commercial schedules, routes or photographs merely because those appear in a provider's website. [Aircraft API documentation](https://www.adsbexchange.com/api/aircraft/v2/docs)

## Flightradar24

An API subscription is separate from Silver, Gold and Business website/app subscriptions.
Usage is charged by returned flight records rather than simply by request count, so repeatedly polling a busy region has a materially different cost from looking up a selected aircraft. [API FAQ](https://fr24api.flightradar24.com/docs/faq)

Full live positions add registration, aircraft type, origin, destination and callsign to movement data.
Other endpoints supply airport and airline details, historical positions and flight tracks. [Endpoint overview](https://fr24api.flightradar24.com/docs/endpoints/overview)
The published sample also includes position source, timestamp, operating airline, painted airline and ETA. [Official sample](https://fr24api.flightradar24.com/docs/sandbox-environment)
Flight summaries add takeoff/landing times, actual destination following diversion, runways, distance, duration and service category, with missing fields represented as null. [Flight summaries](https://fr24api.flightradar24.com/docs/endpoints/flight-summary)
Future scheduled departure times are currently excluded from the public API even when visible on the consumer website. [API FAQ](https://fr24api.flightradar24.com/docs/faq)
API data must be deleted within 30 days of receipt. [Storage rules](https://fr24api.flightradar24.com/docs/storage-rules)

## Independent enrichment: adsbdb

The public aircraft endpoint resolves a hex address or registration to aircraft type, manufacturer, registration, registered owner, owner country, operator flag code and optional photograph URLs.
The callsign endpoint returns airline information and origin/destination airports, occasionally with intermediate airports.
These lookups can embellish locally received contacts without replacing their local positions.
Registered owner is not necessarily the flight's current operator, and a callsign route lookup should not be treated as an authoritative current flight plan.
The repository credits PlaneBase for aircraft data and airport-data.com for photographs.
It explicitly restricts copying, publishing or incorporating its route data into other databases without the named rights holder's permission, so public API availability is not an unrestricted data licence. [Official repository and response schemas](https://github.com/mrjackwills/adsbdb)

## Other tracking technologies and services

A provider is not the same as a tracking technology: an online feed can combine several technologies, and multiple providers may repeat the same underlying observations.
MLAT estimates positions from message arrival-time differences at multiple receivers; a single receiver hearing Mode S messages without positions cannot perform that network calculation by itself.
The [readsb format](https://github.com/wiedehopf/readsb/blob/dev/README-json.md) distinguishes ADS-B, MLAT, ADS-C, TIS-B and other position sources.
Satellite-received ADS-B extends geographic coverage but remains ADS-B.

### Open Glider Network

[OGN](https://wiki.glidernet.org/) focuses on FLARM, OGN trackers and ADS-L devices, making it a strong candidate for adding gliders and other light aircraft.
Its [subscription documentation](https://wiki.glidernet.org/wiki:subscribe-to-ogn-data) describes a public APRS stream over TCP with geographic filtering, plus gateway alternatives.
The [protocol](https://wiki.glidernet.org/wiki:ogn-flavoured-aprs) carries position, altitude, course, speed, climb rate, turn rate, aircraft category, address type and reception information where available.
Its [device database and opt-in rules](https://wiki.glidernet.org/opt-in-opt-out) can associate permitted aircraft identities and registrations with devices.
Respect identification and tracking preferences, and preserve FLARM/OGN/ICAO address namespaces when matching contacts.
A FLARM address that resembles an ICAO hex address is not automatically the same identity.
Live stream availability, local coverage and applicable data reuse terms were not tested.

### SafeSky

[SafeSky's public API introduction](https://docs.safesky.app/books/safesky-public-api-for-traffic/page/1-introduction) describes aggregation of ADS-B, ADS-L, Mode S, FLARM, FANET, OGN Tracker, PilotAware, mobile-app positions and other integrations.
This is a candidate for broader lower-airspace coverage through one interface.
Its [beacon model](https://docs.safesky.app/books/safesky-public-api-for-traffic/page/7-model-definition) includes category, source technology, observation time, ground speed, climb and turn rates, accuracy and a callsign when public.
The model uses metres AMSL derived from GPS for altitude, which must not silently replace barometric altitude.
[API keys require contacting SafeSky](https://docs.safesky.app/books/safesky-public-api-for-traffic/page/2-authentication).
The linked [data policy](https://public-api.safesky.app/public/api-policy.html) requires a written agreement and discusses reciprocal data sharing.
Do not treat the phrase public API as confirmation of free, unrestricted hobby access.

### Airframes

[Airframes](https://docs.airframes.io/docs/using-airframes/) provides aircraft positions from ACARS reports, ADS-C surveillance and other location-bearing messages, including outside terrestrial ADS-B coverage.
Its [API overview](https://docs.airframes.io/api/) describes flights and position trails, aircraft and airline metadata, messages, departure/arrival operational events, routes and station information.
This could add both alternative positions and an optional view of aircraft communications.
The [authentication](https://docs.airframes.io/api/authentication/) and [pricing](https://docs.airframes.io/api/pricing/) pages are explicitly marked under development, with early access by contact, planned free feeder access and paid alternatives.
The overview also gives inconsistent statements about anonymous access versus mandatory keys.
Treat this as an exploratory candidate until access, licensing, observation timestamps and message-to-flight matching have been validated.
Sparse operational position reports should not be presented as a continuous high-frequency track.

### FlightAware

[FlightAware's source catalogue](https://www.flightaware.com/about/datasources/) includes ANSP radar and flight plans, terrestrial ADS-B and MLAT, ACARS datalink, airline flight information and Aireon space-based ADS-B.
[AeroAPI](https://www.flightaware.com/commercial/aeroapi/) provides query-based flight status, ETAs, current positions, tracks, filed routes and historical products, with availability varying by tier.
The Personal tier has limited included monthly usage, per-result-set billing and a limit of ten result sets per minute; historical products and satellite ADS-B are restricted to higher tiers.
[Firehose](https://www.flightaware.com/commercial/data) provides an enterprise streaming alternative.
For this project, targeted flight-detail lookups are a more plausible evaluation than continuously polling a busy map.

The published [AeroAPI Standard License](https://www.flightaware.com/commercial/aeroapi/AeroAPI_Standard_License.pdf), version November 2022, restricts combining its data with other real-time or near-real-time flight-data providers without written permission and limits raw-data retention to 30 days.
Confirm the applicable current agreement and permission for the proposed combined display before selecting it.
Do not assume a subscription alone authorizes enrichment of another provider's contacts.

## Useful enrichment already available near the receiver

The [readsb JSON documentation](https://github.com/wiedehopf/readsb/blob/dev/README-json.md) lists optional squawk, emergency status, vertical rate, indicated/true airspeed, Mach, roll, selected altitude, navigation modes and integrity/accuracy indicators.
It also documents calculated wind and temperature estimates.
Availability depends on received messages, aircraft equipment and decoder support, so these fields should remain optional and distinguish measured from derived values.
These are candidates to expose from local reception before adding a remote dependency.

The same decoder supports an aircraft database for registration, type, optional long type name and classification flags.
[tar1090-db](https://github.com/wiedehopf/tar1090-db) distributes a database maintained by Mictronics.
This suggests a cached metadata layer for local ADS-B contacts, subject to checking the dataset's current attribution and distribution terms.
Database classification flags, including military, should be presented as source-supplied metadata rather than authoritative observations.
Photos require separate image permissions and attribution even when a tracking service returns a photo URL.

## Proposed integration approach

These are recommendations, not changes to the accepted product specification.

- Keep fast position observations separate from slower aircraft identity and flight-detail lookups.
- Retain provider, tracking technology, position observation time and altitude reference for each observation.
- Prefer fresh local positions as specified, while allowing online metadata to embellish the same contact.
- Match ICAO-addressed observations cautiously and keep non-ICAO identifiers in separate namespaces.
- Resolve flight details using time and other context as well as callsign, because a callsign alone does not identify a unique flight occurrence.
- Preserve unknown fields and record whether origin/destination is reported, inferred or merely a callsign database association.
- Cache stable metadata where terms permit and fetch expensive flight detail on selection.
- Evaluate online update cadence against the current 15-second stale and 60-second removal defaults before adopting a source.

Start with a small local-area comparison of adsb.lol and adsb.fi, then assess OGN for additional traffic classes.
Add registration/type enrichment independently.
Evaluate route enrichment with representative current flights before choosing a provider.
SafeSky and Airframes are worthwhile follow-on investigations if their access arrangements fit the project.
No accounts, paid calls, receiver sharing or provider agreements were created by this research.

## Verification limits

This assessment verifies published capabilities, not live coverage, account eligibility, measured latency or paid responses.
No accounts, purchases or receiver-sharing arrangements were created.
Photograph redistribution rights and integration-specific commercial terms require checking before implementation.
