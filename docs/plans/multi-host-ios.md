# Multi-host iOS companion plan

Status: implemented and peer-reviewed on 2026-09-13. Original research baseline:
`95ede1693557fb79bd3e1d860428b37872295379`. The findings below describe that baseline;
the design sections retain the planning rationale. The implemented contract and
intentional refinements are documented in [Multi-host iOS](../multi-host.md),
with [validation evidence](multi-host-validation.md).

Implementation decisions: request-specific five-second offers replace a separate
scheduling telemetry stream; unknown timings use deterministic readiness/backlog/
memory ranking, never invented performance measurements. Offers have a two-second
request deadline so a silent host cannot stall healthy candidates. Eight enabled
hosts is enforced. Physical WAN/cellular throughput qualification remains an
explicit field-test limitation; simulator fixtures do not establish that result.

## Product outcome

Pair an iPhone with several Macs, browse one combined library, and submit to
Auto or a named Mac. Each Mac remains authoritative for its files and work.
The phone combines their views and chooses a destination; the relay carries
independently encrypted sessions. No central library server is required.

Recommended first release: all enabled paired Macs connect concurrently while
the phone is active; qualify 1, 2, 4 and 8 hosts. Eight is a proposed initial
active-host ceiling to validate, independent of the relay's eight phones per
room. Pairings beyond that can remain saved and disabled. Do not silently
exclude enabled hosts from the library or Auto candidate list.

## Findings in current source

| Area | Current behavior and consequence |
| --- | --- |
| Composition | `Sources/ZephraMobile/App/ZephraMobileApp.swift` owns one `LinkClient`, reconnect loop and catalog. Views consume that client through the environment. This is a cross-surface change. |
| Pairing | `MobileKeychain.swift` stores `device-identity` and one `paired-host`; `LinkKeyStore` loads/saves one host. `LinkClient+Pairing.swift` disconnects before pairing. Adding a Mac currently replaces the relationship. |
| Identity | `PairedHost` has public keys, endpoints and `RoomID`; names and addresses are not identities. The relay verifies the room derives from the host signing key. |
| Library | `CachedEntry.id`, catalog lookups, sync dictionaries, edits and fetches use filenames. Stores are shared across the current single library. Equal filenames from different Macs must never collide. |
| Sync | `LibraryCatalog+Sync.swift` gates removals on `libraryIsComplete`; `LinkClient+LibraryPull.swift` pages by offset while deltas arrive. Completion and removal must be scoped to the host and listing generation. |
| Generation | `StateSnapshot` already carries models, availability, running work, queue, `acceptsWork`, and engine `canQueue`. `ModelSummary` carries capabilities. `EngineStateDTO` has current seconds per step, but no comparable host hardware or job-duration estimate. |
| Admission | `CompanionSession+Commands.swift` submits through `remoteAdmission` and `enqueue(settings:on:count:)` without changing the Mac's draft. It already names a model per request; routing must preserve this seam. |
| Retry | Enqueue deduplication is the session's `runs[requestID]` map. It does not establish cross-session or crash-safe deduplication. A lost acknowledgement is not proof of rejection. |
| Draft | `PromptDraft.adopt` seeds from the first snapshot; `follow` follows one running job. Arbitrary host updates must not change a multi-host draft. |
| Control | `cancel` means whatever is running on that Mac; `clearQueue` is host-wide. A run-specific UI needs stronger command semantics. |
| Relay | `Relay/link/index.mjs` authenticates membership per connection and room. One phone key can join different rooms through different sockets; host supersession is room-scoped. Multiple hosts in one room would be the wrong topology. |
| Traffic | `RelayCadence` is per road; host previews broadcast up to ten times a second. Multiplying sessions multiplies traffic and in-memory blob buffers. |
| Compatibility | `LinkProtocolVersion.current` is 1 and handshakes reject mismatches. Existing hand-written Codable readers show how additive fields retain compatibility. New commands require explicit feature negotiation. |

Source paths above are repository-relative. Supporting references:
`docs/mobile.md`, `docs/companion.md`, `docs/architecture.md`,
`Packages/ZephraLink/Sources/ZephraLinkClient/`,
`Packages/ZephraLink/Sources/ZephraLinkProtocol/`, and
`Packages/ZephraKit/Sources/ZephraLinkHost/`.

## User experience

