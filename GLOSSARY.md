# Aircraft Radar

Vocabulary for displaying live aircraft information in the style of a vintage air-force radar screen.

## Language

**Radar display**:
The geographic presentation of live aircraft information in the style of a vintage military tactical display.

**Application icon**:
The visual mark identifying ADSB Radar in macOS application surfaces such as Finder and the Dock.

**Aircraft data source**:
An origin of live aircraft information supplied to the radar display.
_Avoid_: Radar, when referring to the source of the information rather than its presentation.

**Aircraft contact**:
A representation of one aircraft on the radar display, which may be informed by more than one aircraft data source.

**Local reception**:
Aircraft information received through the user's own radio receiver.

**Online feed**:
Aircraft information supplied by an online service to extend the view beyond local reception.

**Receiver location**:
The geographic location of the user's radio receiver, used as the home position of the radar display and the origin of its simulated sweep.

**Stale contact**:
An aircraft contact whose last position is too old to count as current, retained briefly at that position before removal.

**Position age**:
The elapsed time since a source's last position observation for an aircraft, distinct from the time since any message was received or the display last refreshed.

**Immediate update mode**:
A display mode in which aircraft contacts update as new information arrives, independently of the decorative radar sweep.

**Sweep-timed update mode**:
A display mode in which aircraft contacts update when the simulated radar sweep, anchored to the receiver location, reaches them.

**Synthetic aircraft data**:
Generated aircraft observations used to explore the radar display without receiving real-world aircraft traffic.

**Test scenario**:
A repeatable sequence of synthetic aircraft observations containing movement, missing information, and changes in position freshness.

**Demo scenario**:
A synthetic traffic picture with many aircraft, complete flight details, and fresh positions, used to demonstrate the radar display.
