# Multi-host qualification — 2026-09-13

Implementation and local qualification are complete. Core functionality merged in
[PR #47](https://github.com/jamesbrink/Zephra/pull/47); the qualification fixes and
this evidence are delivered by [PR #48](https://github.com/jamesbrink/Zephra/pull/48).
Merge requires the Gates job to pass on the final PR head.

## Source and automated gates

Final implementation revision: `e2dee21` (`fix(ios): keep run controls readable at
accessibility sizes`). This includes main at `47940f3`. Kit, Link, hosted Mac and
MLX ran on `1b30c0a`; the only implementation change afterward is the two iOS
Today layouts. iOS tests, final UI checks and the scroll profile include that
change. Later commits contain qualification documentation and artifacts only.

| Gate | Result |
| --- | --- |
| `make lint-layers`, `git diff --check` | Passed before implementation commits |
| `make test` | 785 tests / 147 suites passed |
| `swift test --package-path Packages/ZephraLink` | 274 tests / 50 suites passed |
| `make test-ios` | 192 tests / 38 suites passed |
| `make test-app` | 234 tests / 49 suites passed |
| `make test-mlx` | All 12 test runs in 11 package invocations passed; 511 tests |
| `make relay-test` | 121 tests passed |

[Portable results](evidence/multi-host/test-results.json) contain extracted results
and SHA-256 hashes of full local logs. Xcode used fresh integrated build products
under `/tmp/zephra-integrated-{derived,build}`. Metal tests exercised synthetic
fixtures; they did not load production models or launch real generations.

The added regressions cover current-session capabilities, independent host
lifecycle, cancellation during pairing/reconnect/relay join, interrupted migration,
revisioned paging across reconnect, owner-qualified media and edits, cross-host
reference upload and re-upload, durable receipt write failures, and repeated
submission before a queue delta arrives. Pending accepted work reserves capacity;
publication replaces that reservation without double-counting. Frozen legacy outer
snapshot/delta decoders continuously read new-host publications. This is wire
compatibility coverage, not execution of an old released app binary.

## Real transport UAT

Independent temporary host identities and mock engines communicate over actual
TCP sockets or the deployed WebSocket relay. Both phones use one identity across
all rooms. No existing pairing or user library is read.

| Hosts × phones per host | TCP | Forced relay |
| --- | ---: | ---: |
| 1 × 2 | 0.425 s | 5.442 s |
| 2 × 2 | 0.880 s | 11.698 s |
| 4 × 2 | 1.570 s | 22.439 s |
| 8 × 2 | 2.932 s | 43.947 s |

Each case pairs and authenticates, requests offers, concurrently submits the same
request UUID from different phones, reconnects and retries without duplicate work,
mutates only the owner of `same.png`, downloads that file to both phones, and
stops host A while the remaining hosts continue accepting commands. The relay
matrix bypasses LAN. [Stage log](evidence/multi-host/relay-matrix-events.log).

One preceding relay matrix failed during the eight-host download. API Gateway
reported a destination as gone on a fragment; the relay removed its membership.
A later retry received “not joined,” closing the socket. The underlying reason
API Gateway reported the connection gone is unresolved. The isolated eight-host
rerun (45.611 s) and subsequent complete matrix above passed. Both
[client](evidence/multi-host/relay-disruption-client.log) and
[server](evidence/multi-host/relay-disruption-server.log) failure evidence are
retained. Successful reruns do not erase this external-transport interruption;
app lifecycle tests separately prove reconnect and receipt reconciliation.

Initial qualification also exposed valid relay frames overtaking one another by
more than the LAN's 500 ms window. Relay roads now use a bounded two-second hold.
No Lambda or infrastructure change was made. Read-only deployment inspection
confirmed the deployed source matched `Relay/link/index.mjs`, the API/domain were
dual-stack, and production throttling was 500 requests/s with a burst of 1000.

## Performance measurements

The integrated forced-relay load test used eight mock-backed hosts and sixteen
clients. Eight simultaneous 2 MiB downloads shared one phone's transfer admission;
a watched preview crossed during the downloads, then all sixteen clients reconnected.

| Measurement | Observed |
| --- | ---: |
| Total download payload | 16 MiB |
| Bulk completion | 4.936 s |
| Watched preview latency | 1.425 s |
| Peak admitted blob bytes | 4 MiB |
| Sixteen-client reconnect storm | 1.137 s |
| Baseline / peak process physical footprint | 26,460,976 / 77,415,264 bytes |

Footprint samples are every 10 ms and include the entire macOS test process—mock
hosts and clients together. They are not a physical iPhone memory measurement.
Transfer limits remain two active globally, one per owner, 256 MiB announced
aggregate and 128 MiB per file. Preview congestion retains only the latest frame
and drops it when the run changes or the subscription ends.

A disk-backed eight-host / 8,000-entry library took 0.407 s to reopen cached
metadata and 0.029 s for first grouping in the final hosted iOS test. These are
data-readiness measurements, not first rendered-frame latency.

A final-source Debug Simulator ETTrace capture profiled one upward 0.8-distance
swipe in the already-open 8,000-entry library. The trace spans 9.604 s, with
0.641 s active main-thread samples and 8.963 s idle. Accessibility snapshot
polling accounts for substantial activity (`_XCopyAttributeValue`, 38.87% of active
inclusive samples); individual AttributeGraph update leaves are about 3.5% each.
There was no dominant sampled application leaf. The UI action succeeded, but its
automatic accessibility snapshot exceeded the 2.5 s settling deadline. This is a
small, automation-influenced CPU sample, not an FPS or scroll-hitch guarantee.

The [processed profile](evidence/multi-host/scroll-profile.json.gz) and
[analysis](evidence/multi-host/scroll-profile.txt) are preserved. ETTrace v1.1.0,
iPhone 17 Pro / iOS 26.5, one run, warm metadata and placeholder media.
UUID-matched app, Debug dylib and ETTrace dSYMs were collected; app-owned symbols
resolved. Remaining unsymbolicated samples were ETTrace internals (5.55%) and
system libraries (under 0.7%). The application-code dylib UUID is
`11B663D9-603C-3219-A825-07271E71879E`. Temporary profiling linkage was removed and
the uninstrumented app reinstalled. No comparative speedup is claimed.

## Simulator and accessibility checks

The 1/2/4/8-host library fixtures show 3/6/12/24 distinct entries despite duplicate
filenames. [Screenshots and accessibility captures](evidence/multi-host/README.md)
show owner names and offline state. Source filtering was exercised against Studio
Mac; only its three entries remained. Reference buttons identify their owner;
an unavailable uncached source produces a visible failure and explicit Clear
reference request action, keeping Generate blocked.

Canvas destination remains independent of the watched Mac. Auto explains its
choice; a named unavailable target remains pinned. Mixed modern/legacy Today
fixtures expose “Stop Run on halcyon” and “Stop All Work on Studio Mac.”
Watch, source selection, target selection and host settings actions were exercised.

Light/default text and dark/largest accessibility text were inspected. At the
largest size, the composer scrolls, library uses one column and a collection menu,
and running/waiting/finished Today rows stack their controls. Host details remains
a native scrollable Form. Accessible labels name media sources, generation targets,
stop scope and the Mac name field. Semantic accessibility labels and activation
were verified through Simulator automation; spoken VoiceOver output was not tested.

## Independent review and qualification limits

`review_multi_host_plan` reviewed the plan, implementation, integration and final
Today layout changes. Valid findings were addressed, including stale previews on
run transitions, cancellation, truthful routing reasons, and accepted-work
reservations before publication. The reviewer reported no remaining source
blockers, contingent on these gates and UI checks. It inspected source/tests
without independently rerunning them.

These results establish protocol behavior over real transports with isolated mock
engines, plus Simulator UI and bounded performance evidence. They do not claim
physical multi-Mac/iPhone UAT, spoken VoiceOver audio, IPv6-only carrier operation,
real-model generation throughput, battery use or first-frame timing. Automatic
model acquisition, batch splitting, accepted-job migration, media replication and
unattended background dispatch remain the plan's explicitly deferred scope.