- **Library:** default to All Macs, a single newest-first grid with existing
  search, tags, favorites and day sections. An optional source filter selects
  one or several Macs. Show a small source label in detail and an offline mark
  where relevant. Stable ties sort by host ID then filename. Identical images
  on two Macs remain two owned items; do not infer replication from hashes.
- **Offline:** cached metadata and thumbnails remain browsable. Cached originals
  remain viewable/shareable. Uncached media says which Mac must reconnect.
  Failure of one Mac must not turn the entire library into an offline screen.
- **Compose:** destination chip defaults to **Auto**; tapping it lists Macs with
  connection, model readiness, workload and a capability summary. Auto shows
  the likely destination and a short explanation before Generate. The actual
  accepted destination is shown with the job afterward.
- **Models:** show the union of paired hosts' catalogs, with “Ready on 2 Macs”
  or a concrete reason none can accept it. A named destination narrows choices.
  Retain an incompatible draft and explain the mismatch instead of silently
  changing model, precision, size, seed, audio or duration. Capabilities from
  different app versions must not be merged into a fictitious supported range.
- **Today:** combine running, queued and completed jobs, each with host ownership.
  Select a job to watch its preview. Viewing a Mac/job does not change the next
  generation destination. An external Mac run never overwrites the draft merely
  because its snapshot arrived last; adopting settings is an explicit action.
- **Controls:** cancel/remove targets the selected host and job. A host-wide
  queue action lives inside that host's detail and names its scope.
- **Hosts:** add, rename locally, retry, enable/disable, exclude from Auto, and
  forget each Mac separately. Pairing another Mac does not interrupt existing
  sessions. Disabling preserves cache; forgetting removes that host's pairing
  and its local cache after explaining the effect. Neither deletes remote files.
  Forgetting with an uncertain submission explains that remote work may continue.
- **One host:** retain the familiar experience; Auto resolves to the only eligible
  Mac. If none are eligible, show the reasons and Retry/Choose Mac actions.
  Do not silently hold a new generation for later foreground delivery.

## Architecture and ownership

Keep `LinkClient` a client for exactly one host. Add small types rather than
making it multiplex encrypted channels or introducing a large controller.

| Proposed type | Placement and responsibility |
| --- | --- |
| `HostID` | LinkProtocol value, derived from full host signing-key fingerprint; verify all pinned peer keys during handshake. Never use the display name, endpoint or socket ID. |
| `PairedHosts` | LinkClient abstraction for collection persistence. App implementation owns Keychain. One device identity is resolved once before creating clients. |
| `HostKeyStore` | Host-scoped adapter to existing client storage, with identity writes centralized. A client's forget/revoke can only remove its own record. |
| `HostConnections` | iOS Support observable collection of clients and per-host reconnect lifetimes. Inject roads and stores; shared path/discovery coordination belongs in the composition layer. |
| `HostLibrary` | iOS Support per-host sync state and stores; cancellation and a session/sync epoch reject obsolete completions. |
| `LibraryItemID` | iOS value `(HostID, fileName)`; remains distinct from unchanged host-local wire filename. |
| `CombinedLibrary` | iOS observable aggregate over host libraries, query and stable selection. No network protocol logic. |
| `GenerationDestination` | iOS value `.auto` or `.host(HostID)`; separate from watched host/job. |
| `HostSelection` | Pure LinkClient policy over value inputs; ranks candidates and returns reasons. No engine import or concrete model families. |
| `Submission` | iOS durable record of immutable request, host assignment and outcome, managed separately from the editable draft. |
| `HostOffer` | LinkProtocol request-specific admission and estimate value, projected on Mac through the engine's existing validation seam. |

Views consume the narrow aggregate or selected host context appropriate to that
surface. Do not retain a hidden global “active client” for mutations. Keep iOS
free of ZephraEngine/MLX/AppKit imports and backend types. One public type per
file, small files and at most three stored properties per view remain rules.
Update AGENTS.md and the architecture/mobile/companion documentation together
when these existing single-client rules change during implementation.

### Pairing and migration

1. Load or create the device identity once. Distinguish missing from unreadable
   Keychain data; a read failure must not mint a replacement identity. Concurrent
   clients must never race identity creation or whole-array pairing writes.
2. Write a versioned host collection with the existing host as its first entry,
   retaining its keys, endpoints and paired date. Verify the new record before
   marking migration complete. Keep a recovery copy of the old item until success;
   the new schema is authoritative afterward and must not resurrect forgotten Macs.
