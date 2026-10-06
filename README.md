# Phosphor

A native macOS aircraft viewer with a vintage military radar display, inspired by [Air Defender](https://airdefendergame.com/).
Track aircraft from an RTL-SDR receiver, [adsb.fi](https://adsb.fi), or an offline synthetic demo.
Explore aircraft details, trails, and bundled UK airways, airspace, and airports.

![Phosphor showing aircraft over southern England](assets/demo/phosphor-preview.png)

[Watch the original 15-second demo: South UK to London](assets/demo/adsb-radar.mp4).
This historical recording shows the former ADSB Radar branding.

## Build and start

An easy-to-install package for non-developers is coming very soon.
For now, build from source using the instructions below.

Requires macOS 14+ and Swift 6 developer tools.

```sh
./scripts/build-app.sh
open 'build/Phosphor.app'
```

In Settings, save your home coordinates and choose a source:

- **Online**: live adsb.fi traffic with internet access; no receiver needed.
- **Local**: an RTL-SDR dongle, antenna, and `readsb` (`brew install readsb`).
- **Local + Online**: both sources in one view.
- **Synthetic**: offline Test or Demo traffic.

Drag to pan, pinch to zoom, and click an aircraft to inspect it.
Use Command-0 to return home.

## Try the offline demo

Quit any running copy, then launch:

```sh
'build/Phosphor.app/Contents/MacOS/Phosphor' --synthetic --scenario demo
```

## Development

Use `./scripts/build-app.sh release` for a release build in `build/release/Phosphor.app` and `swift test` to run the tests.
See the [usage guide](docs/usage.md) for settings, receiver setup, and manual checks, or the [product specification](docs/product-spec.md) for the accepted design.
Signed distribution builds, Sparkle updates, and the GitHub release workflow are covered in the [release guide](docs/releasing.md).
Phosphor uses a fresh application identity and does not migrate settings or caches from ADSB Radar.
Historical verification records retain the names and commands used at the time; use this README and the usage guide for current build commands.

Aircraft data: [adsb.fi](https://adsb.fi) ([personal-use API](https://github.com/adsbfi/opendata)).
Map data: [Natural Earth](https://www.naturalearthdata.com/) and [UK aviation / airport sources](docs/airway-verification.md).
