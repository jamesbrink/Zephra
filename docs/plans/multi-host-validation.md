# Multi-host validation — 2026-09-13

## Automated gates

All passed locally on the implementation branch:

| Gate | Result |
| --- | --- |
| `make doctor` | Xcode 26.6 and Metal toolchain ready |
| `make lint-layers` | Passed |
| `make test` | 747 tests, 137 suites |
| `swift test --package-path Packages/ZephraLink` | 256 tests, 42 suites |
| `make test-ios` | 168 tests, 29 suites, iPhone 17 Pro / iOS 26.5 |
| `make test-app` | 222 tests, 47 suites |
| `make test-mlx` | All 12 test runs passed, 498 tests in total |
| `make relay-test` | 121 tests |
| `git diff --check` | Passed |

Logs were retained under `/tmp/zephra-{doctor,kit-tests,link-tests,ios-tests,app-tests,mlx-tests,relay-tests}.log`.
Xcode test results are in `.build/DerivedData/Logs/Test/`. These paths are local
run artifacts, not portable repository fixtures. The PR Gates job repeats the
fast gates on its tested revision before merge; full Metal gates ran locally.

## Simulator checks

Frozen fixtures use `ZEPHRA_PREVIEW_STATE` and `ZEPHRA_PREVIEW_HOSTS` on iPhone 17
Pro, iOS 26.5. They make no network or generation requests.

- Four-host library: twelve entries with deliberately duplicated filenames remain
  twelve distinct rows. Source and offline labels appear in the grid and in
  accessibility button labels. Selecting Studio Mac reduces the grid to its
  three entries. Selecting Render Mac 3 as well yields six entries from exactly those two Macs.
- Canvas: Auto recommends a ready host independently of the watched host. The
  destination picker includes each Mac and its offline state. A named offline
  target stays pinned and blocks sending rather than redirecting work.
- Eight-host Today: independent host sections expose Watch and explicitly named
  host-wide legacy Stop controls. Automated ownership tests cover 1/2/4/8 hosts.
- Visual inspection found source/favorite overlap; source labels now reserve the
  favorite marker's space. Library placeholders are intentional fixture media.

## Relay deployment observation

Read-only AWS inspection in `us-west-2` confirmed the deployed `zephra-link`
Lambda is Active/Successful, Node.js 20, last modified 2026-09-13 14:23:50 UTC.
API `h5vpuxpgtf` and `zephra-link.urandom.io` are dual-stack, with the domain
Available. Production stage throttling is 500 requests/second, burst 1000.
No infrastructure or deployed Lambda code was changed during qualification.
Relay source behavior is unchanged; new multi-room tests exercise the existing
one-host-per-room topology with one phone identity across rooms.

## Independent review

Subagent `review_multi_host_plan` reviewed both the plan and final implementation.
Corrections covered strict acquisition at queue drain, durable uncertainty,
receipt save races, stable selection, revision-safe paging, shared transfer
accounting, host removal and pairing lifecycle, and control responsiveness during
bulk transfers. The final finding (a stalled offer expiring healthy peers) was
fixed with a two-second cancellation-aware deadline and a dedicated passing test.
The reviewer reported no remaining merge blockers; it inspected source/tests and
did not independently rerun suites.

## Field qualification boundary

No physical multi-Mac LAN/forced-relay session, two-physical-phone contention,
IPv6-only carrier path or real generation was exercised in this run. In-memory
roads, relay fakes and simulator fixtures establish correctness scenarios, not
WAN throughput, real-device energy use or end-to-end carrier measurements.

## Integration with concurrent main changes

GitHub reported a model-picker conflict with main at `6ae435a`. The resolution
retains per-host memory eligibility and memory notes while choosing only the
phone draft. A regression test covers an insufficient-memory Mac beside a
capable Mac, manual pinning and disabling the capable host. The independent
reviewer cleared the integrated source. Integrated Kit (769), Link (259) and
iOS (176) tests passed after a fresh build; the reconnect timing assertion now
includes the documented 350 ms jitter. Full integrated Mac/MLX gates are also
required before merge, in addition to the passing pre-integration gates above.
