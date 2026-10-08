# View menu hover verification

Radar redraws previously refreshed the native Labels and Trails submenu rows, clearing their hover highlight and preventing reliable submenu access.
`RadarPresentationMenu` gives the menu its own SwiftUI invalidation boundary and captures its presentation values when its body updates.
Radar redraws no longer modify those rows, while presentation choices still apply through the current model settings.

## Automated checks

Run the normal suite with `swift test`.
Run the native regression independently with `PHOSPHOR_NATIVE_MENU_TEST=1 swift test --filter PresentationMenuTests`.
The native test uses an offscreen window at 800 and 1200 points wide, opens the actual View menu, changes the viewing radius while tracking, and checks that neither submenu rows nor item identities change.
The test requires a macOS desktop session and must run separately because native menu tracking runs a nested AppKit event loop that interferes with concurrent UI tests.
Avoid desktop interaction while it runs.

The original implementation produced six submenu-row changes and failed at both widths.
The extracted menu produced no submenu-row changes and passed at both widths.
The normal suite passed all 150 tests, the separate native regression passed both widths, and debug packaging and the release build succeeded.

## Native exercise

Build with `./scripts/build-app.sh`.
Start an isolated synthetic fixture with `build/Phosphor.app/Contents/MacOS/Phosphor --ui-fixture --map-offline`.
The fixture uses separate preferences and does not change the normal application's settings.

1. Open View and move the pointer over Labels, then Trails.
   Each row should retain its highlight and open its submenu while radar updates continue.
2. Choose Automatic labels and None for trails, then reopen the menu to confirm the checkmarks.
   Labels should visibly declutter, and trails should disappear.
3. Toggle Direction vectors and confirm the map responds.
4. Leave a submenu open beyond the 15-second bar-hiding interval.
   The top controls should remain visible and the submenu should remain usable.

The native candidate retained highlighted Labels and Trails submenus and applied Automatic labels successfully with 250 synthetic contacts.
