# Reception retry verification

Build and start the candidate from the repository root:

```sh
./scripts/build-app.sh release
open 'build/ADSB Radar.app'
```

1. Leave the receiver disconnected and choose Local or Local + Online in Settings.
2. Wait for the missing-receiver error, then leave View open through several automatic retries.
3. Move the pointer between Labels and Trails, choose a label mode, and toggle direction vectors.
4. Open Filters, change Hide ground aircraft, and edit an altitude limit while reception retries.
5. Check that the map frame stays fixed, menus remain usable, and pointer and text-entry focus remain under your control.
6. Repeat at the minimum window size and use Retry explicitly.
7. Connect the receiver and check that successful reception replaces the error.

The native layout regression covers Local and Local + Online at 800- and 1200-point window widths.
The model regression covers automatic retries retaining an error during Starting, explicit retries, and recovery.
The packaged app was checked with a missing receiver, an open View menu, and changes to direction vectors and the ground filter.
Physical receiver recovery and sustained pointer-hover/text-entry focus need manual confirmation; the native automation used here does not reliably exercise keyboard focus in a popover.
