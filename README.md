# ADSB Radar

A personal native macOS aircraft viewer with a vintage military tactical display inspired by [Air Defender](https://airdefendergame.com/).
The app starts a local `readsb` decoder for an RTL-SDR dongle, draws aircraft over bundled offline geography, and supports aircraft inspection, pan, zoom, trails, and receiver-anchored sweep presentation.

The [accepted specification](docs/product-spec.md), [glossary](GLOSSARY.md), and [SwiftUI decision](docs/adr/0001-native-swiftui-for-macos.md) describe the product.
Online aircraft feeds and a separate Linux interface are future work.

## Build and start

Requirements: macOS 14 or later, Swift 6 developer tools, and an RTL-SDR dongle with a suitable antenna for live reception.
The initial hardware is a generic RTL-SDR; the receiver integration also supports compatible V4 installations.
Install the receiver software once using Homebrew:

```sh
brew install readsb
```

Build the native application and open it:

```sh
./scripts/build-app.sh
open 'build/ADSB Radar.app'
```

A release build is available with `./scripts/build-app.sh release`.
The application uses the installed decoder rather than bundling it.
It looks in the standard Homebrew locations and the process PATH; set `READSB_PATH` to an executable path when launching from Terminal to use another installation.

Enter the receiver's latitude and longitude in Settings and save them.
Those coordinates and other settings stay in local macOS preferences, outside the repository.
The receiver starts when the app opens and its app-owned process stops when the last window closes or the app quits.
Close other applications using the dongle before retrying reception.

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
swift test
```

The core checks exercise decoded observations, missing fields, a real child-process receiver fixture, freshness and removal thresholds, history retention, sweep crossings, coordinate transforms, and known unit conversions.
The receiver fixture does not require a dongle or network access.

For offscreen native layout inspection, build the debug executable and render synthetic contacts without opening or controlling a desktop window:

```sh
swift build
"$(swift build --show-bin-path)/ADSB Radar" --render-preview /tmp/adsb-radar-preview
```

This debug-only command produces map, contact-inspection, and panned previews with synthetic data.
It is a layout check rather than an interactive UI or RF reception test.
The preview renders an offscreen native hosting view, including menus and the scrollable contact panel.

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

## Offline geography

Coastlines and borders are bundled from [Natural Earth](https://www.naturalearthdata.com/), whose vector data is [public domain](https://www.naturalearthdata.com/about/terms-of-use/).
The app uses a receiver-centred azimuthal equidistant projection and draws locally without a tile service.
Regenerate the bundled data from the pinned Natural Earth release with:

```sh
python3 scripts/update-geography.py
```

The generated geography resource is maintained by that script.