3. Migrate cache files to host namespaces with a journal and atomic completion
   marker. Existing caches have no ownership evidence beyond the old pairing.
   Because prior re-pairing could have left older files, validate against that
   host's complete listing before exposing ambiguous legacy rows as its files.
   Preserve ambiguous data in a legacy quarantine, never send edits against it.
4. Pair into a temporary host-scoped client, persist successfully, then publish
   it into the collection. Surface persistence failure rather than the current
   `try? store.save` success appearance. Deduplicate re-pairing the same key.
5. A changed host signing identity is a new host and needs pairing; matching
   names/addresses never authorizes automatic reassociation of files or jobs.

### Library correctness

Namespace entry JSON, thumbnail versions, full-file paths, in-flight fetches,
viewer selection, Today thumbnails and reference origins by HostID. Existing
wire filenames and GenerationRecord stay source-owned. A global file LRU keeps
the current 500 MB policy across all hosts, rather than multiplying it by host
count. Track metadata/thumbnail storage separately and measure large libraries.

Perform independent incremental syncs. A reset/disconnect affects only its
host. Do not prune from a partial or failed listing. Add negotiated listing
revision/cursor support so concurrent inserts/deletes cannot make offset pages
look complete while skipping files; apply deltas relative to that revision.
For legacy hosts, preserve conservative upserts and require a verified stable
reconciliation before removal; explicit removal deltas remain host-scoped.

Route every fetch, favorite, tag, delete and source-local action by item owner.
For cross-host selections, partition operations by host and return per-item
results. Roll back only the failed items and only if their mutation revision
still matches; restoring an entire old catalog would overwrite concurrent work.
Host removal cancels and drains that host's writes before removing its directory.
Pin visible/exporting media against eviction until consumers release it.

A reference from Mac A can be used on Mac B by fetching the bytes from A (or the
local cache), then uploading them to B using its existing reference-blob path.
Do not send A's filename as though it names a file on B. Retain source attribution
in a negotiated host-qualified provenance field, preserving old provenance
readers. If bytes cannot be fetched, the job cannot be dispatched. Source-local
operations such as existing upscale/animate stay with A initially; a cross-host
version must become an explicit uploaded-input generation operation.

## Auto routing

Auto chooses a host for the exact model and settings the user requested. It does
not choose a different model or reduce quality to make a weak host eligible.

### Information contract

Add optional feature flags and scheduling summary fields to snapshots and their
deltas, with defaulting readers. Host-projected facts include session/boot epoch,
monotonic sequence, installed-ready models, loaded model, admission state,
usable memory budget, pressure/thermal constraints, and per-model execution
support. Hardware class and memory describe capability; they are not enough to
promise runtime or guarantee that a job fits.

A negotiated `offerGeneration` command evaluates an immutable request without
queueing, loading or downloading. Return admitted/refused with reason, estimated
queue wait, model preparation time, execution time, memory margin and estimate
confidence, plus queue revision and offer lifetime. Use existing Mac validation
and queue planning; do not duplicate engine admission logic on the phone.
Current `remoteAdmission` checks basic request/admission state, not predicted
memory fit or installation readiness, and enqueue clamps settings. Extend the
engine with a side-effect-free workload assessment rather than claiming those
checks already exist. Offers return normalized settings and a digest; Auto must
refuse material normalization rather than silently changing the requested job.
An offer includes input metadata (reference presence, dimensions, byte count,
and digest), never full pixels. Final submission validates the uploaded input
against it. Clip-tail continuation bytes do not cross the current protocol;
continuation requests are ineligible until a separate input-transfer contract
exists, rather than being silently dropped by `withoutPixels`/clamp.
Readiness excludes unfinished downloads/builds. Offers are advisory; final enqueue
revalidates because other phones and the Mac can submit in the meantime.
Bind the negotiated enqueue to the same strict execution policy as the offer:
exact supported settings, installed-ready model, no download/build, and current
memory/admission checks. Otherwise a model removed after the offer could start
a download during queue drain. Recheck before execution too; policy failure
terminates the job with a reason instead of changing it. Legacy enqueue keeps
its existing behavior for old phones; new strict commands are feature-gated.

Collect passive timings from completed work: model ID/revision, dimensions,
frames, steps, batch count, residency, load and finalization stages. Include
chained clips, decoding, audio and upscale where requested. No benchmark
inference is launched just to rank hosts. Use bounded rolling estimates and
conservative fallback profiles; current seconds-per-step is evidence only for
comparable workloads. Timings and summary facts stay inside encrypted sessions.

