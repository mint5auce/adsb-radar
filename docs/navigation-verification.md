# Navigation input isolation

The accepted interaction is that zoom and return-home/receiver controls perform their navigation action without selecting an aircraft beneath them or clearing the current aircraft selection.
The entire navigation panel owns its input, including button padding and the space between symbols.
Primary clicks, secondary clicks, and drags starting inside this panel must not reach the map's object-selection or pan handlers.
Ordinary map selection, the object chooser, and panning remain available immediately outside the panel.

## Reproduction and verification

On 6 October 2026, the original bug was reproduced in the native app by panning an aircraft beneath the minus button.
Clicking minus changed the radius from 80 to 100 NM and opened the aircraft inspector.
A native event regression also reproduced zoom unexpectedly clearing an existing selection, then passed after the fix.

The map's simultaneous tap gesture was handling the navigation button's click as a map click.
The fix measures the navigation panel in map coordinates and excludes its bounds from primary selection, secondary selection, and drag initiation.
Each button's full rectangular label is clickable, including its padding.
No new domain term or architectural decision record is needed for this local interaction correction.

`RadarInteractionTests` delivers AppKit mouse events through the real hosted SwiftUI surface in an offscreen window.
Its five tests cover eleven cases: all three navigation controls with two bottom insets, contacts beneath each zoom button, button padding, normal map selection/deselection/panning, and drags starting on navigation.
The focused checks and full suite passed using a separate build directory while other control-visibility work was underway:

```sh
swift test --scratch-path /tmp/adsb-radar-navigation-build --filter RadarInteractionTests
swift test --scratch-path /tmp/adsb-radar-navigation-build
```

A separate native candidate with the stationary synthetic fixture verified zoom over an aircraft, preserved aircraft inspection during zoom and return-home, selection immediately above the panel, and secondary-click isolation.
Secondary clicks on the unobscured map still opened the object chooser.
The existing live app was left running; the verification candidate was closed after testing.
Pinch gestures and physical receiver operation were not retested for this input-routing change.

## Repeat the native check

From the repository root, quit the app copy being replaced, then build and launch the stationary fixture:

```sh
./scripts/build-app.sh
open 'build/ADSB Radar.app' --args --ui-fixture
```

The debug fixture uses separate verification preferences and stationary synthetic aircraft with refreshed timestamps.

1. Zoom in until individual aircraft are easy to distinguish, then pan an aircraft beneath the navigation panel.
2. Click plus and minus, repositioning the map between checks if necessary.
   Confirm that zoom changes without opening an inspector or object chooser.
3. Select an aircraft on the unobscured map, then use both zoom buttons and return-home/receiver.
   Confirm that the same aircraft remains selected.
4. Click the padding between navigation symbols and drag from inside the panel onto the map.
   Confirm that padding only activates its navigation button and that the drag does not pan the map.
5. Secondary-click over an aircraft hidden by the panel, then secondary-click an unobscured aircraft.
   Only the unobscured map click should open the object chooser.
6. Select an aircraft immediately outside the panel and pan from unobscured map space.
   Confirm that both interactions still work, including after resizing the window or showing and hiding the footer.
