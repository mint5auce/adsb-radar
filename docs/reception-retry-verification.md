# Reception retry verification

Build and start the candidate from the repository root:

```sh
./scripts/build-app.sh release
open 'build/ADSB Radar.app'
```

1. Leave the receiver disconnected and choose Local or Local + Online in Settings.
2. Wait for the three missing-dongle attempts to finish; confirm the orange text says Retry in Settings and there is no Retry button on the map.
3. Move the pointer between Labels and Trails, choose a label mode, and toggle direction vectors.
4. Open Filters, change Hide ground aircraft, and edit an altitude limit while reception is paused.
5. Check that the map frame stays fixed, menus remain usable, and pointer and text-entry focus remain under your control.
6. Open Settings and confirm Automatic attempts stopped and an enabled Retry Local receiver button.
7. Use Retry without saving settings, then wait for a fresh set of three attempts to stop again.
8. Check that Online reception continues throughout in Local + Online mode.
9. Repeat at the minimum window size and confirm Retry in Settings remains readable.
10. Change Missing receiver attempts in Settings, save, then use Retry to verify the chosen limit.
11. Connect the receiver and use Settings Retry to check that successful reception replaces the error.

The native layout regression covers missing-receiver pauses in Local and Local + Online at 800- and 1200-point window widths.
The model regressions cover three total attempts, a configured one-attempt limit, empty startup snapshots, paused polling, continuing Online reception, presentation edits during a pause, explicit retry, and recovery.
Preference tests cover the default, migration, persistence, and positive attempt limits.
The packaged app was checked with the dongle absent: it paused, Settings Retry started a fresh cycle, Online stayed active, and zero was rejected without saving preferences.
Physical receiver recovery and sustained pointer-hover/text-entry focus need manual confirmation; the native automation used here does not reliably exercise keyboard focus in a popover.