### Selection algorithm

1. Filter enabled, Auto-allowed, authenticated live hosts. Require a fresh
   snapshot and offer: start with a configurable 5-second offer lifetime and
   bounded parallel offer requests. Use local monotonic receipt age, not clocks
   synchronized between machines. Expired/unknown admission cannot win Auto.
2. Require exact model/variant support, an already usable installed model,
   compatible settings and reference/continuation support, and host approval of
   the workload's memory/engine constraints. Never infer fit from total RAM alone.
   Auto does not download or build models in this release. Manual preparation is
   explicit and then the job can be retried.
3. Minimize estimated completion: queue work ahead + preparation/model switch +
   generation/finalization + required input transfer + uncertainty allowance.
   Count work and duration, not queue length: a ten-minute clip is not equivalent
   to one small image. Cached reference input and upload path affect transfer cost.
4. When estimates are sparse, use deterministic tiers: eligible idle with model
   loaded, eligible idle requiring load, then busy eligible hosts ranked by known
   backlog; use host capability/memory margin as a tie-breaker, then stable HostID.
   Mark this result “Best available” rather than displaying a fabricated ETA.
5. Stabilize the pre-submit recommendation: switch only for a material advantage
   (initial tuning: 15% and at least 5 seconds) or lost eligibility. At Generate,
   freeze seed/settings/request ID, refresh offers, choose once, and record the
   assignment before sending. Explain any changed destination in the accepted job.
6. Account for this phone's submissions not yet reflected in host snapshots so
   rapid presses do not all see the same empty queue. Distinct phones still race;
   final host admission is authoritative and explicit rejection permits reranking.

Example: an idle slower Mac with the model ready can beat a faster Mac behind a
long clip. The faster Mac wins when its shorter predicted run outweighs its wait.
A very capable Mac missing the model is excluded from Auto, with the reason shown.
A pinned Mac is never silently replaced by another.

### Submission and failure semantics

Persist the assignment before network I/O. States are prepared, sending,
accepted(hostID, batchID), rejected, outcomeUnknown, and terminal. Preserve the
request ID and immutable parameters on retries; reference blob IDs are session
local and may change on re-upload. Never rerandomize the seed during a retry.
The receipt digest covers canonical settings and input content digests, excluding
transport-local blob IDs. Persist the accepted expanded batch seeds/identities
with the receipt if recovery can replay work: `BatchExpansion` currently creates
fresh seeds for members after the first, so the original seed alone is not the
whole batch's reproducibility contract.

Before enabling unattended retry across reconnects, replace the session-local
map with a host-owned receipt ledger keyed by authenticated phone signing identity
and request ID. Persist a payload digest and batch ID; mismatched payload reuse
is rejected. Add negotiated receipt lookup. Enqueue acceptance and the receipt
must be recoverable together; a crash between them must not produce an absent
receipt that falsely authorizes a duplicate. If the existing queue cannot meet
that guarantee, persist a prepared receipt first and report its unresolved crash
window as unknown, never absent. This is a prerequisite, not a promise of global
exactly-once processing.

Retain unresolved receipts indefinitely until reconciled; define a bounded
terminal receipt retention period (initial proposal: 30 days). Expired/evicted
requests return unknown, not “never accepted.” Persist the phone's unresolved
submission and reconcile after relaunch. A host restart that loses volatile queue
work reports interrupted/unknown truthfully rather than pretending it is queued.

Auto may try another host only before sending enqueue bytes, or after an explicit
non-acceptance response. Timeout/disconnect after a possible send means “Checking
submission on Mac A.” Query/retry A under the same request ID when supported.
Do not send to B while acceptance on A is uncertain, even if A is now offline.
The user may explicitly create a new job after a duplicate-risk explanation.
Legacy hosts support manual submission with uncertainty shown and no automatic
cross-session resend; Auto requires the negotiated offer/receipt features.

Keep a batch on one host in the first release. Automatic batch splitting and
moving accepted jobs require a separate ownership and cancellation design.
Add negotiated `cancelRun(expectedRunID:)` and targeted queue commands; a stale
Stop button must not cancel a new run that began after the user tapped it.
Legacy hosts expose clearly labeled host-wide Stop controls only.

## Relay and transport plan

Keep one room per Mac and one phone guest socket per connected relay host.
Each socket authenticates independently using the same phone identity, pinned
host keys and its own channel counters, fragment buffers and blob state. Existing
room allow-lists/revocation and eight-guest caps remain independent. No relay
plaintext scheduling data, combined room, cloud account or shared encryption key.

