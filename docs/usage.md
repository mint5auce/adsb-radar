# ADSB Radar usage guide

A personal native macOS aircraft viewer with a vintage military tactical display inspired by [Air Defender](https://airdefendergame.com/).
The app displays local RTL-SDR reception, adsb.fi online traffic, or generated offline traffic over bundled geography, with aircraft inspection, pan, zoom, trails, and receiver-anchored sweep presentation.

The [accepted specification](product-spec.md), [glossary](../GLOSSARY.md), and [SwiftUI decision](adr/0001-native-swiftui-for-macos.md) describe the product.
A separate Linux interface is future work.

## Build and start

Requirements: macOS 14 or later, Swift 6 developer tools, and an RTL-SDR dongle with a suitable antenna for live reception.
The initial hardware is a generic RTL-SDR; the receiver integration also supports compatible V4 installations.
For local reception, install the receiver software once using Homebrew:

```sh
brew install readsb
```

Build the native application and open it:

```sh
./scripts/build-app.sh
open 'build/ADSB Radar.app'
```

A release build is available with `./scripts/build-app.sh release`.
Both builds include the native application icon, generated locally from the [tracked master artwork](../assets/app-icon/README.md).
The application uses the installed decoder rather than bundling it.
It looks in the standard Homebrew locations and the process PATH; set `READSB_PATH` to an executable path when launching from Terminal to use another installation.

Enter the receiver's latitude and longitude in Settings and save them.
Those coordinates and other settings stay in local macOS preferences, outside the repository.
When Local or Local + Online is selected, the receiver starts when the app opens.
Its app-owned process stops when switching to Online or Synthetic, closing the last window, or quitting.
Close other applications using the dongle before retrying reception.

## Airway and airport maps

The map includes offline UK ATS route centrelines, published controlled-airspace boundaries, and OurAirports airport markers.
Use the independent Routes, Airspace and Airports switches; choose All levels or a flight-level slice to explore the network.
Click a feature for its details, or secondary-click to choose among aircraft and map features under the pointer.
The map-data info button shows sources, dates and a manual update action.
See [data provenance, refresh commands and verification steps](airway-verification.md).

## Check the application icon

Quit any running copy of ADSB Radar, then build and launch the candidate:

```sh
./scripts/build-app.sh
open 'build/ADSB Radar.app'
```

In Finder, navigate to the repository's `build` directory and inspect ADSB Radar in icon view or Get Info.
Check that Finder and the running Dock show the dark tile with the green aircraft and three fading trail dashes, with transparent rounded corners and no white square.
Repeat using `./scripts/build-app.sh release` after quitting the debug copy.
Both configurations replace the same app bundle.
If cached artwork persists, quit the app, close the Finder preview or build-directory window, reopen that directory, and double-click the rebuilt ADSB Radar app in Finder.
Avoid broad system icon-cache resets.

## Online aircraft

Choose Online / adsb.fi in Settings and enter a Home location if none is saved.
Online mode needs internet access but no receiver or decoder installation.
The saved location anchors the sweep and range rings, and the location control returns home.
Configure the refresh interval and search-radius limit in Settings; defaults are five seconds and 250 nautical miles.
The search follows the visible map after panning settles, using one circle capped by the configured radius.
When the map extends beyond it, a dashed amber boundary and search-limit notice show the requested area.
This boundary does not guarantee reception coverage, and contacts leaving the search remain until normal ageing removes them.
The radius cannot exceed 250 nautical miles and all requests share adsb.fi's one-request-per-second allowance.
Failed requests retry with increasing delays while contacts continue to age using their original position times.
Choose Local + Online to combine both sources in one view with separate health indicators.
Fresh local positions take precedence; when they become stale, fresh online positions take over automatically.
Local reception resumes precedence when fresh observations return, without duplicating matching ICAO aircraft.

Enrich aircraft details online is enabled by default, including in Local mode.
It adds optional registration and aircraft type to the inspector using visible aircraft and selected-contact lookups.
Disable it in Settings to stop dedicated identity requests; ordinary Online responses can still supply details.
Known identities survive relaunches in a local Application Support cache, including while offline or enrichment is disabled.
Set the identity refresh age separately in Settings; the default is seven days and fractional days are supported.
Only encountered visible or selected aircraft trigger dedicated refreshes, and their details show the provider and successful update date.
Missing details and network failures leave known values, their previous update dates, and aircraft movement intact.
Synthetic does not request or display real identity data.

Aircraft data is supplied by [adsb.fi](https://adsb.fi), using its [public personal-use API](https://github.com/adsbfi/opendata).
No account, payment, or receiver sharing is enabled.
For implementation checks and exact manual steps, see [online verification](verification-online.md).

## Offline Test and Demo scenarios

Synthetic traffic works without a dongle, `readsb`, or an internet connection.
Choose Synthetic in Settings, then choose Test or Demo and save.
The source and scenario are remembered between launches; the first launch defaults to Local.
Generated traffic is labelled SYNTHETIC in the header, status, and contact details.
Local reception failures never enable Synthetic automatically.

You can also launch either scenario from Terminal after building and quitting any running copy:

```sh
./scripts/build-app.sh
'build/ADSB Radar.app/Contents/MacOS/ADSB Radar' --synthetic --scenario test
```

For a clean Demo picture with 100 aircraft:

```sh
'build/ADSB Radar.app/Contents/MacOS/ADSB Radar' --synthetic --scenario demo
```

Use `--demo-count 25` or `--demo-count 250` to change the Demo density, or use the count control in Settings.
The supported range is 25 to 250 aircraft, with a default of 100.
`--synthetic` alone uses the remembered scenario, defaulting to Test if none is saved.
Launch options change only that session's source choices, including when you save other settings during that session.

Traffic uses the saved receiver position, or a bundled example at latitude 51.5 and longitude -2.5 if no receiver position is saved.
The example is not saved as your receiver location.
Switching between real-data modes retains contacts, trails, and selection supported by sources that remain enabled.
Contacts supported only by a disabled source are removed.
Entering or leaving Synthetic clears contacts, trails, and selection while retaining location and display settings.
Restart clears the synthetic picture and repeats its routes and event sequence with current observation timestamps.

Test has eleven positioned aircraft and one heard without a position.
F0000B has unknown optional flight information.
TEST001 moves for two sweep revolutions or eight seconds, whichever is longer, then continues sending messages with its position frozen.
It turns amber after the configured stale threshold, disappears at the removal threshold, and recovers after another two sweep revolutions or five seconds, whichever is longer.
The cycle repeats; with default settings it becomes stale at 23 seconds, disappears at 68 seconds, and starts recovery at 76 seconds after Restart.
Sweep mode may display recovery on the following beam crossing.
Changing synthetic timing settings restarts the sequence to use the new thresholds.
Demo keeps all aircraft moving with complete flight information and fresh positions.

## Use the radar

Drag the map to pan and pinch or use the plus and minus controls to zoom.
The sweep and range rings remain anchored to the saved receiver location.
Use the location control or Command-0 to return to the receiver.

Click an aircraft symbol to inspect it, or select it from the Contacts menu.
The panel shows available flight information, its source, the displayed position, and the age of its latest source position.
Unknown values remain explicit, and aircraft heard without positions are counted in reception status.

Choose Sweep or Immediate from the presentation menu.
Sweep mode updates contacts as the beam reaches them; immediate mode updates them as observations arrive.
Position ageing continues independently of either mode, so stale aircraft fade and disappear even when reception stops.

Settings controls the saved receiver location, update mode, revolution time, initial range, trail duration, freshness thresholds, and altitude, speed, and distance units.
The defaults are a four-second sweep, 100-nautical-mile radius, two-minute trails, feet and knots, and stale/removal thresholds of 15/60 seconds since the last position observation.

## Verification

Run the focused core checks or the whole suite:

```sh
swift test --filter DecodingTests
swift test --filter ReceiverTests
swift test --filter SessionTests
swift test --filter GeometryTests
swift test --filter SyntheticSourceTests
swift test --filter PreferencesTests
swift test
```

The core checks exercise decoded observations, missing fields, a real child-process receiver fixture, freshness and removal thresholds, history retention, sweep crossings, coordinate transforms, and known unit conversions.
The receiver fixture does not require a dongle or network access.

For offscreen native layout inspection, build the debug executable and render synthetic contacts without opening or controlling a desktop window:

```sh
swift build
"$(swift build --show-bin-path)/ADSB Radar" --render-preview /tmp/adsb-radar-preview
```

This debug-only command produces map, contact-inspection, panned, minimum-window, and settings previews with synthetic data.
It is a layout check rather than an interactive UI or RF reception test.
The preview renders an offscreen native hosting view, including menus and the scrollable contact panel.
Add `--synthetic --scenario demo --demo-count 250` to that command to render the actual synthetic source and its example origin instead of the static layout fixture.

## Manual acceptance check

1. Build and start using the commands above, connect the dongle, and save the receiver location.
2. Confirm reception becomes active and actual aircraft appear; inspect a contact and verify unknown fields remain explicit.
3. Drag and zoom, including moving the receiver offscreen, and verify that geography, selection, trails, range rings, and the sweep remain aligned.
4. Return to the receiver and switch between both update modes; change sweep speed and units and confirm the display follows the settings.
5. Shorten stale and removal thresholds temporarily, then disconnect the dongle or otherwise stop incoming positions.
   Confirm contacts dim and disappear according to position age while the interface remains usable.
6. Reconnect and retry; confirm reception recovers without duplicate decoder processes.
7. Quit and confirm the app-owned decoder exits while any unrelated receiver process is left untouched.
8. Relaunch and verify settings persist, then run an offline session and confirm geography still appears without network access.

Actual reception depends on hardware availability, antenna placement, and radio coverage; an active receiver can legitimately have no positioned contacts yet.

## Manual offline acceptance check

1. Build with `./scripts/build-app.sh`, quit any running copy, disconnect the dongle, and launch Test using the exact command above.
2. Confirm the Synthetic indicator, bundled geography, eleven positioned contacts after a full sweep, and one contact without a position.
3. Select TEST001 and F0000B; check source attribution, increasing trails, and explicit unknown optional fields.
4. Observe TEST001 turn amber with stale text only in its sidebar, disappear, and recover at the times described above.
5. Click Restart and confirm selection and trails clear and the sequence begins again.
6. Try Immediate and Sweep, pan, zoom, return to origin, and change units; confirm the ordinary radar controls still work.
7. Quit and launch Demo with `--synthetic --scenario demo --demo-count 25`, then repeat with counts of 100 and 250.
   Inspect clean data, movement, layout, and responsiveness; zoom or pan to inspect crowded contacts.
8. Save a display preference during a flagged launch, quit, and reopen normally with `open 'build/ADSB Radar.app'`.
   Confirm the display preference persists while the flagged source/scenario/count choices were temporary.
9. Switch between Local and Synthetic in Settings; verify prior contacts and selection clear and the app-owned decoder stops in Synthetic.
   With the dongle disconnected, Local must show its existing failure and Retry control rather than generated traffic.
10. Save Synthetic in a normal launch and relaunch to verify that choice persists.
    If testing without a saved receiver location, check the example origin and confirm that the receiver fields remain unset in Settings.

## Offline geography

Coastlines and borders are bundled from [Natural Earth](https://www.naturalearthdata.com/), whose vector data is [public domain](https://www.naturalearthdata.com/about/terms-of-use/).
The app uses a receiver-centred azimuthal equidistant projection and draws locally without a tile service.
Regenerate the bundled data from the pinned Natural Earth release with:

```sh
python3 scripts/update-geography.py
```

The generated geography resource is maintained by that script.
