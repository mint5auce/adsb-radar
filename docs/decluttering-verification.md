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
