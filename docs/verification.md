# Implementation verification

Verification performed on 5 October 2026 with Apple Silicon macOS and Swift 6.4.
The implementation covers the approved local-reception scope of issues #1 through #7.
Online feed integration remains future work.

## Automated and layout checks

- Debug and release compilation passed.
- The full Swift Testing suite passed all ten tests across decoding, receiver lifecycle, session presentation, and geometry.
- Receiver fixtures exercise an actual child process, snapshot ingestion, stop, restart, and an actionable missing-dongle status.
- Session checks cover freshness while reception is silent, removal and recovery, repeated snapshots, trail retention, sweep crossings, and mode changes.
- Geometry checks cover panning, receiver anchoring, known unit conversions, and projected direction alignment away from the receiver.
- Offscreen native hosting-view renders were inspected at normal and minimum window sizes, with selected contacts, synthetic trails, a stale contact, panning, native menu labels, and settings.
- Bundled geography renders without a network map service.
- After the map-label tweak, the debug app rebuilt successfully and an inspected synthetic stale-contact preview retained amber callsign and altitude labels without stale text.

The preview also shows that a range-ring label can overlap an aircraft label.
That existing layout detail was left unchanged in this small presentation update.

The direction regression was reproduced with the former screen-axis heading calculation before the correction passed its focused test.
Desktop interaction could not be used for reproduction because Computer Use refused access to ADSB Radar as an unapproved app.
The projected geometry seam was the closest effective reproduction.

## Live reception and manual acceptance

macOS detected the generic Realtek RTL2838 dongle, and the app-owned `readsb` process opened its R820T tuner successfully.
Fresh aircraft snapshots arrived approximately once per second.
The first session contained a small number of decoded messages and one aircraft without a position.
Subsequent reception produced real positioned aircraft, including EZY38VV, displayed against the offline geography.
The earlier session without a connected dongle produced the expected decoder failure; the application now translates it into a clear connection-and-retry message.

Computer Use initially rejected app access without presenting an approval popup.
Access succeeded after the CLI permission mode changed to permit approval prompts.
The agent inspected the live window and selected aircraft details, switched update modes, opened settings, scrolled to unit controls, and saved the restored sweep mode.
Jonny reported that manual testing passed, requesting only removal of stale text from map labels while retaining amber plots and the sidebar's stale text.
The agent did not independently repeat the complete hardware-disconnection, quit, persistence, and live offline exercise.
Owned-process cleanup also passed the receiver fixture.

Build and run with the commands in [README.md](../README.md#build-and-start), then follow its [manual acceptance check](../README.md#manual-acceptance-check).
Quit the currently running app before reopening a rebuilt candidate.

## Standards review

No hard documented-standard violations or blocking receiver lifecycle defect were found.
Two optional design findings remain: position and observation time could become a single timestamped-position type when another source is added, and distance conversion factors and symbols could be grouped on `DistanceUnit`.
These are judgment calls rather than current-scope requirements.

## Spec review

The initial review found two issues: direction vectors needed the same geographic projection as contact positions, and integrated manual acceptance was incomplete.
The direction calculation was corrected and independently rechecked by the spec reviewer.
Manual testing subsequently passed according to Jonny, and Computer Use confirmed real positioned-aircraft display and the interactions recorded above.
No material scope creep was found.

Standards: zero hard violations and two optional findings.
Spec: the implementation defect was resolved, and the verification finding was addressed by subsequent live reception and Jonny's manual acceptance.
