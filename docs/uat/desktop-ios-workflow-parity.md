# Desktop and iOS workflow acceptance

Date: 2026-09-26. Branch: `feat/desktop-ios-workflow-parity`.

## Safety and environment

No real generations, real model downloads, or user model deletion were run.
Desktop used a separate Debug process with `ZEPHRA_PREVIEW_STATE=generating` and
`ZEPHRA_FRESH_START=build/uat`. The installed `/Applications/Zephra.app` stayed
untouched. iOS used the iPhone 17 Pro simulator, iOS 26.5, frozen multi-host
fixtures. Fixture workflow requests change synthetic state only. Host integration
suites use encrypted in-process links, fake backends and disposable filesystem
storage; downloader suites use stubbed URL loading.

## Acceptance evidence

| Area | Evidence | Outcome |
| --- | --- | --- |
| Desktop prompt history | Queued two fixture prompts, one multiline; Up twice recalled oldest; Down twice restored unsent draft | Passed after fixing selection callbacks during replacement |
| Desktop queue | Context Move Earlier changed two queued batches' displayed order; frozen running row remained unchanged | Passed |
| Queue integrity and remote retries | Package tests cover seeds, chains, stale membership, pinned running/preparing work, encrypted reorder and replay | Passed |
| iOS Auto history | Opened History with two live Macs and one offline fixture; rows chronological and attributed; selection changed prompt while preserving size, steps and references | Passed |
| iOS manual history | Hosted encrypted multi-host tests select only destination; watched host does not change scope, disabled hosts excluded | Passed |
| Composer | Typed a 1120-character prompt; bounded full-width editor wraps and retains reference controls; Done finishes editing | Passed for long wrapped text |
| iOS model lifecycle | Download fixture showed progress; Pause showed Resume without opening Cancel; Resume restored progress; explicit Cancel confirmation returned Download Only | Passed after fixing Form button fan-out |
| Storage deletion | In-use row disabled; second fixture row confirmed named Mac and irreversible action; synthetic deletion removed only that row and updated total 6 GB to 2 GB | Passed |
| Real storage contract | Encrypted integration tests exercise measured disposable storage, in-use refusal, failure propagation, token invalidation and replay without deleting replacement directories | Passed |
| Viewer prompt | Long paragraph plus 300-character unbroken word: two-line title stayed bounded, Close accessible; full prompt sheet wrapped all text | Passed |
| Gallery density | Rendered Thumbnail Size menu changed grid from three columns to two with host badges intact | Passed |
| Pinch | Hosted tests exercise magnification direction, one/six-column clamps and invalid input; gesture is wired to same transform | Calculation passed; physical two-finger gesture unavailable in current automation tools |
| Today | Multi-host fixture shows real prompt/image runs, no duplicate success ledger list; hosted tests hide accepted/completed and retain old uncertain receipts | Passed |
| Legacy/offline compatibility | Golden encoding, optional capability, existing legacy loading and cached library suites | Passed |

## Automated gates

- macOS hosted: 383 tests in 73 suites passed.
- iOS hosted: 245 tests in 54 suites passed again after final Form button changes.
- ZephraKit full serial: 959 tests in 173 suites passed.
- ZephraLink final full serial: 296 tests in 55 suites passed, including synthetic lifecycle and lost-acknowledgment regressions.
- Debug macOS and iOS builds passed. Layer lint and diff whitespace checks passed.
- Relay: all 121 tests passed; prerequisites passed.
- Final shared sort regression: all 5 workflow tests passed.

## Remaining device acceptance

Physical pinch gesture, VoiceOver operation, maximum Dynamic Type and landscape
are not claimed as rendered acceptance by this simulator pass. Menu alternative,
accessibility actions, one-column accessibility layout and bounds are present.
Real inference/download throughput was deliberately excluded by user instruction.

## Independent implementation review

The implementation reviewer found lifecycle retries could overtake newer transfer
decisions, and mixed date/position queue comparison was non-transitive with
missing history. Transfer edits are now sent once and uncertain acknowledgments
ask the person to inspect status. Both apps use the shared total chronological
ordering, keeping unknown dates stable after known dates. Regression tests cover
lost replies and shuffled queues with missing history. Reviewer rechecked the
corrective diff and reported no remaining actionable findings.
