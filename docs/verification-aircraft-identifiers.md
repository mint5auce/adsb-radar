# Aircraft identifier verification

The identifier preference applies to map labels, inspector headings, Contacts, and aircraft choosers.
Registration is the default for new and existing preferences without an explicit choice.
Each preference falls back to the other identifier, then the uppercase aircraft address.
Blank values count as unavailable, and secondary identifiers omit duplicates.
The inspector retains labelled REGISTRATION and CALLSIGN fields, including UNKNOWN for missing values.

## Automated checks

```sh
swift test --filter AircraftIdentifierTests
swift test --filter AircraftIdentifierModelTests
swift build
swift test
```

Resolver tests cover both preference orders, missing and blank values, duplicate identifiers, and uppercase address fallback.
Settings checks cover first-launch defaults, older preferences, and Codable round trips for both choices.
Model checks cover registration arriving after a contact, open-chooser refresh, chooser titles and secondary identifiers, preference persistence, and unchanged contact selection and position.

## Native previews

```sh
swift build
"$(swift build --show-bin-path)/Phosphor" --render-local-enrichment-preview /tmp/phosphor-identifier-preview --preview-identities --preview-identifiers
```

This uses deterministic fixture reception and enrichment without requiring a receiver or live aircraft traffic.
It produces registration and callsign variants of the inspector, Contacts, chooser, and minimum-window views.

## Manual exercise

```sh
./scripts/build-app.sh
open build/Phosphor.app --args --synthetic --scenario demo --demo-count 25
```

1. Open Settings and scroll to Presentation.
2. Confirm Aircraft identifier initially shows Registration when no explicit preference has been saved.
3. Choose Callsign, then Cancel, and reopen Settings to confirm the draft was discarded.
4. Choose Callsign and click Save settings, then quit and relaunch to confirm persistence.
5. In Synthetic mode, confirm both preferences display callsigns because registration is unavailable, and the inspector shows REGISTRATION as UNKNOWN.
6. With Local or Online traffic and available identity data, choose Registration and save.
7. Compare the same aircraft's map label, inspector heading, Contacts heading, and overlapping-aircraft chooser heading.
8. Confirm the alternative identifier and address remain visible without duplicates, and both labelled inspector fields remain available.
9. Switch to Callsign and save, checking the same surfaces and retained selection.
10. Watch a newly received aircraft without registration gain identity details and confirm the Registration heading updates automatically.
11. Check the inspector and Contacts at the minimum window size, scrolling for remaining details.

Live receiver and provider checks require suitable hardware or traffic and are not covered by deterministic fixtures.

## Verification result, 7 October 2026

The debug build, focused identifier tests, and full suite passed: 85 RadarCore tests and 40 Phosphor tests.
Native fixture previews were inspected for both identifier preferences, Contacts, the chooser, and normal and minimum-size inspector layouts.
The standards review found no violations; the specification review found an open-chooser refresh gap that was fixed and passed re-review.
Interactive Settings Save/Cancel and live receiver/provider exercises were not performed; use the manual steps above for those checks.
