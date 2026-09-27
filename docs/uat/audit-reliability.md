# Audit reliability validation

The repair is one `fix/audit-reliability` PR. No UAT inference, model download,
merge, or deployment was performed. Tests use mock backends, HTTP fixtures,
temporary stores, encrypted in-process roads, and existing tensor fixtures.

## Finding-to-fix evidence

| Finding | Repair | Regression coverage |
| --- | --- | --- |
| Stop/Clear Queue repeated after a lost acknowledgment | Single-shot unscoped commands, typed refusals, explicit uncertain outcomes; modern Stop captures a run ID | `LinkDestructiveRetryTests`, existing targeted-stop suites |
| Cache clear/host removal raced active consumers and writes | Catalog cancellation/drain transactions, storage tickets, host isolation, deferred leased deletion | `CacheTransactionTests`, `CacheLifetimeTests`, `CacheObservationLifetimeTests`, `MediaActionTests` |
| Photos/share failures disappeared or files lost their consumer | Shared observable action, surface-owned save state, operation-owned leases, busy/error/success feedback | `MediaActionTests`, frozen viewer checks below |
| Save availability became stale | Entry/version/connection/revision observation, shared file-store mutation stream | `FileStoreRevisionTests`, existing viewer identity tests |
| Thumbnail orphans persisted and stale fetches recreated them | Retained-digest pruning at startup and complete sync, rollback/offline retention, commit filtering | `ThumbnailReclamationTests`, `ThumbnailSyncReclamationTests` |
| Storage refresh cancellation published stale loading/results | Ticket-aware cleanup and cancellation checks | `StorageRefreshTests` |
| Equal-size retained mirror corruption was reused | Cancellable streaming SHA-256 validation, exact-file replacement before capacity credit | `ModelDownloaderTests.retainedMirrorIntegrity`, `corruptFinalNeedsAdmission`, `cancelledIntegrity`, `refusedReplacement` |
| Audit incorrectly claimed disk admission was absent | Preserve the existing volume coordinator and 256 MiB margin | `TransferReservationTests`, existing transfer-space/resume suites |
| Timing tests depended on machine speed | Explicit generation barrier and controlled deadline sleepers with request/reply synchronization | `StrictHostTests`, `OfferDeadlineTests`, `PreviewDeadlineTests` |

## Automated checks

Validated code commit: `38e64353` (rebased onto `14548f93`, including the existing
large-image and accessible-prompt repair). Independent implementation review
reported no actionable findings after the cache race fixes and rebase.

- `make doctor`, `make lint-layers`, `git diff --check`: passed.
- `make test`: 966 tests in 174 suites passed.
- `swift test --package-path Packages/ZephraLink`: 303 tests in 57 suites passed.
- `make relay-test`: 121 tests passed.
- `make test-ios`: 263 tests in 63 suites passed.
- `make test-app`: 383 tests in 73 suites passed.
- `make build-ios`: passed.
- `make build`: passed (universal Apple Silicon/Intel release).
- `make test-mlx`: all 11 packages passed, 616 tests across the serial Metal gates.

The affected kit and link suites passed five consecutive repetitions running
concurrently, repeated after the rebase. An additional stress run exposed a
manual-timer setup race in the offer tests: background library timers could
sample and terminate the injected stream. Timers now capture their sleeper
at creation, and offer tests synchronize completed library pulls and explicit
request/reply barriers. The affected link suites then passed five repetitions
under concurrent Metal compilation. A broader link run during Qwen compilation
hit paging/gap test deadlines; the complete 303-test suite passed after compilation finished. One initial hosted iOS run timed out in
an existing aggregate-library transport test; the complete rebased suite passed.
The initial thumbnail test used the legacy unscoped fingerprint format; its
host-scoped fixture was corrected and the new pruning/rollback suites passed.

## Frozen UI checks

The iPhone 17 Pro simulator used `ZEPHRA_PREVIEW_STATE=viewer` and the existing
numbered fixture PNG. Saving succeeded; revoking the simulator's add-only Photos
permission produced the actionable refusal; sharing opened the system sheet and
dismissed cleanly. Settings explained that files currently in use are removed
when viewing, sharing, or saving finishes. Deterministic media-action tests held
saving open, asserted busy state and duplicate suppression, and verified lease
release after completion. The macOS Debug app opened in frozen `ready` state
with an isolated fresh-start directory. No Generate control was pressed.

- [Photos success](audit-reliability/photos-saved.png)
- [Photos permission denial](audit-reliability/photos-denied.png)
- [Share sheet](audit-reliability/share.png)
- [Clear-cache explanation](audit-reliability/cache-message.png)
- [Frozen macOS ready state](audit-reliability/mac-ready.png)

The simulator device was shut down and the Simulator app closed after these
checks. The isolated macOS preview is also closed after validation.
