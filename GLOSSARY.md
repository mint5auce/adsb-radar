# Aircraft Radar

Vocabulary for displaying live aircraft information in the style of a vintage air-force radar screen.

## Language

**Radar display**:
The geographic presentation of live aircraft information in the style of a vintage military tactical display.

**Airway**:
A published air traffic route through a defined corridor of controlled airspace.
_Avoid_: Airline route, which describes a connection between airports.

**ATS route**:
A published route used to channel aircraft traffic for the provision of air traffic services.
Airways are one kind of ATS route.

**Airway corridor**:
The airspace occupied by an airway, bounded laterally and by a floor and ceiling.

**Controlled-airspace region**:
A published volume of controlled airspace with lateral and vertical limits, such as a control area, control zone, or terminal control area.
Its boundary is distinct from the routes that pass through it.

**Flight-level slice**:
A horizontal view of airspace at a chosen standard-pressure level.

**Airway segment**:
A portion of an airway between successive significant points, with its own applicable limits and restrictions.

**Waypoint**:
A specified geographic location used to define an air traffic route.

**Application icon**:
The visual mark identifying Phosphor in macOS application surfaces such as Finder and the Dock.

**Aircraft data source**:
An origin of live aircraft information supplied to the radar display.
_Avoid_: Radar, when referring to the source of the information rather than its presentation.

**Aircraft contact**:
A representation of one aircraft on the radar display, which may be informed by more than one aircraft data source.

**Local reception**:
Aircraft information received through the user's own radio receiver.

**Online feed**:
Aircraft information supplied by an online service, either on its own or alongside local reception.

**Source mode**:
The choice of aircraft data sources supplying live positions to the radar display, independently of optional identity enrichment.

**Identity enrichment**:
Registration, model, owner/operator, and reported-category information associated with an aircraft contact, independently of its position and movement.

**Receiver location**:
The geographic location of the user's radio receiver, which is also the home location when using local reception.

**Home location**:
The geographic origin of the radar display's simulated sweep and range rings, independent of the currently viewed map area.

**Online search area**:
The geographic area requested from an online feed, distinct from the area where that provider can actually receive aircraft.

**Stale contact**:
An aircraft contact whose last position is too old to count as current, retained briefly at that position before removal.

**Position age**:
The elapsed time since a source's last position observation for an aircraft, distinct from the time since any message was received or the display last refreshed.

**Immediate update mode**:
A display mode in which aircraft contacts update as new information arrives, independently of the decorative radar sweep.

**Sweep-timed update mode**:
A display mode in which aircraft contacts update when the simulated radar sweep, anchored to the home location, reaches them.

**Synthetic aircraft data**:
Generated aircraft observations used to explore the radar display without receiving real-world aircraft traffic.

**Test scenario**:
A repeatable sequence of synthetic aircraft observations containing movement, missing information, and changes in position freshness.

**Demo scenario**:
A synthetic traffic picture with many aircraft, complete flight details, and fresh positions, used to demonstrate the radar display.

**Label decluttering**:
A reduction in overlapping aircraft-contact labels while retaining the aircraft contacts themselves.

**Aircraft view filter**:
A criterion determining which aircraft contacts are shown, independently of their reception and lifecycle.

**Aircraft category**:
A reported classification of an aircraft's size or characteristics, distinct from its model and commercial or private use.

**Aircraft model**:
The aircraft design identified by a type code, such as A320, independently of the purpose of a particular flight.

**Home distance**:
The distance between an aircraft contact and saved Home, independently of the map centre.

**Selected-aircraft exception**:
A selected aircraft that remains eligible for display despite failing active aircraft view filters.
