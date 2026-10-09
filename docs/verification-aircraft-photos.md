# Aircraft photo verification

Implemented on 9 October 2026 against baseline `6fa92fad5f9ad8d6fc0d8f470bc52e2f255425ef`.
The accepted requirements are in the Aircraft photographs section of `docs/product-spec.md`.
The offline native fixture and manual acceptance steps are in `docs/usage.md` under Aircraft photographs.

## Automated checks

`./scripts/build-app.sh debug` passed.
All eight added photo tests passed, covering provider validation/fallback, metadata expiry, stale results, image lifetime, disclosure state, and settings migration/persistence.
`git diff --check` passed.

The final `swift test` run passed all 99 RadarCore tests and 61 of 62 Phosphor tests.
The failing test was `IdentityPersistenceModelTests.expiredCacheSurvivesOfflineFailureWithoutQueryingUnseenEntries`, at its provider-request assertion.
A separate clean worktree at the unchanged baseline reproduced that exact failure.
An earlier full run also hit timeouts in three existing receiver-retry tests; all three passed in an isolated rerun and the final full run.
No unrelated retry or identity-cache code was changed.

## Standards

The independent standards review found no documented AGENTS.md, glossary, or ADR violations and no material baseline code smells.
It separately identified the same metadata-expiry correctness issue as the spec review.

## Spec

The independent spec review found one issue: selected metadata could survive beyond the provider's 24-hour allowance.
A timed expiry now clears the retained image and metadata, refreshes the lookup, and preserves the user's disclosure choice.
A regression test verifies expiry and disclosure preservation.
Re-review found no remaining actionable spec mismatch or material scope creep.

Final review totals: no unresolved standards findings and no unresolved spec findings; the single expiry issue was fixed.

## Native verification and remaining checks

Verified green/full-colour rendering, keyboard focus revealing colour, loading/unavailable/disabled disclosures, collapse/reopen behaviour, and the immediate colour setting surviving Cancel.
The native fixture uses generated illustrative artwork rather than stored provider photographs.
Window occlusion and app hiding participate in visibility tracking, while deterministic state tests verify image release and rejection of late bytes.
Physical pointer-hover timing, Reduce Motion, exact minimum-window layout, live image-page navigation, and hidden-window memory release remain manual checks documented in `docs/usage.md`.
The available native automation did not reliably support hover or exact window sizing.
