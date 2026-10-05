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
After that change, Jonny confirmed that stale-update manual testing and the manual acceptance checks for issue #1 were complete and all passed.
The agent did not independently repeat the complete hardware-disconnection, quit, persistence, and live offline exercise.
Owned-process cleanup also passed the receiver fixture.

Build and run with the commands in [README.md](../README.md#build-and-start), then follow its [manual acceptance check](../README.md#manual-acceptance-check).
Quit the currently running app before reopening a rebuilt candidate.

## Issue #8: synthetic offline scenarios

Debug and release compilation passed after adding the interactive synthetic source.
The full suite passed all 18 tests, including repeatable movement and restart, clean Demo data at 25/100/250 aircraft, generation around a configured origin, and Test freshness/removal/recovery through the normal session.
Preference checks cover the first-launch Local default, older saved settings, persistence, invalid launch options, and temporary CLI choices while saving display settings.

Native Computer Use checks exercised Test selection and synthetic attribution, an increasing position age, amber stale plots with sidebar text, contact removal, and clearing selection on Restart.
Demo reached 25, 100, and 250 positioned aircraft with no aircraft lacking positions.
Navigation controls responded at 250 aircraft, and normal relaunch retained the saved Demo choice.
Switching from Local to Synthetic stopped the app-owned decoder, confirmed by inspecting the process list.
Switching back to Local started one decoder, and quitting stopped it again.

A native `--synthetic --scenario test` launch overrode saved Demo choices.
Saving Immediate mode during that launch and reopening normally restored Demo with 25 aircraft while retaining Immediate mode, confirming that the scenario override remained temporary.
An invalid scenario exited with an actionable command-line error.
Offscreen renders of the actual Demo source confirmed 250 contacts, the bundled example origin, and unset receiver fields in Settings.
The synthetic header and Restart control also fit the minimum window size in an inspected offscreen render.

The first Demo routes clustered contacts excessively during visual inspection, so their starting positions were spread across the viewing area.
Contact labels still overlap in dense pictures, particularly at 250 aircraft; this is an existing renderer limitation and can be reduced by zooming or lowering the count.
The source performs no decoder, device, or network I/O, and no decoder process ran during synthetic checks.
The agent did not independently repeat a physical dongle-disconnection test or a session with networking disabled for issue #8.
Recovery is covered by the deterministic source/session check; the agent did not independently time a complete native recovery cycle.
Spec review reproduced a missing recovery display with a 30-second sweep and 3/6-second freshness thresholds through the actual source/session pipeline using a controlled clock.
The source's moving phase was extended to at least two sweep revolutions, and a failing regression check now passes through fresh, stale, removed, and recovered states with that configuration.
Independent rechecks found zero remaining findings on both the standards and spec axes.
The optional restart-transition duplication identified in standards review was consolidated into a shared helper.
Jonny subsequently confirmed that the manual acceptance tests passed.

Build, launch, and exercise both scenarios using the exact commands and steps in [README.md](../README.md#manual-offline-acceptance-check).

## Issue #9: native macOS application icon

The unchanged reference retains its recorded SHA-256, and the cleaned master is tracked in `assets/app-icon/master.png` with its imagegen prompt and local export instructions.
The cleaned artwork preserves the tile, upper-right aircraft, green glow, and three fading trail dashes.
Light and dark contact sheets were inspected at native sizes from 16 through 256 pixels, with a preview of the 1024-pixel representation.
The small trail remains subtle at 16 pixels, but the aircraft stays recognisable without a separate small-size redesign.
The exterior has transparent corners and no visible white surround or presentation shadow.

`./scripts/build-app.sh` and `./scripts/build-app.sh release` both passed.
Both generated and packaged the same icon SHA-256, `dcf275410129285f9c785f7d8bd6c4c3678d5c1cda54c58d39870cb3040e843d`, confirming repeatable exports with the installed macOS tooling.
`CFBundleIconFile` resolves to `Contents/Resources/AppIcon.icns`, and both bundles passed `codesign --verify --deep --strict`.
The packaged icon was decoded using `iconutil`; all ten standard and Retina representations have their expected dimensions from 16 through 1024 pixels and retain alpha.
The packaged minimum system version remains 14.0.
Shell syntax checks passed, debug and release compilation passed, and the complete existing suite passed all 18 tests.
No behavioural tests were added for this asset and packaging change.

Computer Use verified the new icon in Finder's Get Info header and large preview, with clean transparent corners and the preserved design.
The rebuilt debug and release apps launched successfully using the existing saved settings; local reception was active in the debug launch.
Direct Computer Use access to the Dock timed out, so the running Dock icon has not been independently visually verified.
The manual steps in [README.md](../README.md#check-the-application-icon) cover both configurations and a narrow relaunch procedure for cached artwork.
No system icon-cache resets or preference changes were made.
Independent review against baseline `610130a` found zero standards findings and no actionable spec defects or scope creep.
The spec review identified the unverified running Dock appearance as the one partial acceptance check.

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
