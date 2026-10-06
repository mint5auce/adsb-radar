# Aircraft view decluttering verification

Build the candidate with `./scripts/build-app.sh`.
Start it with `open 'build/ADSB Radar.app' --args --synthetic --scenario demo --demo-count 250`.
These launch arguments use generated traffic without replacing the saved source preference.

## Labels, trails, and direction vectors (#20)

1. Inspect the 250-aircraft overview at normal size and at the 800 by 560 minimum window size.
2. Open View and compare Automatic, All, and Selected only labels.
3. Select an aircraft and check that its callsign and altitude remain readable in every label mode.
4. Zoom in and verify that additional automatic labels appear without shrinking text.
5. Compare All, Selected, and None trails, and toggle direction vectors.
6. Wait for movement, restore All trails, and confirm history was retained while hidden.
7. Repeat with Immediate and Sweep updates, then relaunch to confirm saved presentation choices.

The original problem was reproduced in the native app with 250 Demo aircraft before implementation.

## Home distance (#21)

1. Save a Home location in Settings, then open Filters and choose 25, 50, and 100 NM or enter a positive custom distance and press Return.
2. Pan away from Home and confirm the eligibility criteria stay anchored to Home while In view and Outside view change.
3. Select an aircraft, tighten the distance until it falls outside the criterion, and check the Outside filters note and counts.
4. Deselect it and confirm its marker and hit target disappear.
5. Enter zero, a negative value, or invalid text and confirm the inline explanation leaves the last valid filter active.
6. Wait while contacts are hidden, clear filters, and confirm their updated positions and retained trails reappear.
7. Change distance units and relaunch to verify the criterion retains its physical distance.
8. With Home unset, confirm distance controls explain their unavailability.

Home-distance model checks passed with retained contacts, selected exceptions, offscreen counts, and clearing without observation changes.
