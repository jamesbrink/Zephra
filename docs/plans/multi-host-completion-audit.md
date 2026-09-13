# Multi-host completion audit

Status: **implementation and local qualification complete**, 2026-09-13.
PR #47 delivered the core; PR #48 delivers the audited corrections and evidence.
The final PR must pass exact-head CI before merge. Results and field boundaries
are recorded in [multi-host-validation.md](multi-host-validation.md).

## Corrections and live evidence

- [x] Real TCP sockets, 1/2/4/8 isolated mock-backed hosts, two phone identities
  per host: pairing, simultaneous generation, request deduplication after
  reconnect, host-owned edits, duplicate filenames, simultaneous 1 MiB file
  downloads, and host A stopping while other hosts remain usable.
- [x] The same topology through the deployed relay, forced to bypass LAN.
  Initial runs exposed delayed frames incorrectly classified as lost by the
  500 ms window. Relay connections now use a bounded two-second window.
  The final passing matrix took 5.442 / 11.698 / 22.439 / 43.947 seconds for
  1 / 2 / 4 / 8 hosts. No physical iPhone or distinct physical Mac was used:
  these are real transport sessions with independent identities and mock engines.
- [x] Capability negotiation requires a snapshot from the current session;
  cached state cannot authorize new commands after reconnect.
- [x] Transfers prioritize references, opened media and visible thumbnails,
  with FIFO ties and an eight-grant aging bound. Uploads share admission limits.
- [x] Published chain duration includes all passes, tail processing and joining.
  A three-pass timing regression test passed.
- [x] Final source peer review and integrated local gates; exact-head CI remains the merge prerequisite recorded on PR #48.

## Acceptance evidence and implementation

- [x] Passive estimates: model revision, residency, reference/audio modes,
  preparation/finalization stages, remaining running work, input-transfer cost,
  bounded profiles and truthful confidence. Incomparable legacy timings are excluded.
  Profiles are process-local, unknown revisions cannot cross loads, and actual
  model unload costs are included. Peer-review edge cases were addressed.
- [x] Identity/cache migration crash and readback-boundary fault tests. A durable
  pending marker now repairs interrupted or mismatched collection migration from
  the retained legacy record; cache quarantine resumes after a partial move.
- [x] Concurrent lifecycle through HostConnections: disable, revoke, forget and
  re-pair A while B accepts commands; background/foreground preserves independent
  sessions and keeps disabled hosts disconnected.
- [x] Cancellation during a pairing attempt or reconnect in progress.
- [x] Disk-backed combined library cold reopen, duplicate-name media isolation,
  owner partitioning, offline edit refusal and scoped cache deletion.
- [x] Modern revisioned paging restarts on insert/delete/same-count replacement
  and retains a delta immediately after the final page.
- [x] Aggregate edits over encrypted test sessions reach only the owning host;
  a newer server edit survives rollback; late media cannot recreate a forgotten
  host cache while another host remains usable.
- [x] Disconnect/reconnect during a modern listing.
- [x] Host-qualified reference adoption with duplicate filenames and an offline
  source, cached/uncached media, and stale selection cancellation. Generate is
  blocked during resolution and on failure, with an explicit clear action.
- [x] Full adopted-reference upload to another live host and reconnect re-upload.
- [x] Receipt write/enqueue crash-window fault injection before and after prepared
  and accepted writes, same-session retry and restarted-host replay.
- [x] Delayed-snapshot repeated presses, reference re-upload and terminal receipt
  write failure with reconciliation.
- [x] Continuous old-client publication against a new host.
- [x] UI matrix with semantic VoiceOver labels and accessible action activation, plus
  largest accessibility sizes on composer, library, Today and host details.
  Spoken VoiceOver audio was not exercised.
- [x] Measured cached metadata readiness (not first rendered frame), large-library scrolling, aggregate in-flight
  memory, reconnect storms and watched-preview latency during downloads.
- [x] Portable final evidence tied to implementation revision `e2dee21` and PR #48.

Explicit rejection *permits* reranking in the plan; it does not authorize
rerouting unknown or accepted work. Any automatic retry must preserve that rule.
The separate deferred scope (automatic acquisition, batch splitting, accepted-job
migration, replication and unattended background dispatch) remains deferred.
An IPv6-only path is required only when available; a dual-stack DNS/API check is
not evidence of an IPv6-only carrier session.

## Reproduce live qualification

Ordinary `swift test` skips live tests. These opt-in commands create temporary
keys, files and relay rooms, then close their sessions; no existing pairing is read.

```sh
ZEPHRA_LIVE_UAT=tcp swift test --package-path Packages/ZephraKit --filter LiveMultiHostTests
ZEPHRA_LIVE_UAT=relay swift test --package-path Packages/ZephraKit --filter LiveMultiHostTests
```

`ZEPHRA_UAT_HOSTS=1|2|4|8` narrows a diagnostic run. `ZEPHRA_UAT_LOG_PATH` writes
stage progress. `ZEPHRA_LIVE_PERFORMANCE=relay` with filter
`LiveMultiHostPerformanceTests` runs bulk/preview/reconnect measurements.

## Final qualification

Engine 785, Link 274, iOS 192, hosted Mac 234, MLX 511 and relay 121 tests passed.
The final TCP and forced-relay 1/2/4/8-host matrices passed. The report retains one
preceding API Gateway disconnection rather than hiding it behind successful reruns.
The independent reviewer cleared the final source; the exact-head Gates check is
required on PR #48 before merge. Portable evidence is under
[evidence/multi-host](evidence/multi-host/README.md).