Add relay contract tests for one phone key in two rooms, concurrent forwarding,
revocation in A with B unaffected, room-local supersession, independent guest
caps and disconnect cleanup. Avoid a relay schema change unless tests expose a
real need. Validate the current deployed artifact and stage configuration before
release; repository documentation's 500 requests/second and burst 1000 are not
live measurements from this research.

Traffic changes are required even if room routing stays unchanged:

- Negotiate preview subscriptions; send previews only for the watched job/host,
  with scalar state continuing for all. Legacy peers retain compatible defaults.
- Inject a phone-wide outbound relay budget alongside per-road pacing. Preserve
  sealed-frame order: prioritize before sealing/queueing, never reorder nonce
  counters or drop arbitrary already sealed frames. Coalesce preview production.
- Coordinate downloads across hosts: start with two bulk transfers globally,
  one per host; prioritize visible thumbnails, user-opened media and reference
  uploads. Bound buffered bytes, including unsolicited blobs and originals, not
  only request counts. Use cancellation-aware queues and backpressure.
- Host-to-phone traffic needs subscription/transfer admission limits too; a
  phone's outbound bucket cannot control several Macs' inbound streams. Shared
  limits across different phones ultimately require relay admission/quota tuning;
  per-phone budgeting alone is not an account-wide rate guarantee.
- Use one app-owned network path watch, bounded connection attempts and jittered
  per-host backoff. `NetworkLinkRoads` currently owns a single `BonjourBrowser`;
a shared discovery implementation must multicast results to independent consumers
and reference-count lifetime. One host ending its LAN race must not stop another
host's browse. Do not share the current single-consumer stream unchanged.
Background closes all phone sessions, while accepted Mac jobs
  continue. Foreground reconnects independently and reconciles submissions.

AWS documents a 32 KB frame cap, ten-minute idle timeout and two-hour connection
lifetime. Keep fragmentation and reconnection behavior; multiplexing does not
remove these limits. [AWS WebSocket quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-execution-service-websocket-limits-table.html).

## Compatibility and rollout

Retain protocol v1 for additive fields/negotiated commands only. Test old fixtures
against new decoders and new snapshots against old decoders; absent optional
features mean legacy behavior. Do not send new command enum cases to old Macs.
Negotiation is bidirectional: the Mac advertises support in optional snapshot
fields; a capable phone explicitly opts in per session before the Mac emits any
new event/reply kind. `StateDelta+Codable.Kind` is a closed enum, as are other
wire discriminators: host support alone does not establish phone support.
Until opt-in, use existing cases with additive fields or legacy publication only.
Test an old phone receiving continuous new-Mac deltas/library events, not merely
its ability to decode the first snapshot.
If a necessary envelope/security change cannot be additive, design an explicit
version transition rather than simply bumping the current strict-match number.

New phone + old Mac: pairing, combined library and explicit destination work;
advanced Auto is unavailable for that host with an update explanation. Old phone
+ new Mac: its current single-host behavior continues. Mixed hosts remain visible
and independently usable. Install supporting Mac changes before enabling Auto
in the phone release. Relay routing stays compatible throughout.

## Implementation sequence and acceptance gates

1. **Identity and scoped storage.** Add HostID, collection persistence, adapters,
   migration and per-host fixtures. Gate: crash-safe migration, duplicate names,
   re-pair, Keychain read/write failures and concurrent construction lose no keys.
2. **Concurrent host sessions.** Add connection collection, independent pairing,
   reconnect/path lifecycle and Hosts settings. Gate: A failing, revoking or being
   removed never disconnects B; background/foreground and cancellation settle.
3. **Combined library.** Namespace every cache/selection/action path, implement
   scoped sync, revision-aware listing and combined queries. Gate: two hosts with
   identical filenames/versions remain separate through viewing, editing,
   partial sync, cache eviction and deletion; cold offline launch works.
4. **Explicit generation destinations.** Separate draft/destination/watched run,
   aggregate Today, add host-qualified references and targeted control. Gate:
   each command hits its owner and concurrent snapshots do not rewrite drafts.
5. **Mac offers and receipts.** Add feature negotiation, engine-backed estimates,
   receipt persistence/recovery and targeted cancellation. Gate: dropped ack,
   reconnect and crash-window fault tests cannot silently create a second job.
