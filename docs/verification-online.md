# Online source verification

## Issue #15: Online mode

The existing 18 core tests passed before implementation.
The completed slice passes 24 tests across the core and application model, including deterministic online payloads, millisecond timestamps, missing optional values, request spacing and priority, queued cancellation, increasing retry delays, older preferences, obsolete responses, and contact ageing during a suspended poll.
The app source loop is independent of the display loop.
Native debug packaging and release compilation passed.

On 6 October 2026, the documented adsb.fi geographic endpoint returned HTTP 200 and 14 aircraft within 25 NM of the bundled example location.
The native app then displayed hundreds of real contacts at the default 250 NM search radius, with a selected contact reporting adsb.fi and a genuine position age.
Offscreen native previews were inspected for Immediate, Sweep, contact inspection, settings, and an unavailable-provider state at the minimum window size.
Preview preferences are isolated from saved user preferences.
Dense live traffic retains the existing label-overlap limitation; zooming reduces the clutter.
A new physical-receiver disconnection exercise was not performed for this slice.
Owned receiver process stop/restart is covered by the existing child-process fixture.

Build and start after quitting any running copy:

```sh
./scripts/build-app.sh
open 'build/ADSB Radar.app'
```

1. Open Settings, choose Online / adsb.fi, enter latitude 51.5 and longitude -2.5 for the example Home location, and save.
2. Confirm Online health becomes active and aircraft appear without a dongle.
3. Select a contact and inspect its source, position age, trail, and explicit unknown fields.
4. Switch between Immediate and Sweep, pan away from home, and use Return home.
5. Set a different refresh interval and search limit; relaunch and verify they persist.
6. Temporarily disconnect networking and confirm the failure status appears, the map remains responsive, and existing contacts become stale and disappear at the configured thresholds.
7. Restore networking and confirm automatic recovery; switch to Synthetic and confirm the real contacts and selection clear.
8. Switch back to Local and confirm the usual receiver status; quit and confirm the owned decoder stops.

Repeatable offscreen Online fixtures, requiring no internet or hardware:

```sh
swift build
"$(swift build --show-bin-path)/ADSB Radar" --render-online-preview /tmp/adsb-radar-online-preview
```

These renders exercise native views with fixtures and do not constitute an interactive network-outage or physical-receiver test.
