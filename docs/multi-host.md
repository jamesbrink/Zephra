# Multi-host iOS companion

The phone connects to up to eight enabled Macs and presents one library. Settings
lets each Mac be renamed locally, disabled, excluded from Auto, retried, re-paired
or forgotten. Disabling keeps its cached library. Forgetting removes only that
Mac's pairing and phone cache; files and accepted work on the Mac remain.

## Sending and watching

The capsule's Send To picker defaults to Auto. A named Mac stays pinned even if
it becomes unavailable. Watching a Mac in Today changes the canvas and preview,
not the generation destination. External jobs never overwrite the draft; the
model menu exposes an explicit Adopt Run Settings action.

Auto first requires a live enabled host, its advertised multi-host support, a
fresh offer, the exact installed model, unchanged supported settings, adequate
GPU memory budget and host admission. It never downloads, builds, substitutes a
model or lowers settings. A host's Models section exposes explicit loading,
which may download or prepare a model.

`HostSelection` minimizes known queue + preparation + execution estimates, with
an allowance for this phone's submissions not yet reflected in the host queue.
Comparable completed-library timings supply a conservative mean with 20%
allowance. Unknown preparation or execution times remain unknown: deterministic
fallback prefers idle loaded, idle needing load, then busy hosts with known
backlog, memory margin and host fingerprint as tie-breakers. Recommendations
change for a material gain (15% and at least five seconds) or lost eligibility.
Offers expire after at most five seconds, measured from the phone's request
start with a monotonic clock. Each request has a two-second deadline and no
offer retry, so a silent host cannot hold up healthy candidates. Generate refreshes them before assigning work.

This release deliberately uses request-specific offers rather than an additional
unsolicited scheduling stream. Final submission and queue drain repeat strict
admission, so an offer is not a reservation. Installed-only acquisition refuses
network fetches and skips builds even if model storage changes after admission.
Catalog peak scaling is conservative; no inferred hardware benchmark is shown
as a measured ETA. Batches stay on one host. Clip chains retain the strict policy.

## Delivery and recovery

Before sending, the phone atomically saves the immutable request and host
assignment. The Mac keys receipts by authenticated phone signing fingerprint and
request UUID; the digest binds settings and reference content, excluding the
session-local blob UUID. Different payloads cannot reuse the same request ID.
A prepared receipt is written before enqueue; accepted records name its batch.
A crash in either write window remains unknown and cannot authorize a duplicate.
The host's volatile queue is not replayed after restart.

Pending output writes remain active for receipt purposes. Successful writes are
counted before queue absence can imply interruption, independently of index
refresh latency. Completed/interrupted receipts compact after 30 days to
idempotency tombstones; unresolved IDs are never deleted. The phone reconciles
sending/unknown/accepted submissions with their original host after reconnect or
relaunch. An unreadable ledger disables sending. Unknown acceptance never causes
Auto to send the same work to another Mac.

Targeted Stop names the expected run and keeps other batches queued. Old Macs
remain manually usable and expose a visibly host-wide Stop. They are excluded
from Auto; no new command is sent without the optional `multiHost` snapshot flag.
No new unsolicited message kinds were added, so old phones retain their wire
contract with a new Mac.

## Library, references and storage

`CachedEntry.id` is the full host signing-key fingerprint plus filename. Each
host owns its entry and thumbnail directories; originals use host and content
version in their cache keys. Equal filenames, versions, host names or run UUIDs
from different Macs do not share identities. A root `LibraryCatalog` combines
child catalogs; every mutation and fetch resolves the entry's owner. Source
filters and labels expose ownership, including offline hosts.

Modern listings carry a revision. Any library delta during paging invalidates
the staged pass; only a completed current pass permits cache pruning. Legacy
hosts require two identical passes. Sync arms observation before asynchronous
writes. Optimistic rollback affects only unchanged touched rows, and host removal
invalidates epochs and drains observation, media and edits before deleting cache.
The global original-file LRU remains 500 MB. Viewer, sharing and Photos consumers
lease files against eviction. A consumer can temporarily hold the cache over its
limit; releasing it reapplies eviction.

`paired-hosts-v2` migrates the prior pairing with readback verification, retaining
the old item only as recovery evidence. The new collection is authoritative, so
forgetting cannot resurrect it. Ambiguous old entries/thumbnails move into Legacy
quarantine and are adopted only after matching a complete host listing.

A reference from another Mac is fetched through its owner/cache, encoded by the
existing reference pipeline, and uploaded as bytes to the destination. The input
contract carries content digest, byte count, dimensions and source host. The
existing provenance `referenceOrigin` retains the composite host/file identity,
which prevents it being interpreted as a destination-local filename. Existing
source-local operations remain with their owner. Clip-tail continuation over the
link is refused until it has its own uploaded-input contract.

## Connections and resources

Each Mac retains its own room, authenticated guest socket, channel counters,
fragment buffers, client and reconnect loop. The phone shares one multicast
Bonjour browser, one path monitor and a 120 messages/second outbound relay cadence
with burst 40. Reconnect adds 0–350 ms jitter to exponential backoff. Background
closes phone sessions; it does not cancel Mac work.

Incoming bulk transfers are capped at two per phone and one per client, with a
256 MiB aggregate announced-byte budget and a 128 MiB individual-file ceiling.
Partial retry buffers and unclaimed completed blobs remain accounted for; idle
unclaimed data expires. References are limited to 16 MiB. Bulk producers apply
backpressure before sealing, preserving nonce order and leaving the host reader
free for controls. Modern previews are subscribed only on the watched host;
legacy hosts keep their compatible behavior. These are per-phone limits, not an
account-wide throughput guarantee across many phones.

## Validation

Source tests cover 1/2/4/8-host duplicate ownership, secure persistence migration
and failure, shared transfer budgets, selector eligibility/cost/stability, strict
submission deduplication across sessions, receipt crash/retention/save windows,
targeted Stop during a stalled download, revisioned and stable legacy listings,
and independent relay rooms with one phone identity. The simulator fixture knob
`ZEPHRA_PREVIEW_HOSTS=1|2|4|8` works with existing Debug preview states and makes no
network or generation requests. Full gate results and simulator evidence are
recorded in `docs/plans/multi-host-validation.md`.

Physical multi-Mac WAN/cellular throughput and IPv6-only carrier behavior require
field qualification; simulator and in-memory roads do not establish those
measurements. Routing tests use mock backends, never model downloads or real
inference. Future scope remains automatic model acquisition, batch splitting,
accepted-job migration, library replication and background dispatch.