6. **Auto policy.** Implement pure selector, reason presentation, request refresh,
   local pending load and uncertainty handling. Gate: scenario table below passes
   with fixed clocks/estimates; legacy and stale hosts cannot be selected.
7. **Scale and release qualification.** Add preview subscriptions and global
   transfer budgeting before shipping concurrent-host functionality. Run relay
   contract, resource and UI tests at 1/2/4/8 hosts; record evidence, adjust the
   active ceiling/budgets, update docs and ship Mac support before phone Auto.

Steps 3 and 4 depend on 1–2; 6 depends on 4–5. Step 7's traffic controls are a
release gate for 2–6, not optional polish. Use normal feature branches such as
`feat/ios-host-connections`, conventional commits and `make lint-layers` before
any implementation commit. This plan itself does not deploy or run inference.

| Qualification | Required evidence |
| --- | --- |
| Selection | Fast busy vs slow idle; loaded vs load needed; large video vs small image queue; memory refusal; missing/building model; unknown timings; stale offers; tie stability; all offline; pinned unavailable; multiple pending presses. |
| Ownership | Duplicate host names and files; same UUID from different hosts; cache reopen; viewer/swipe/selection after source removal; per-item mutation failure; late completion after forget. |
| Delivery | Lost enqueue ack; disconnect before/after send; reference re-upload; phone termination; Mac crash at each receipt boundary; retention expiry; same ID different payload; two phones submitting simultaneously. |
| Library | Large paged listings with insert/delete and same-count replacement; disconnect mid-pull; resync; per-host stale flags; cross-host reference with source offline and cached/uncached bytes. |
| Compatibility | Old phone/new Mac; new phone/old Mac; mixed capability hosts; absent fields; unsupported feature; strict version mismatch; old cache migration without known owner. |
| Relay | Two rooms and same guest key, room-local isolation, full room, supersession, reordered/dropped fragments, throttle, long transfer and reconnect. |
| Native UI | Frozen 1/2/4/8-host fixtures, VoiceOver source/target labels, Dynamic Type, light/dark, offline grid, Auto explanation, target picker, simultaneous Today jobs and unmistakable Stop scope. |
| Performance | Aggregate memory and in-flight bytes, first cached grid time, scrolling with large libraries, reconnect storm, traffic across all hosts, watched-preview latency during downloads. No MLX load for protocol/UI tests. |

Use Swift Testing in ZephraLink/ZephraKit, hosted `make test-ios`, `make relay-test`
and layer lint. Run source-only fake-host tests first. Final LAN and forced-relay
UAT needs multiple distinct host identities, at least two phones for contention,
and an IPv6-only path when available. Validate routing with fake generation
backends; any final real-generation qualification is a separate scheduled run on
idle Macs, with retained evidence.

## Decisions and later scope

Recommended decisions are explicit in this plan: one room per host, one combined
library, Auto by default, installed-ready models only for Auto, no automatic
model substitution, one batch per host, host-owned files, and safe uncertainty
over duplicate work. No unresolved product question blocks the foundational
identity/library work. Thresholds, the initial active-host ceiling and receipt
retention are qualification settings to settle before release.

Later scope: automatic model acquisition, batch splitting, job migration,
cross-host file replication/deduplication, cross-host source-local edit operations,
and unattended phone-background dispatch. Record these in ROADMAP.md alongside
this plan; they must not become implicit promises of the initial feature.

## Peer review

Completed 2026-09-13 by independent subagent `review_multi_host_plan`, which
checked the plan against the current app, link and relay source. The reviewer
found the identity, library ownership, relay topology and conservative submission
semantics sound and judged the plan ready after the compatibility clarification.
All findings have been incorporated:

- Strict installation/settings/memory policy is shared by offers, submission
  and execution rather than assumed from today's permissive admission/clamping.
- Reference offers carry metadata; receipts bind input content, not blob IDs.
- Recoverable batches preserve expanded member seeds and identities.
- Shared discovery multicasts with independent consumer lifetimes.
- Bidirectional session negotiation gates new events/replies as well as commands;
  old-client continuous-publication tests are required.

Research validation: existing `make relay-test` passed 115/115 tests, and
`git diff --check` passed. These establish the current baseline, not proof of
unimplemented multi-host behavior. No app implementation, generation, deployment
or production configuration mutation was performed.

Implementation review also completed on 2026-09-13. The same independent reviewer
rechecked the completed source after corrections and reported no remaining merge
blockers. See [validation](multi-host-validation.md) for gates and field limits.
