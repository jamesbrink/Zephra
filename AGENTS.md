# Zephra

Zephra is a native macOS app that generates images locally on Apple Silicon,
via MLX/Metal. It runs five model families today, Z-Image-Turbo,
Qwen-Image-2512, FLUX.2 klein 4B, Wan 2.2 and LTX-2.5 (video, with sound on one
entry), behind one backend seam.

## Quick reference

| Task | Command |
| --- | --- |
| Regenerate the Xcode project | `make gen` (edit `project.yml`; the `.xcodeproj` is generated and gitignored) |
| Build, run | `make build`, `make run` (Release by default, `CONFIG=Debug` otherwise) |
| Fast tests, no Metal | `make test` (`swift test` in `Packages/ZephraKit`) |
| App-target tests | `make test-app` (Debug, hosted in the app; minutes the first time) |
| MLX package tests | `make test-mlx` (`xcodebuild` over `MLX_PACKAGES`) |
| Layer lint, before every commit | `make lint-layers` |
| One ZephraKit suite | `cd Packages/ZephraKit && swift test --filter ModelSwap` |
| One MLX suite | `cd Packages/ZephraMLXKit && xcodebuild test -scheme ZephraMLXKit-Package -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:ZephraQuantizationTests/QuantizableWeightTests` |
| One app-target suite | the `test-app` xcodebuild line with `-only-testing:ZephraTests/ExportPlanTests` |
| Benchmark | `make bench ARGS="--size 1024 --steps 9 --runs 3 --json"` (Release, idle Mac) |
| Logs, screenshot | `make logs`, `make screenshot WINDOW=<title>` |
| The phone | `make build-ios`, `make run-ios` (`PREVIEW=<state>`), `make test-ios` |
| The phone, to TestFlight | `make testflight` (`archive-ios` first; needs the `ASC_*` key in `signing.env`) |

What trips a first session: `swift build` and `swift test` work only in the
MLX-free packages, `Packages/ZephraKit`, `Packages/ZephraLink` and
`Packages/ZephraStyle`, because everything else links mlx-swift and its Metal
kernels need `xcodebuild`; a test filter matches *type* names, never `@Suite`
display names; tests are Swift Testing, never XCTest; and on this volume use
`/bin/ls`, since the shell's `ls` function can hang.

This file is the rules. Each section ends with a pointer into `docs/`, where
the reasoning and the history behind those rules live; read there before
changing a rule, and change both when one moves. Measured sizes, peaks and
timings live in `BENCHMARKS.md`, deferred work in `ROADMAP.md`.

## Priorities

In order:

1. **Very clean code.** Small files, one type per file, compiler-enforced
   module boundaries, no god objects.
2. **Extensible for more models later.** An explicit backend/model seam
   (protocol + descriptor catalog). Z-Image-Turbo, Qwen-Image, FLUX.2 klein
   and LTX-2.5 are the implementations; the UI never touches any family's types.
3. **Performance on Apple Silicon**, then a nice, fully native SwiftUI UI.

## Layering rules — non-negotiable

```
Sources/Zephra (SwiftUI app) ─→ ZephraEngine ─→ ZephraCore, ZephraSnapshot
                             ─→ ZephraBackend<Family> ─→ ZephraCore, ZephraSnapshot,
                                                          ZephraQuantization, <Family>Kit
                                                          [imported in ZephraApp.swift ONLY]
                             ─→ ZephraUpscale<Network> ─→ ZephraCore, ZephraMLX
                                                          [imported in ZephraApp.swift ONLY]
                             ─→ ZephraStyle ─→ ZephraCore
                             ─→ ZephraLinkHost ─→ ZephraCore, ZephraEngine,
                                                   ZephraLinkProtocol
                             ─→ ZephraLinkTransport ─→ ZephraLinkProtocol
                                                   [Companion/ only, to open a road]
Sources/ZephraMobile (iOS)   ─→ ZephraCore, ZephraLinkProtocol, ZephraLinkTransport,
                                ZephraLinkClient, ZephraStyle
                                [never a backend, MLX, ZephraEngine or AppKit]
Sources/ZephraBench (tool)   ─→ ZephraCore, every ZephraBackend<Family>
Sources/ZephraQuantize (tool)─→ ZephraCore, ZephraSnapshot, ZephraQuantization,
                                every ZephraBackend<Family>

Shared, by what a file actually touches:
  ZephraKit/ZephraSnapshot     Foundation, CryptoKit — the model downloader, local snapshot
                                                  checks, the hub cache read as a fallback,
                                                  what the models occupy on disk
  ZephraKit/ZephraMedia        Foundation, AVFoundation, ZephraCore — frames in, an H.264
                                                  MP4 out (`MP4Writer`, with an AAC track when
                                                  handed an `AudioTrack`), which a video backend
                                                  takes for its clip; a clip's tail read back
                                                  (`ClipTail`) and clips joined (`MP4Stitcher`,
                                                  the one `ClipEditing`, its blocking reads on
                                                  `ClipWork`'s own queue), which the engine
                                                  reaches only through the protocol in Core and
                                                  the app links in `ZephraApp.swift` alone, to
                                                  inject it; the player is AVKit's over the file
  ZephraKit/ZephraLinkHost     Foundation, Observation, ImageIO, CoreGraphics, os,
                                                  ZephraCore, ZephraEngine,
                                                  ZephraLinkProtocol — the Mac's side of the
                                                  link: CompanionHost, the sessions a paired
                                                  phone talks through, the projections that
                                                  turn the store and the index into what
                                                  crosses, and the JPEG a preview frame
                                                  becomes. No UI framework and no road
  ZephraKit/ZephraTestSupport  Foundation, ZephraCore — Scratch, the filesystem test
                                                  fixture, and SnapshotUnderTest, the real
                                                  snapshot a kit's suite may read
  ZephraStyle                  SwiftUI, ZephraCore — the chrome both apps draw with:
                                                  ZephraChrome's radii, hairlines and
                                                  heights, the washes, the palette's colour
                                                  sets, and the badges that are only those.
                                                  No AppKit, no UIKit, no engine
  ZephraMLXKit/ZephraQuantization  MLX, ZephraCore, ZephraSnapshot — the streaming weight
                                                  packer, and the one descriptor build every
                                                  family runs through it
  ZephraLink/ZephraLinkProtocol    Foundation, CryptoKit, ZephraCore, ZephraEngine — the wire
                                                  the Mac and the phone both speak: the
                                                  frames, the state snapshot and its deltas, the
                                                  commands, a Noise-style channel, the QR
                                                  pairing payload and the relay's JSON; no
                                                  transport and no interface
  ZephraLink/ZephraLinkTransport   Foundation, Network, os, ZephraLinkProtocol — the roads:
                                                  TCPConnection and TCPListener behind a
                                                  four-byte length, the listener's own Bonjour
                                                  advertisement and BonjourBrowser, and the
                                                  relay's RelayConnection and RelayListener,
                                                  which routes the room's phones by the
                                                  guest id on every frame
  ZephraLink/ZephraLinkClient      Foundation, Observation, ZephraLinkProtocol,
                                                  ZephraLinkTransport — LinkClient, one
                                                  host session the phone observes, over an
                                                  injected LinkRoads and LinkKeyStore;
                                                  Sources/ZephraMobile is what links it
  ZephraMLXKit/ZephraMLX           MLX, MLXNN, ZephraCore — the packed loader, the manifest
                                                  reader, the rotary table, the pixel packer,
                                                  the tiled decode, the allocator's knobs and
                                                  the streamed layer stack; <Family>Kit may
                                                  take it
```

- `ZephraCore` (`Packages/ZephraKit`): Sendable value types + protocols. Zero
  dependencies — no model package, no MLX, no SwiftUI.
- `ZephraSnapshot` (`Packages/ZephraKit`): downloading a model, checking a local
  model directory, reading the Hugging Face cache as a fallback, and listing what
  the catalog's models occupy on disk. Foundation only, so `make test` covers all
  of it through a `URLProtocol` stub.
  - `Download/`: `ModelDownloader` resolves the catalog's branch to one commit,
    pins it in `.zephra-revision`, lists that commit (`RepositoryListing`,
    `FilePattern` globs with fnmatch rules) and fetches into
    `<models>/Downloads/<org>--<repo>/`, flat. A file in flight is
    `<name>.incomplete`, renamed only when its size matches the listing; a resume
    sends `Range` and `If-Range` with the stored `ETag`, and a 200 to a `Range`
    request or a 206 that does not begin where the file ends starts the file
    over. `.zephra-commit` records what a finished folder holds, so a transfer at
    another commit empties it first. Any listed path that would leave the folder,
    links followed, is refused before anything is written; a partial that is a
    link is replaced, and a folder that is a link is never emptied. Body is
    paused above 64 MiB unwritten and resumed under 16 MiB (`ChunkedDownload`).
    The app injects `TransferAcquisition`: `ModelTransfers` owns at most two
    transfers with one writer per destination, and `ModelDownloads` keeps
    requests alive independently of the foreground load: switching models
    detaches that waiter, Pause preserves partials, and explicit Cancel discards
    unfinished files only after the final owner and writer settle. Completed
    repositories and cached releases stay, and a network failure remains
    resumable. **No `Authorization`
    header is ever sent.**
  - `HubSnapshotCheck` says when a directory is a finished download: config,
    weights, every shard an index names, nothing `.incomplete` or
    `.zephra-revision` under it.
  - `HubCache` and `HubRepository` read both `~/.cache/huggingface/hub` layouts as
    a **read-only fallback**; nothing is ever written there.
- `ZephraQuantization` (`Packages/ZephraMLXKit`): the streaming weight packer,
  shared by every family, driven by a `QuantizationPlan`. `SnapshotBuild` runs it
  safely: a `.partial` directory renamed on success, removed on failure, a
  free-space refusal before anything is read, and `requireDisjoint` refusing a
  destination that is the source, inside it or around it (the packer empties what
  it writes to). The `pack(release:into:descriptor:plan:componentWeights:onProgress:)`
  overload is the whole of a catalog build, so each `<Family>SnapshotBuild` is a
  plan and component weights and nothing else.
- `ZephraMLX` (`Packages/ZephraMLXKit`): MLX work that is the same for every
  family. `Loading/` — `PackedSnapshotManifest` (nil when absent,
  `malformedManifest` when unreadable, never "unpacked" by mistake),
  `PackedWeightLoading` (reshapes for `.scales`, refuses packed shards with no
  manifest, casts float32 scales with `castFloatParameters`), `SafetensorsShards`.
  `Rotary/` — `RotaryFrequencies` and `rotate(_:computeDType:)`. `PixelBuffer`
  (latent to PNG or RGBA8), `TiledDecode`, `MLXRuntime` with
  `WiredLimitReservation` and `MLXInferenceRuntime` (the one `InferenceRuntime`,
  over the family's `VAETileSetting`), `GPUGeneration` (M5-class or not),
  `LatentPreview`, and `Streaming/LayerWeightStream`. A model package may depend
  on this; nothing here may depend on a model package. Vendored `ZImageKit` keeps
  its own tiled decode and preview as a `ZEPHRA-PATCH`. What the ports
  deliberately do not share is listed in `PROVENANCE.md`.
- `ZephraEngine` (`Packages/ZephraKit`): concurrency + state. Depends on
  `ZephraCore` and `ZephraSnapshot`, nothing else. Backends arrive as an injected
  `BackendRegistry` of `@Sendable` factories; this layer never names a concrete
  backend. `ModelInventory` is its one use of `ZephraSnapshot`.
- `ZephraBackendZImage`, `ZephraBackendQwenImage`, `ZephraBackendFlux2`,
  `ZephraBackendLTX2`, `ZephraBackendWan` (own packages): translate `ZephraCore` types to and from
  one family's kit. No state, no UI. Each takes `ZephraCore`, `ZephraSnapshot`,
  `ZephraQuantization` and its own kit (`ZephraMedia` too for video), and packs a
  download into the variant it loads through the protocol's `build` step. This
  keeps `Packages/ZephraKit` MLX-free.
- `Packages/ZImageKit`: vendored. Edit only with a `// ZEPHRA-PATCH: <reason>`
  comment and a matching `VENDORED.md` entry.
- `Packages/QwenImageKit`: ours, clean-room from Qwen-Image-2512's configs and
  `diffusers`, never from the GPL-3.0 `mzbac/qwen.image.swift`.
- `Packages/Flux2Kit`: ours, translated with attribution from two MIT ports and
  `diffusers`, pinned against `diffusers`; never from GPL code or the unlicensed
  `xocialize/flux2-vae-mlx-swift`.
- `Packages/LTX2Kit`: ours, from Apache-2.0 `diffusers` and `transformers`,
  pinned by dumped fixtures; nothing copied from `Lightricks/LTX-2`. The video
  lane always, the audio lane, its decoder and the vocoder for the entry with
  sound.
- `Packages/WanKit`: ours, from Apache-2.0 `diffusers` and `transformers` and
  the release's configs, pinned by dumped fixtures; no other port of Wan read.
- Each kit's `PROVENANCE.md` lists its deliberate departures; keep it true.
- `ZephraUpscaleRealESRGAN`: the Real-ESRGAN upscaler, an `ImageUpscaler` beside
  the backends, taking `ZephraMLX` and no family kit; no backend imports it.
- Nothing in the app target may import a model package or `MLX`. Only
  `Sources/Zephra/ZephraApp.swift` may import a `ZephraBackend*` or
  `ZephraUpscale*` package, to register it.
- No backend package may import another backend package.
- `Packages/ZephraLink` is the one package an iOS app links too, so what it may
  import is a short list rather than a short ban: Foundation-level frameworks,
  `ZephraCore`, `ZephraEngine` and itself. `ZephraEngine` is for
  `GenerationRecord` and `LibraryAnnotation` alone, which cross the wire as
  themselves: they are the truth inside every PNG, and a second shape of the same
  provenance is a second thing to keep in step. Its three targets stack in one
  direction only: `ZephraLinkProtocol` (the wire, no socket in it),
  `ZephraLinkTransport` (the roads, no state in it) and `ZephraLinkClient` (the
  phone's `LinkClient`, which reaches a road only through injected protocols and
  so is tested without one).

Code rules:

- One public type per file; file name matches the type name.
- Target ≤150 lines per file.
- No `*Manager`, `*Helper`, `*Utils`, or `*Service` type names. The one exception
  keeps AppKit's own name: `PromptLayoutManager` is an `NSLayoutManager`.
- Views hold at most 3 stored properties, or get split into subviews.
- `ModelCatalog` is the only static registry in the codebase. No other singletons.

Run `make lint-layers` before every commit. It fails on forbidden imports across
the layers above (`ZephraLink`'s by an allow-list rather than a ban), on any
repeating animation in either app target, on `hoverWash` used anywhere but under
`allowsHitTesting(false)`, on British spelling in user-facing string literals
(except `LibraryScope`'s persisted `"favourites"`), and on the type-name ban.
`make lint-size` is advisory only: it lists files over 150 lines. The
three-stored-properties rule is not linted; apply it by eye.

Full detail: `docs/architecture.md`.

## The companion link

`Packages/ZephraLink/Sources/ZephraLinkProtocol` is the protocol the phone talks
to this Mac over: two frame kinds, a state snapshot and its deltas, the
commands a phone may send, a Noise-style handshake on CryptoKit with an AES-GCM
channel counted per direction, the QR pairing payload, and the relay's routing
JSON. Every way the responder turns a device away before it is authenticated is
the same `LinkError.notPaired` and the same sentence, which names no Mac and does
not say whether a code is on screen: two answers there were two oracles. No transport and no interface are in it, so both ends are tested in
milliseconds without a socket — `cd Packages/ZephraLink && swift test`.

Three rules it is built on. A preview frame never rides inside a state update —
`EngineStateDTO` is scalars, and previews have a message kind of their own. A
reference picture never rides inside a request — it crosses as a blob and
`GenerationRequest` strips the bytes on the way in *and* on the way out. And a
blob's chunks are accepted in order only, because `OrderedInbox` underneath has
already made the stream ordered and a gap above it means loss or tampering;
`BlobReassembly` also holds a sender to the `byteCount` it announced, and a chunk
for a blob nothing announced is dropped rather than opening a transfer of
whatever size it likes. A transfer's clock is **idle time** (`blobIdleTimeout`,
15 s, re-armed by every chunk), since a wall clock caught neither a clip crossing
slowly nor a transfer that stopped at chunk 630; and `blobLimit` (4) counts only
the transfers nobody asked for, or the grid's next five thumbnails evict the clip
somebody is waiting on.

Every fact the Mac derives from its own state is **stamped into
`EngineStateDTO`** rather than worked out again on the phone: `isBusy`,
`isFinishing`, `acceptsGeneration` and `canQueue`. The last is the one the
phone's Generate button reads — whether a generation may be started *or queued
behind the one being rendered* — and it is `GenerationStore.acceptsQueuedGeneration`,
which `remoteAdmission` gates on, so the button and the refusal are one answer.
`EngineState` alone cannot answer it, so `EngineStateProjection`
(`ZephraLinkHost`) is the one place the DTO is built for a phone and both
projection sites go through it. A field added to the DTO after a Mac has
shipped is read with `decodeIfPresent` and a default that is what the field's
absence used to mean (`canQueue` falls back to `acceptsGeneration`);
`EngineStateDTO+Codable`, `ModelSummary+Codable` and `QueuedEntry` are the
hand-written readers. `ModelSummary.isSelectable` and `memoryNote` are the same
rule for a model: `StateSnapshotProjection` stamps both from
`ModelCatalog.fit(_:budget:)` against the Mac's own budget, the phone greys that
row and shows the note rather than judging memory itself, a `.switchModel`
naming such a model is refused `badRequest` with `MemoryFit.reason` as
`remoteAdmission` refuses a generation on it, and an older Mac's summary reads
as selectable with no note.

The channel's counter is **sent**, between the kind byte and the ciphertext —
`kind || counter || ciphertext || tag` — because the relay is one Lambda
invocation per frame and those post concurrently, so frames arrive overtaken; the
counter is the nonce, so it is authenticated for free, and a counter at or below
the release point (`replayed`) or a whole 1024-frame window beyond it
(`outOfWindow`) is dropped rather than fatal. Only a frame that does not
authenticate closes the channel. `OrderedInbox` releases opened frames in counter
order, holding an overtaken one for at most 256 frames, with a 500 ms LAN or
two-second relay window from `LinkConnection.frameReorderingHold` — one clock per
gap, re-armed whenever the release point moves, since a clock left running across
a chain of gaps that each filled in milliseconds manufactured holes out of
ordinary reordering; a gap that does
not fill inside that is loss, not reordering, and is **skipped** — the release
point jumps to the lowest counter held, the frames behind it come out, `onGap`
says so once at error on both ends, and the phone answers by sending
`Command.resync`, which the Mac answers `.ok` and a fresh snapshot; only more
than 256 frames held on one gap still ends the session. **A hole costs the one
thing it swallowed**, not every transfer and request in flight: the transfer
whose next chunk is then out of turn fails as `lost` in `LinkClient.receive`, and
a reply that never comes is closed by `requestTimeout`, which is this end's own
promise. Every `Command` is safe
to repeat, so `LinkClient.request` asks once more under a fresh
id, and the one that adds work — `enqueue` — is answered from the run that
session already queued for that `GenerationRequest.requestID`. `fetchBlob` asks
up to `blobAttempts` (4) times with `LinkBackoff` between and **from where the
last attempt got to**: `Command.fetchFile(name:fromChunk:)` names the first chunk
still wanted, written only when past zero and read as zero when absent, so a Mac
that has never heard of it sends the whole file and the phone's reassembly starts
fresh on a chunk that arrives at index 0.

`ZephraLinkTransport` is the roads under that wire. A TCP frame rides behind a
four-byte big-endian length and is capped at 1 MiB, a length past which closes
the road rather than allocating it; the listener publishes its own
`_zephra._tcp` service with the room in the TXT record, since an advertiser of
its own would have to be handed the port and kept in step with the listener's
lifetime. `RelayConnection` speaks the relay's JSON over a
`URLSessionWebSocketTask` and never reconnects itself — a reconnection is a whole
new handshake. A payload whose base64 passes 24,000 bytes goes as `RelayFragment`
slices (`m`, `i`, `n` on a `send`, which the relay forwards verbatim), because API
Gateway allows one 32 KB frame and a sealed 64 KiB chunk is about 87 KB of base64;
`RelayFragments` puts a set back together whatever order it arrives in. Every
slice waits at the road's own `RelayCadence` — 120 a second refilling a bucket of
40 — because the account's throttle is 500 a second shared by both directions of
every session and a picture's six hundred slices written back to back arrive as a
burst whose tail is refused, which is a hole in the far end's counters; the ping,
the allow-list and the join do not come through `send` and are not paced. A
message with a `message` and no `a` is API Gateway answering for itself rather
than the relay, and it is `RelayMessage.foreign`, logged and carried up
`relayErrors()` rather than failing the decode and ending the road.
`RelayListener` serves **every phone in the room**, up to the relay's
`MAX_GUESTS` (8), because the relay gives a host one socket and every frame on it
names the guest: the relay writes `from` on what arrives, `RelayGuestSession`
writes `to` on what leaves, and `RelayListener+Guests` keeps one session per
`from`, opened by whichever of the phone's first frame and its `peer joined`
comes first and ended by the `left` that names it. Frames and peer notices reach
it as one ordered `guestSignals()` stream, since a `left` that overtook the
frames behind it would end a session still being read. A host with several guests
that names none is refused `ambiguous` rather than guessing, and a signal naming
nobody — an older relay — is the room's one guest, which is what keeps either end
working against the other's previous build. The relay admits a guest only when its signing
key is on the host's allow-list: the host's `join` carries it (`allow`, at most
`RelayJoin.allowLimit`, from `CompanionHost.relayAllowList`) and an `allow`
message replaces it whenever a pairing completes or is revoked. Both messages also
carry `open`, written only when true, which `CompanionHost.relayOpen` raises while
a pairing code is on screen and drops the moment it goes: a phone pairing for the
first time is on no list, and an open room buys it a handshake the Mac still
refuses unless it can answer the code. `RelayRoad.rejoin()` reads both off the
main actor **itself**, before its first join, rather than waiting for
`watchAllowList()` to publish them: those are two tasks on two executors, and the
join that went out first carried `allow: []` — a room admitting nobody until the
`allow` message landed behind it. A `peer joined`
over a live session is that guest's own announcement arriving late and never ends
it; only a `peer left` or the road going does. A send that fails or a socket that
closes marks the road closed and finishes `frames()`, so no session is left over a
dead socket: `RelayListener` ends every guest of its road as that road stops and
`RelayRoad` ends a join's guests before the next join yields any. On the phone a `peer left` — read
through `LinkConnection.peerEvents()`, empty for a road that cannot tell — ends the
session, and `LinkClient.sessionEndings()` is what wakes `LinkReconnect` at once
rather than on its poll or the next foreground.

`ZephraLinkHost` (`Packages/ZephraKit`) is the Mac's side. `CompanionHost` is
`@MainActor @Observable`: it owns the sessions, the paired devices and the
pairing secret, and it is served `LinkListener`s rather than opening a road
itself, so a LAN listener and a relay are the same thing to it. Three wrong
answers to one code burn the secret (`pairingAttemptLimit`): the QR goes and
`pairingNote` says why; a wrong tag from a device that was reconnecting is not
counted. One
`withObservationTracking` loop over the store and the index, re-armed after each
change and coalesced by 50 ms, is what publishes the `StateDelta`s; preview
frames go out as JPEG at most ten a second, encoded off the main actor.
`CompanionSession` is one phone, with a writer task of its own so a slow link
never holds the main actor; `close` gives that writer `drainDeadline` (2 s) to
send what is queued, then closes the road and only then waits for it, because a
send to a phone that has gone never completes on its own. The plaintext stage is bounded twice, in
`CompanionHost` rather than in a listener that knows nothing of handshakes: at
most `unauthenticatedLimit` (8) connections may sit in it, and each is closed
after `handshakeDeadline` (10 s) without a channel. It **writes nothing to the Mac's own interface**:
every request goes through `GenerationStore.enqueue` and the index's own
mutations, never `settings`, `descriptor`, `index.query` or `generate(count:)`,
and an annotation edit is made with the index's `UndoManager` lifted off, since
the Edit menu belongs to the person at the keyboard. The app's side is
`Sources/Zephra/Companion/`: `LinkKeychain` (the identity and the pairings,
through `LinkSecretCache`, which reads each once a launch and rate-limits a
`lastSeen` write to once a minute — `lastSeen` is stamped at the handshake and
again when the session ends, and the Devices list says "Connected" while
`CompanionHost.isConnected` holds and draws the rest as a relative `Text` that
ticks, never a formatted string, which drew once and never again — over the store `LinkKeychainKind` settles once
a launch from this build's team identifier and logs — the data-protection
keychain for a signed build, the legacy one lazily if that is refused, and
`LinkFileStore` under `<Application Support>/Zephra/Companion` for an ad-hoc
build, which queries no keychain at all and so pairs once per machine rather than
once per rebuild), `CompanionThumbnails`, `CompanionEndpoints`, `CompanionRoads`
and `RelayRoad`. Three rules about those secrets, each of which cost a Mac its
identity once: `LinkKeychainKind.settle()` resolves which keychain this launch
uses on one thread, at the top of `startCompanion`, before either secret is read;
the migration out of the legacy keychain deletes the old item **only** where the
write landed somewhere else, which `LinkKeychainLatch` — one per store, not one
per process — is what says; and minting an identity while paired devices are
still on file is logged at error, as is an identity that cannot be read at all
(`startCompanion` says so and opens no road), since from the outside either Mac
is simply a Mac no phone can find any more.

The relay itself is in this repository now, at `Relay/link` — one Lambda file,
its README (the wire contract as the relay states it) and its tests. Nothing
imports it: it and `RelayConnection` are two implementations of one contract, and
keeping them in one repository is what lets a change to that contract be one
commit. A host's `join` supersedes any older host row in the same room: those rows
are deleted and their sockets closed, and any guest bound to them is told `peer
left` and cleared, because a Mac killed without a `$disconnect` otherwise leaves
a room holding slots for phones that are gone, and a phone bound to a socket
nobody reads, for three hours. A room holds `MAX_GUESTS` (8) guests in a string
set on the host's own row, claimed by a conditional `ADD` and refused past the cap
as `room full`; a host row from the build before it, holding one `guest`, is read
as a one-element set until the next join moves it in. `make relay-test` covers
it against fakes in seconds and `make relay-deploy` puts it up, which CI does on
every push to `main`. Terraform in the
urandom.io repository still owns the function, the table, the API and the domain,
and deliberately not the code. The API and the domain are **dual-stack** and the
domain has an AAAA alias beside its A (2026-09-13): a phone on an IPv6-only
carrier has no way to a relay with no AAAA record.

`ZephraLinkClient` is the phone's `LinkClient`: `@MainActor @Observable`, split
by concern like `GenerationStore`, holding the snapshot the deltas edit, the
newest preview and the library it has been told about. `LinkKeyStore` and
`LinkRoads` are injected, so the whole session is tested over a road that never
leaves the process; the phone reconnects on foreground and after a close on
`LinkBackoff`'s one, two, four, eight seconds, capped at thirty. Everything
sealed leaves through one `AsyncStream<Data>` on `LinkSession`, drained by a
writer task, and `send` is synchronous: a frame's nonce is its position in the
stream, so no await may sit between taking the counter and queueing the bytes.
Ending a session closes the road **before** it waits for that writer, and
`TCPConnection.close` fails every send still waiting itself: a send over a road
whose interface has gone is never completed by Network, and a phone that waited
for it never dialled again. `LinkSessionDeathTests` and `CompanionDeadRoadTests`
pin both ends.

Full detail: `docs/companion.md`.

## First launch

A Mac that has never run Zephra opens on a model chooser, not on a download.

- `WelcomeGate` (`Support/`) is the whole decision, resolved from preferences
  **synchronously in `init`** so the chooser is up before the first frame.
  `hasAnswered(in:)` is the `hasChosenModel` flag once written, and before that
  the presence of `selectedModelID`, which the root writes on every launch, so
  its absence is what a genuinely first launch looks like; the root writes `selectedModelID` only when
  the chooser goes down, never while it is up. `settle(availability:budget:current:)`
  dismisses the chooser when the survey finds a model already here that this Mac
  can hold and answers which model to continue on; a finished download this Mac
  cannot hold settles nothing, since continuing on it would open on a model
  nothing will load. Nil for a chooser already down. `dismiss()` records
  the answer (a skip is an answer); `reopen()` is the way back from
  `CanvasStateView`'s idle state.
- `WelcomeHost` (`Views/Welcome/`) shows the chooser or `RootView`. With the
  chooser up, `bootstrapFromInterface` runs only `surveyAvailability()`.
  **Nothing is fetched while the chooser is up.**
- The recommendation is `ModelCatalog.default(fitting:)`: the first entry this
  Mac holds **resident**, then the *leanest* it holds streamed, then — where nothing
  fits — the entry with the smallest `ModelDescriptor.leanestPeakBytes`.
  Streaming is what a Mac does to run a model it cannot hold, not what it should
  be started on, and every entry carries a measured `streamedPeakBytes` now, so
  without that order a 16 GB Mac would open on a 13 GB download that reads
  itself off the disk every step instead of on klein 4-bit. The streamed pass
  takes the leanest rather than the first listed for the same reason: catalog
  order says what a Mac that holds things should see first, which is the wrong
  order once nothing is held, and on an 8 GB Mac it would lead with that same
  13 GB download over klein 4-bit's 5.4 GB build. A card is marked
  recommended only when it is also selectable, so a Mac too small for everything
  in the catalog is recommended nothing and the chooser opens on no selection.
  `ZephraApp.savedModel(fitting:)` steps a persisted choice this Mac cannot hold
  onto that same answer, before the store is built, and logs the step;
  `HostMachineMemory` (`Support/`, beside `GPUMemoryBudget`) is what the guard
  reads the machine through.
- Cards are `ModelChoice.all(for:)`, every catalog entry judged once against one
  budget. Nothing is hidden by memory; a model this Mac cannot hold is disabled
  with its reason. A card's size is
  `store.availability[id]?.label`, never `transferBytes` (before the survey,
  `builtBytes` when `isPublishedPrebuilt`). Fit strings live in
  `MemoryFit+Label`; `Needs N GB` rounds up.
- `ModelPortrait` (`Support/`) holds each model's sample picture and one line of
  copy; `ModelPortraitTests` fails when a model has neither.
  `scripts/make-samples.sh MODELS_DIR` regenerates the samples (seed 42, one
  prompt) and **skips models not under `MODELS_DIR`** unless `ALLOW_DOWNLOAD=1`.
- Choosing goes through `GenerationStore.chooseFirstModel(_:)`, not
  `switchModel`, which refuses the model already chosen.
- `ZEPHRA_GENERATE_ON_LAUNCH` is inert while the chooser is up.
- `ZEPHRA_PREVIEW_STATE=welcome` photographs it; screenshot at 1200 x 840 and
  at the 880 x 560 floor.

Full detail: `docs/first-launch.md`.

## Download lifecycle

- `ModelAcquisition` in Core is injected into every backend's `ensureAvailable`.
  `ModelResolution` uses a private unloaded backend for disk checks and never
  touches the inference actor's backend or calls build/load/generate.
- `ModelDownloads` (Engine) owns request observation and foreground borrowing;
  `ModelTransfers` (Snapshot) owns network slots, preflight, compatible claims and
  per-volume space reservations: matching file sets and revisions share work,
  incompatible requests wait for the conflicting claim to release, and a claim
  over several repositories is admitted atomically so crossed dependencies
  cannot deadlock. A claim spans validation, build and resident
  use, so completion never opens a deletion gap; it is borrowed once, and
  failed or cancelled loads unload before releasing it. Foreground events carry
  an operation identity, so a superseded operation cannot change state.
- `GenerationStore.acceptsWork` (`+Admission`) is the one gate every entry point
  reads; a caller adds only its own conditions. All UI storage deletion goes
  through `GenerationStore.deleteModelStorage`, which closes admission while it
  runs. Folder changes close download admission, pause every request and await
  file closure.
- `AppLifecycle` defers Quit while `GenerationStore.shutdown` settles, then
  `LibraryIndex.shutdown` (store first, since its last save inserts into the
  index), then the runtime seam synchronises Metal.

## How a generation runs

Three types in `ZephraEngine`, one concern each, testable in seconds without
Metal:

- `GenerationStore` (`@MainActor @Observable`) is the only object the UI
  observes, split across `GenerationStore+*.swift` by concern — loading,
  admission, generation and saving (a save landing after its image was deleted
  moves it straight to Recently Deleted and never announces it saved), queue,
  batches, switching, history,
  availability, preview, tiling, reference, library, following the run,
  upscaling, interaction, downloads, the two folder changes, residency, the
  memory guard (`+MemoryGuard`).
  **Add a new concern as another extension file**, never as more lines in
  `GenerationStore.swift`.
- `InferenceActor` is the only place backend code runs. It overrides
  `unownedExecutor` with a serial `DispatchQueue`, because a generation is tens
  of seconds of synchronous Metal work that would starve the cooperative pool.
  Backends are not `Sendable`, so `@Sendable` factories go in and the backend is
  built here. Both it and the store's `run` re-check cancellation after the
  decode, so a Stop during the decode keeps nothing. A finished image carries its
  own job's batch and model (`QueuedGeneration`), and the VAE tile is set per run
  from the job's model.
- `EngineEventPump` carries progress back to the main actor: an `AsyncStream`
  buffering the newest four events and dropping the rest; `run` drains before
  returning so a later state set is never clobbered.

**Memory is checked twice, and a refusal is a sentence rather than an abort.**
`MemoryGuard` (`ZephraCore`) is asked in `GenerationStore+MemoryGuard`: once in
`+Preparation.load`, after the files are acquired and before the weights are
read, and once at the first line of `+Generation.run`, before the activity
assertion, for what this request costs on top of the weights already in. Either
answer is a `MemoryShortfall` and reaches the canvas as
`EngineError.insufficientMemory`, whose message is the shortfall's own sentence
— the two figures and one remedy. The load check answers with a **residency**
as well: `MemoryGuard.loadResidency(for:policy:tile:machine:runtime:)` asks the
policy, checks that answer against the machine, and under Automatic steps a
resident load the Mac has not the room for down to streamed rather than refusing
it, logging one line that names both figures; only a model that cannot be
streamed either is refused, and the figure it is refused with is the streamed
one, since that is the load that was going to be attempted. The remedy follows
the **mode**, not the residency: "Set Stream weights from disk to Automatic" is
said under `Never` alone, because under Automatic a refusal means even streaming
did not fit and the person is already on the setting they were being sent to.
The load check is thrown, so the catch that
already unloads and releases the lease runs; the run check fails the job and
empties the queue. What was loaded is `loadedResidency`, so a stepped-down model
is not reloaded on the next Generate; only an explicit preference change or a
model switch reloads it. Retry goes back through `startLoading`, so it re-reads the
machine rather than replaying the old verdict, and a Mac where something else
quit in the meantime loads. Both sites log what they read and what they decided,
admitted or refused, since the same refusal on two Macs is two different stories
about what was holding the memory. `canSelect(_:)` (`+Admission`) is the other
half and is the budget alone: `switchModel` drops a pick of a model this Mac
cannot hold, `startLoading` refuses one before a byte is fetched,
`select(_ item:)` keeps the current model for a picture made by one, and
`fallBackIfUnrunnable()` steps off one at launch. A paired phone hears exactly
these sentences — `staticShortfall` as `badRequest`, a live shortfall as
`.refused` — because a second wording would be a second answer.

`GenerationStore.enqueue(_:on:count:)` (`+Remote`) is the door a paired device
submits through: it queues settings and a model handed in from outside and
writes nothing back to the capsule, the canvas or the reference ticket, and
`remoteAdmission(for:settings:count:)` is what it answers a phone that cannot be
queued — `.busy`, `.refused` or `.badRequest`, each with its one sentence.

A backend returns `GeneratedMedia`: `.image(png:)` or `.video(GeneratedVideo)`
(MP4, poster PNG, frame count and rate). One return type, because only the last
step reads the kind. `GenerationSettings.frames` is 1 for a picture, pinned by
`clamp` where `frameBounds` is `1...1`, and snapped to `frameAlignment` for a
video model.

A length past one pass is a chain (`ChainPlan` in `ZephraCore`,
`GenerationStore+Chaining`): the store plans the passes before it clamps, so
`clamp` keeps a single pass's bounds and no backend is asked for more than it
runs; each pass but the last is kept in `chains`, its tail read through `clips`
and the next pass queued at the head on the next seed; the last joins them (the
source clip first when Extend Clip started it) and publishes one clip.
`QueuedGeneration.chain` is what `StepProgress` reads the passes as one bar by.
Stop drops the passes made. The planning is in Core because both apps' Duration
menus are `ClipLength` over it: a request composed anywhere but the store —
a phone's — carries the whole length through `ChainPlan.frames`, since `clamp`
alone would cut it to its first pass.

`current` is what the canvas shows, and only that (`+FollowingRun`). Generate or
a variation starts following the run; opening or selecting any other picture
stops. A result reaches `current` only while `followsRun`; otherwise it still
enters history, the wall and the library. `watchRun()` follows again and restores
the run's settings only when `capsuleHoldsPicture`. `open(_ item:)` only looks;
`select(_ item:)` adopts the picture's settings and model. `hasPicture` is
`current != nil || isShowingRun`.

`livePreview` is the newest frame of the run in flight (`GenerationPreview`,
RGBA8, at most 256 pixels an edge), kept outside `EngineState` and cleared on
every way a run ends. `GenerationProgressEvent` hand-writes `==` and
`hash(into:)` to ignore the frame. `StepTimer.annotated` rebuilds the event
field by field: **a new field there must be forwarded by name** or it never
reaches the canvas.

Each kit's `<Family>LatentPreview` pools the latent and decodes it untiled. A
loop calls the optional `onPreview` **after** the step's `MLX.eval`, never on the
last step, handing a closure rather than a frame; the backend's
`PreviewThrottle` (0.75 s) drops frames unpaid. `onProgress` stays before the
step, and `BenchStepClock` and `StepTimer` ignore updates carrying a frame. What
a loop passes is the estimate of the **finished** latent, `x - sigma * v`, not
the latent it holds — the raw latent decodes to mush on a bent schedule.

Full detail: `docs/generation.md`.

## The library

`~/Pictures/Zephra` is the default library; Settings > General can pick another
folder and optionally migrate images, sources, albums and Recently Deleted.
`AppSettings.imageLibrary()` hands the same root to the store and the index.
`GenerationStore.changeImageDirectory` gates work and drains writes while
`LibraryIndex` pauses mutations and scans; only a successful change is
persisted; migration never overwrites a destination file; Keep in Place
switches the visible library and leaves the old folder untouched. The folder
is the truth — there is no database,
and everything the app knows about an image is inside that image's own PNG, so
a file moved, renamed or copied to another Mac keeps its prompt, favourite and
tags. `ZephraEngine/Library/` is that folder read as an index, Foundation only,
so `make test` covers all of it.

- Two text chunks, two owners. `zephra:generation` is `GenerationRecord`,
  provenance written once and never edited; a PNG without it was not made here
  and is skipped. It carries the `batchID` of the press of Generate, so runs
  survive a relaunch. `zephra:library` is `LibraryAnnotation`: favourite, tags,
  albums. Anything mutable goes in the second chunk.
- `PNGTextChunks+Header` reads a chunk without reading the file (64 KiB, stop
  at the first IDAT); `PNGTextChunks+Replacing` splices one back before IDAT,
  dropping the same keyword, so repeated writes do not grow the file.
- `LibraryScan` fingerprints the directory from one `contentsOfDirectory` and
  re-reads only paths whose (mtime, size) moved. `LibraryFolderWatch` is a
  debounced `DispatchSource` that re-opens its fd when the folder is renamed
  away and back.
- `LibraryIndex` (`@MainActor @Observable`) is what the UI observes, split by
  concern like `GenerationStore`. Mutations take a set of ids, apply
  optimistically, queue onto one serial chain, and revert by re-reading the one
  file that failed — unless a newer change for that file is still `pending`,
  in which case the older write neither reverts nor reports. `LibraryQuery`
  holds scope, text and sort; `sections` are recomputed from it. The view never
  filters.
- Undo. The index, not the call sites, registers the inverse of every
  annotation edit and album change on its optional `UndoManager`
  (`LibraryIndex+Undo`), only for what actually changed. Menu names are
  "Favorite", "Tag", "Album", "New Album", "Rename Album", "Delete Album".
  Changing the images folder empties the stack. Recently Deleted stays out: a
  delete has thirty days of Put Back. No `CommandGroup` replaces `.undoRedo`,
  so the standard Edit items reach the window's manager.
- Deleting moves a file to `Recently Deleted/` with `deletedAt` and `origin` in
  that folder's manifest; a scan purges after thirty days
  (`ImageLibrary+Purge`), rechecking for every candidate that the file is ours,
  since a name can be reused. Put Back returns each to the folder it came from.
- A clip is its poster. LTX-2.5 hands back a PNG and an MP4 under the same
  stem; the library indexes the PNG (its record's `frameCount` is what says it
  is a clip) and `VideoSidecar` is the one rule for where the MP4 lives.
  Everything that moves a PNG moves the pair: `write` puts the MP4 down first
  so a scan never lists a clip whose file is not there, `restoreFromRecentlyDeleted`
  steps both around a collision under one stem, and `moveToRecentlyDeleted`,
  `discard` and migration carry both. `LibraryItem.exportURL`
  is the clip for a clip and the picture otherwise, and Export, Copy, Share,
  drag and Reveal all go through it. Upscale is offered for pictures only.
- Every span of seconds on screen is a `DurationLabel` (`ZephraCore`); a
  per-step pace is a rate and keeps its seconds.
- Export copies the file, never the bytes in memory, once a picture has one
  (`ImageExport.exportData(for:)`). Every copy goes through `ExportPlan`, so a
  file is never copied onto itself and collisions ask Keep Both, Replace or
  Cancel. `copyReplacing` writes a hidden sibling and renames into place; never
  remove-then-copy, which deleted originals exported into their own folder.
- Copy puts one picture on the pasteboard as the file URL, the PNG bytes, and
  a TIFF promised through `PasteboardImage` and made only on demand; several
  files go on as URLs alone. Plain ⌘C is `LibraryGrid`'s `onCopyCommand`, so
  Edit > Copy still means text in a field; ⇧⌘C is the named "Copy Image".
  Share uses `ShareLink` where there is a view and `SharePicker` for the menu
  item, resolved through `CommandTarget`.

Full detail: `docs/library.md`.

## The app target's shape

The app is one `Window("Zephra", id: "main")` scene, not a `WindowGroup`,
beside Settings and the two About windows. Everything a window would own is
app-wide state built once in `ZephraApp`; per-window state is a ROADMAP item.
It is one process: `Support/SingleInstance` brings a running copy forward and
exits before a window is up, because two Zephras over one library write over
each other. Exempt are launches that own neither folder — `ZEPHRA_PREVIEW_STATE`
builds, the app-hosted tests, and `ZEPHRA_FRESH_START` (`FreshStart` in
`Support/`, which gives `AppSettings.store` a throwaway suite of that
directory's own and its own `Models` and `Images` folders; the hub cache is
deliberately not redirected).

Six directories, by what a file is rather than what screen it is on:

- `Style/` — the chrome drawn on top of the shared tokens. The tokens
  themselves live in `Packages/ZephraStyle`, since the iOS companion is drawn
  from the same numbers: `ZephraChrome` holds every radius, hairline and
  height, `ZephraChrome+Washes` every colour laid over things, `Color+Palette`
  the colour sets, and `Chip`, `ModelDot`, `UpscaleBadge` and `VideoBadge` are
  nothing but those. A view reaching for a literal radius or a raw colour
  belongs in the package instead; what stays here is AppKit-bound or app-bound.
  Safelight amber means "only while the model works" and appears nowhere else.
  Radii step down by what a thing is: 16 capsule, 10 reference well, 8 card or
  thumbnail, 6 field, 5 wall square.
- `Workspace/` — which pane is up, the library query, whether the inspector is
  open: `WorkspaceSelection`, one `@Observable` injected by the root and
  persisted through `AppSettings`.
- `Support/` — caches, exports, pickers, previews, and the single homes for
  cross-cutting answers listed below.
- `Companion/` — everything the link needs that is the Mac's rather than the
  protocol's: `LinkKeychain` (the identity and the pairings) over
  `LinkSecretCache` and one of `LinkKeychainStore` or `LinkFileStore`,
  `LinkKeychainKind`, `CompanionThumbnails`,
  `CompanionEndpoints`, `CompanionRoads`, `RelayRoad` and `PairingQRCode`. The one
  place in the app target that may import `ZephraLinkTransport`, since a road is
  what it opens; `ZephraApp.swift` itself takes only `ZephraLinkHost`.
- `Update/` — everything the hand-rolled updater is, for the reason
  `Companion/` exists: `UpdateEnvironment` (the two hooks, read once at the
  root), `RunningBuild`, `UpdateEligibility`, `UpdatePhase`, `UpdateDecision`,
  `UpdateOutcome`, `UpdateChecker` (`@MainActor @Observable`, injected from
  `ZephraApp`), `UpdateInstaller`, `UpdateSignature`, `UpdateTool` and
  `Relaunch`. See "Updates" below.
- `Views/` — one subfolder per surface; the capsule, its controls, the
  commands and Settings sit at the top because they belong to no surface.

Rules in `Support/`:

- `ModalHost` is where every alert and file panel is raised, as a sheet on the
  owning window (the key window), with `runModal()` only when there is no
  window. `NSAlert` rather than `.alert` because a menu command has no view to
  hang a binding on. `ModalHost.warning` is the one place button order is
  decided: `NSAlert` gives the *first* button Return, so a three-answer question
  is reordered and a two-answer one has Return lifted off the dangerous button.
- Thumbnails: `ThumbnailKey` names a baked file, `ThumbnailFolder` bakes off
  the main thread four at a time, `ThumbnailCache` coalesces requests.
  `ImageCache` is the same shape for this session's pictures, and
  `SessionImage` the one view over it. Nothing decodes an image on the main
  actor: every door into the reference well hands `adoptReference` a closure.
- `AppSettings` is the one list of preference keys; bind with `@AppStorage` at
  the picker, read elsewhere through its helpers. `AppearanceApplier` sets the
  appearance on `NSApp` so Settings, menus and alerts follow. `AppearanceMode`
  itself is `ZephraStyle`'s, not this app's: the phone reads the same enum and
  applies it through `preferredColorScheme` instead.
- `CommandTarget` is what the file commands are about: the canvas's picture
  while the canvas shows one with a file, else the grid's focused selection,
  else nothing — no fallback from an empty selection to the picture behind it.
- `ReferenceRole` spells every string a reference picture's role changes,
  from `ModelCapabilities` (`.firstFrame`, `.startFrom`, `.reference`, in that
  order). `ModelLoadNote` is what Generate's and Animate's tooltips say a press
  costs first. `StepProgress` is the step bar's reading, so it never counts the
  slider. `SeedEntry` is the one seed parser and `SizeEntry` the one size
  parser (two numbers with anything between, fitted to the model's grid
  through `ModelCapabilities.fit`). Those three — `ReferenceRole`, `SeedEntry`
  and `SizeEntry` — are pure and live in `ZephraCore` now, not here, since the
  companion app reads the same typing; `SizeMenu` groups presets by `SizeTier`,
  leads each tier with the well's picture's shape at that tier's cost
  (`SizeChoice`), and offers Custom Size… on every model. `AppSettings.seedFormat` is how a
  seed is spelled on screen, read from the environment everywhere — nothing on
  disk follows it.
- `BackgroundNotice` is a pure function over two engine states saying what is
  worth a notification while another app is in front; `BackgroundNotices.post`
  is the one place `UNUserNotificationCenter` is touched, posts only when
  `NSApp` is inactive and the General toggle allows, and asks permission the
  first time it has something to say. A click on any of them goes through
  `AppLifecycle+Notifications`, which brings the app forward and the window with
  it: every notice is about the one window, so none of them carries a
  destination.

Rules in `Views/`:

- A view holds at most three stored properties; a fourth wants a subview.
  Animations honour Reduce Motion.
- **Nothing in the app target may run a repeating animation** — a 60 Hz
  overlay over a streamed step reset a 16 GB M4 mini's GPU and aborted the app.
  `make lint-layers` enforces it; the system spinner is fine.
- `WallSquareChrome` (hover wash, selection ring) is `allowsHitTesting(false)`,
  or every click on the wall lands on the wash; the lint keeps `hoverWash`
  out of every other file.
- `focusEffectDisabled()` on the library grid, the picker's grid and the
  viewer is the one exemption from the focus ring; an arrow key with nothing
  selected selects an end of the grid (`LibraryCursor`).
- `SettingsView` is four tabs — General, Performance, Models, Companion.
  `SettingsTab` gives the opening height;
  `minimumHeight` is one number for all four and must fit a 13-inch MacBook
  Air, since AppKit can only clamp a window that fits. `SettingsWindowFrame`
  configures the window from a zero-sized `NSView` and *observes* the
  resizable flag, putting it back whenever SwiftUI strips it. Escape does not
  close Settings.
- About is two windows (`AboutScenes`): About Zephra (`AppFacts` holds the
  strings) and Acknowledgments, which lays `THIRD_PARTY_NOTICES.md` out through
  `NoticesDocument`. There is no Settings > About. `HelpCommands` replaces the
  synthesized Help menu.
- `GenerateClickTests` sends a real mouse-down and mouse-up through an
  off-screen window hosting `CanvasPane`, idle and mid-run, and expects the
  store to take the run: ⌘⏎ goes through the menu bar and would keep working
  with the button under an overlay. `GenerateButtonFrame` (`Support/`) is the
  preference the button reports its place through, since SwiftUI's controls
  are not views AppKit can find. A press the store refuses logs which gate did.
- A keyboard shortcut has one owner, the menu bar; a button shows its chord as
  text and never declares it too. The only `.keyboardShortcut` outside the menu
  bar are a sheet's `.defaultAction` and `.cancelAction`. Return in the library
  belongs to `LibraryOpenCommand` alone. File > Stop Generating is
  `EngineState.stopCommandTitle`; File > Export… (⇧⌘E), never "Save as…".
- `ReferenceFactsRow` and the inspectors work the role out from the *record's*
  model, never the picker's, and read the thumbnail in a detached task.
- `CanvasSidebar` builds today's runs once from `SessionTimeline`
  (`ZephraEngine`, which does all the grouping); nothing in the view filters.
- `WorkspaceInspector` shows always in the library and on the canvas only
  while `GenerationStore.hasPicture`. `LibraryIndex.canvasItem(for:)` is the
  one lookup behind the canvas inspector and menu.
- `RootView` forces the toolbar background visible; panes and the inspector
  start below the strip.
- `ClipPlayerView` is AVKit's `AVPlayerView` over the MP4, looped, muted
  unless the asset itself says it has an audio track (never a record's word
  for it), never SwiftUI's `VideoPlayer` (its controls take the tuck click and
  it crashed resolving its superclass), which is why `project.yml` links
  `AVKit.framework` explicitly. Clips keep playing during a run.
- `DurationControl` shows only when `frameBounds` is a range; `StepsControl`
  hides when `stepBounds` is a single value, as guidance already does.
- Every picture wears the same right-click menu: `LibraryItemMenu` once
  indexed, `FreshImageMenu` before, `CanvasImageMenu` choosing for the canvas.
- Animate sits beside Use as Reference everywhere and both show disabled
  rather than hidden. Animate goes through `ReferenceAdoption.animate`, never
  `adopt` (which hands back an edit's source); a clip's last frame comes from
  the store's `clips` (`ClipEditing.tail`), re-encoded through
  `ReferenceImageEncoder`.
- Extend Clip sits beside Animate for clips only (`ExtendClipButton`, the two
  fresh-image surfaces, and ⌥⌘X), greyed by `ActionAvailability.extendDisabledReason`
  and titled by `CommandTarget.extendTitle`; it goes through
  `ReferenceAdoption.extend`. While the capsule carries a continuation the well's
  role is `ReferenceRole.continues` ("Continues from"), and `ImageFacts.continued`
  is the inspector's "Continues" line.
- Double-click or Return in the grid opens `LibraryViewer` in the pane
  (`\.viewLibraryItem`); "Open in Canvas" (`\.openLibraryItem`) is unchanged.
- `GenerationStore.isShowingRun` decides what the canvas shows: `LivePreviewView`
  letterboxed into the run's aspect, `RunPlaceholderView` before the first
  frame, and no menu or drag because there is no file yet.
  `EngineState.isFinishing` covers decoding and encoding after the last step;
  `StepProgress`, `FinishingNote`, the inspector and `StepTimer` all read it.
- The controls under the prompt stay live while the model works: a run carries
  its own settings, so a size, seed or strength moved mid-run is the next run's,
  and Generate queues it.
- The prompt tuck (`PromptTuckHost`) is visual only: the text view stays first
  responder under the lip, so composed input lands in the real editor, and the
  first change brings the capsule back.
- `RunningRunCard` calls `watchRun()`, which also restores the run's settings
  to the capsule after a wall square replaced them.
- `PromptTextView` is our own `NSTextView` on TextKit 1 because
  `PromptLayoutManager` must clip selection rectangles to the line's used
  width.
- Albums: `NewAlbumBar` or ⌘N creates "Untitled Album" first and renames it,
  so `AlbumEdit` has one naming path; `AlbumNameField` takes focus in `.task`
  after one `Task.yield()`. Images are filed by dragging
  `LibraryItemReference` (`io.zephra.library-item`, declared in `Info.plist`
  under `UTExportedTypeDeclarations`); a drag from the selection files the
  whole selection. ⌘N reaches the sidebar through `@Entry var newAlbum` in
  `FocusedValues`.

Full detail: `docs/app-target.md`.

## The phone

`Sources/ZephraMobile` is the iOS companion: it shows what a paired Mac is
making and asks it for more, and it renders nothing itself. No MLX, no model
folder, no library folder, no engine — every number on its screen came over the
link. It links `ZephraCore`, `ZephraLinkProtocol`, `ZephraLinkTransport`,
`ZephraLinkClient` and `ZephraStyle` and nothing else, which `make lint-layers`
enforces along with the model-package ban, the repeating-animation ban and the
US-spelling check.

- `App/`, `Support/`, `Style/`, `Views/`, laid out like the Mac target's.
  `Views/Shared/` is the one folder that is not a surface, and it holds exactly
  what two surfaces draw the same way: `ClipPlayerView`, `EntryThumbnail` and
  `StopRunButton`.
- `MobileSelection` (`Support/`) is where the phone is looking — which tab is up,
  whether the capsule is expanded and whether the prompt wants the keyboard —
  the Mac's `WorkspaceSelection` in a phone's shape and for its reason: which
  surface is up is a fact several places write, and the library's "Use as
  Reference" is one of them. Focus is there for the same reason: the collapsed
  prompt line is gone by the time `PromptEditor` exists, so the tap records the
  wish (`expandCapsule(focusingPrompt:)`) and the editor mirrors it into its own
  `@FocusState` in a `.task` after one `Task.yield()`, both ways. One tap opens
  the prompt with the keyboard up; the navigation bar's Finish Editing checkmark
  calls `collapseCapsule()` to take both down. A tap on the canvas picture drops
  focus alone. The expanded composer scrolls above the keyboard; at XXL text and
  above, the canvas and model picker also scroll, and cramped controls stack.
  A frozen launch never asks for the keyboard.
- `MobileSettings` (`Support/`) is the phone's one list of preference keys, the
  Mac's `AppSettings` in a phone's shape: `store` is `.standard` for an ordinary
  launch and a throwaway suite, emptied at launch, under a frozen preview state,
  so a screenshot or a hosted test never inherits or pollutes a person's own
  preferences. `AppearancePreference` reads its `appearance` key and applies
  `preferredColorScheme` at the root — enough on a phone's one `WindowGroup`,
  where the Mac's `AppearanceApplier` has to reach for `NSApplication.appearance`
  instead. `AppearanceMode` itself lives in `ZephraStyle`, since both apps read
  one preference and draw it their own way.
- `LinkClient` remains one authenticated Mac session. `MobileWorkspace` builds
  `HostConnections`, with one host-scoped `HostKeyStore`, client, reconnect loop
  and `LibraryCatalog` child per Mac. The root catalog combines their entries.
  Every item identity is host fingerprint plus filename; mutations and media
  fetches resolve its owner, never the watched client. Up to eight enabled Macs
  connect while active. `PairedHosts` serializes Keychain collection writes and
  fails closed on unreadable identity/pairing data. Legacy cache rows stay
  quarantined until verified against a complete host listing.
- `GenerationDispatch` owns Auto/manual destination and durable submissions;
  `HostConnections.watched` is independent presentation state. Auto uses fresh
  host offers for the exact model/settings, installed-only execution, and a
  durable host receipt before any work can be queued. Unknown outcomes stay
  assigned to their original host and are reconciled, never rerouted. New Macs
  advertise optional `multiHost`; new commands are sent only after that flag.
  Existing phones keep their legacy commands and publications.
- Shared resources are one `BonjourBrowser` with independent multicast streams,
  one `HostsPathWatch`, one outbound relay cadence, two incoming bulk transfers
  globally and one per client, and one 256 MiB aggregate blob budget. Each host
  retains independent channel counters and reconnect state. Backoff adds up to
  350 ms jitter. Only the watched modern host sends previews; the Mac's bounded
  bulk producer leaves incoming controls responsive. Background closes sessions,
  while accepted jobs keep running on the Mac.
- `cancelRun` is host/run-specific and preserves unrelated queued work. Legacy
  Stop is labeled host-wide. Explicit model loading in a host's settings may
  download/build; Auto cannot. Receipts account for pending output writes before
  declaring interruption. Details and validation: `docs/multi-host.md`.
- `PromptDraft` (`Support/`) is the phone's capsule: the settings, the model, the
  picture in the well and the seeds one press is worth, injected beside the
  client and the one object here holding something the Mac did not say. It seeds
  itself from the **first** snapshot only. Later host runs never replace the
  phone's draft automatically. `AdoptHostSettings` explicitly copies the watched
  run when requested; `DraftFollowsMac` only seeds the initial defaults.
  A press is `submission(clampedBy:randomizingSeed:)`
  (`PromptDraft+Submission`), which picks a fresh seed **before** the clamp and
  writes it back into the draft, so the capsule shows the seed that went; the
  flag is `MobileSettings.randomizeSeedEachRun`, read in `GenerateButton`'s
  action the way the Mac reads it in `generateFromInterface`, and
  `SeedLockToggle` beside the seed writes the same key. The Mac's own
  `enqueue` still randomises nothing — a request that crossed the link is one
  somebody composed — and the lock guards the press, never `follow`, which takes
  a run's whole settings as `watchRun()` does. It clamps every request through the
  Mac's own `ModelCapabilities`, rebuilt from `CapabilitiesSummary`, so the phone
  asks for what the Mac would have allowed rather than for what the Mac then
  quietly rewrites. Taking a picture into the well runs the Mac's
  size-follows-the-picture rule — on a clip model the frame becomes the
  picture's own shape at the pixel budget in force
  (`ModelCapabilities.size(matchingAspectOf:budget:)`), a picture model leaves
  the size alone — which is `useAsReference`'s rule, shared because both ends
  read the same capabilities. The one thing it does not clamp is the clip's
  length: `clamp` bounds that at one pass and the Mac plans the chain from what
  it is handed, so the request carries the whole length through
  `ChainPlan.frames`.
- The canvas is `Views/Canvas/` and `Views/Capsule/`: the run's frames while
  there is a run (`LivePreviewView`, then `RunPlaceholderView` before the first
  one, which says "Reconnecting" while the link is not live rather than
  repeating a stale phase), otherwise the newest picture or clip, with the
  capsule in the bottom safe area rather than in a sheet, which would cover the
  tab bar. A frame already here survives a drop: `LinkClient.preview` is cleared
  only by a snapshot or a delta saying the engine is not busy. Every picture
  fetch is keyed on `FetchKey` (the name and `LibraryCatalog.isLive`) and keeps
  what arrived as a `Fetched` under the name it arrived for, so a square that
  went grey during a drop fills in when the Mac comes back and one that is
  already drawn is not fetched twice. Every control
  is drawn and hidden by the capabilities the way `ControlsRow` is, `SeedEntry`
  and `SizeEntry` read what is typed, `\.seedFormat` spells a seed — the
  Settings tab's `SeedFormat`, put in the environment once by
  `SeedFormatPreference` as the Mac does it, so no view below the root binds the
  key and the sheet opens on the whole seed either way — and
  `ClipLength` is the Duration menu — both `ZephraCore`'s, so neither is a copy
  of the Mac's and the phone offers the same chained lengths — `ReferenceRole`
  captions the well, and a refusal is the Mac's own sentence under Generate
  rather than an alert.
- The well has three doors and one rule. `PhotosPicker` is the camera roll;
  `ReferencePickerSheet` and the library's own "Use as Reference" both name a
  picture the Mac already has, through `ReferenceIntent` — a file **name**, never
  bytes sent back to the machine that made them. `UseAsReferenceButton` also
  moves `MobileSelection.tab` to the canvas, which is where
  `ReferenceIntentReader` takes the name, fetches through `LibraryCatalog` and
  fills the well with `referenceOrigin` set to it. The reader watches with
  `onChange` and an unstructured task, never `.task(id:)`: taking the request
  clears the name, and a task keyed on it would cancel its own fetch. All three
  doors end at `ReferenceAdoption`, which encodes off the main actor.
- `PairingEntry.parse` is the one parser all three pairing doors go through —
  the camera (VisionKit, hidden where there is none), the paste field (always
  there), a `zephra://pair` link. Everything it throws is a `LinkError` with a
  sentence, and an expired code is refused here rather than at the far end. The
  screen sends people to **Settings > Companion** on the Mac, which is where the
  code is. The camera hands each code on **once** (`ScanGate`) and is paused
  while `client.connection.isBusy`; a second `pair(with:)` closes the first.
- The Library tab is the Mac's library, cached. `Support/Cache/` is three stores
  — `EntryStore` (a JSON file per picture under Application Support, the wire's
  own entry written back byte for byte), `ThumbnailStore` (the JPEG as it
  arrived, keyed by the Mac's own `ThumbnailKey` rule: name, modification time,
  pixels) and `FileStore` (whole pictures and clips in Caches, under a 512 MB
  `CacheBudget` that drops the least recently *read*) — behind `LibraryCatalog`,
  which reads the disk before it asks the Mac anything and follows
  `client.library` and `client.connection` in one observation loop.
  `LibraryCatalog+Media` is the **one** door whole files and thumbnails cross the
  link through, the canvas's picture and the well's reference included, so a
  picture crosses what may be a relay once for every surface and one budget sees
  it; nothing on the phone holds decoded bytes of its own, and `DecodedPicture`
  is the one line that keeps a decode off the main actor. A clip is asked for by
  its **poster's** name, which is the only name the Mac's index resolves, and
  filed beside it as the sidecar MP4 (`url(named:isVideo:)`). **That folder
  is a cache and the Mac's folder is the truth**: nothing in it is backed up,
  clearing it loses nothing, and an entry is refetched when
  `CachedEntry.isStale(against:)` says its file moved, which is exactly the
  three facts `LibraryEntry.version` is made of. The Mac sends library
  *changes* and counts the folder in its snapshot, so the entries themselves are
  **pulled**: `LinkClient+LibraryPull` pages `libraryPage` after every connect, a
  hundred at a time, one in flight, each page into `client.library` as it lands,
  retried from the same offset after `LinkBackoff` while the session is live,
  and `libraryIsComplete` is what says the last page arrived. A resync mid-pull
  carries the pull on rather than starting the folder again — the Mac answers a
  resync with a snapshot on the same session, and `LibraryPullProgress`'s total
  matching `libraryCount` is what says nothing has happened to the folder; a new
  session, or a count that moved, still pulls from nothing. A reset carries at
  most a hundred entries, so `LibraryCatalog` applies its removals only once that
  flag is up — `LibrarySync.plan` is pure and answers with them regardless. Browsing, searching, the viewer over
  anything fetched, Share and Save to Photos work offline; favoriting, tagging,
  deleting and an unfetched picture grey rather than failing on press.
- `LibraryViewer` is Photos-shaped: a lazy horizontal `ScrollView` paging the
  **whole grid** in the grid's order (the run's pictures from Today), each page
  a `ZoomingScrollView` — a nested `UIScrollView` for pinch and double-tap
  zoom, so paging and panning never fight: at fit UIKit hands the pan to the
  pager, zoomed in it scrolls the picture, and a page that stops being current
  goes back to fit. A single tap hides the chrome; the close button is a 44-pt
  target. Swipe down dismisses through
  `ViewerPullRecognizer`, one pan recognizer read in UIKit beside the pager's
  (a SwiftUI drag over the pager never sees a touch), attached to a picture's
  scroll view and to a clip's player view alike, so a clip drops and closes
  as a picture does while AVKit's taps and scrubber keep working;
  `ViewerPose.Pull` holds the rules `ViewerPoseTests` pin. Everything the
  fingers do reaches the viewer as `ViewerGestures` closures in the
  environment; `ViewerPull` is what a pull does to the screen. `ViewerCover`
  is how both surfaces present it: a clear-backed cover with the system's zoom
  transition out of the tapped cell and back into the cell of the picture the
  viewer is **now** on — the cover's item is a `ViewerOpening` (identity the
  opened picture, so paging never re-presents; `shown` reported through
  `\.viewerPaged`), `ViewerOpening.sourceID(forCell:)` makes the shown
  picture's cell the one source under that fixed id and every other cell no
  source at all (the system follows a source added or removed, not one whose
  id changes; `ViewerOpeningTests` pins it), and the grid scrolls the shown
  cell into view as the viewer pages.
- The Today tab is `snapshot.today` drawn in the Mac's order.
  `CombinedToday` owns one `ViewerCover` on its `NavigationStack`,
  never on `HostTodayRows`' transparent group: a cover on the group fans out to
  the list rows and competing zoom presentations crash UIKit. `TodayPictures`
  resolves the opened entry's host and run, preserving run order; thumbnail
  scrolling uses the same host-qualified entry IDs as the viewer.
  `RunSummary` arrives grouped, and `EngineStateDTO` already
  carries the derived facts the running card reads (`isBusy`, `isFinishing`,
  `acceptsGeneration`, `canQueue`).
- Generate never becomes Stop. `GenerateAvailability` (`Support/`) is the whole
  of what the button may do, from a live session, `acceptsWork`,
  `engine.canQueue` and a prompt — the Mac's own answers, so a press the button
  offers is a press the Mac takes; `StopRunButton` (`Views/Shared/`) appears
  *beside* it while a run is in flight rather than in its place, and a second
  press queues behind the picture being rendered the way it does on the Mac.
  `GeneratePress` (`Support/`) is where one press has got to, and the line under
  the button is the Mac's refusal or what is waiting. `CountChip` shows the
  seeds a press is worth on the collapsed capsule when it is more than one.
- `MobilePreview` is `InterfacePreview`'s shape for the phone:
  `ZEPHRA_PREVIEW_STATE=pairing|ready|generating|capsule|library|viewer|today|offline|settings`,
  Debug only, over two JSON fixtures decoded with the wire's own decoder. Every
  state but `pairing` is a `LinkClient.frozen`, which has no road under it;
  nothing reconnects behind one, the catalog is built with no roots and writes
  nothing (`viewer` alone reads drawn pictures from a temporary folder
  `MobilePreview.pictureFolder()` empties at every launch), and
  `shaped(_:for:)` is where `midRun` and `todayRuns` are chosen.
- `make build-ios`, `make run-ios PREVIEW=<state>`, `make test-ios`,
  `make screenshot-ios`. `IOS_SIM` names the simulator; CI passes what
  `scripts/ios-sim.sh` finds. There is no benchmark: the phone renders
  nothing. The one Release lane is `make archive-ios` and `make testflight`,
  which is how a build reaches a real phone.

Full detail: `docs/mobile.md`.

## Adding a model or a backend

Both cases are additive: no view and nothing in `ZephraEngine` learns the
model's name.

**A model an existing backend can already run** — one entry in that family's
`Packages/ZephraKit/Sources/ZephraCore/Model/ModelCatalog+<Family>.swift`
(Z-Image's two are in `ModelCatalog.swift`), listed in `all`. `ModelDescriptor`
carries the `ModelSource`, the download size, **five memory figures** and a
`ModelCapabilities` the interface draws itself from — size presets and bounds,
step and guidance bounds, negative prompt and seed, and for a clip model
`frameBounds`, `defaultFrames`, `frameAlignment` and `frameRate` (a range in
`frameBounds` draws the length control and says the backend answers
`GeneratedMedia.video`), and `continuationFrames` with
`defaultContinuationFrames` when the family can carry a clip on. Every number in an entry is measured; leave a comment
saying where it came from.

The five memory figures are all read off `make bench` at the entry's own default
size: `residentBytes` (the run's "live memory"), `peakBytes`, `tiledPeakBytes`
(under `ZEPHRA_VAE_TILE=64`), and — for a family that streams —
`streamedPeakBytes` and `streamedResidentBytes`, the peak and the live figure of
one `--stream --stream-depth 2` run. **The last two go together.**
`MemoryGuard` subtracts a held figure from a peak to get what a run still has to
find, and `residentBytes` is not what a streamed load holds: it is larger than
the streamed peak itself for every family measured (Z-Image 8-bit, 12.4 GB
resident against a 6.4 GB streamed peak), so reading it there floors the
transient at zero and admits a streamed run on a Mac with nothing free. A
streaming entry that leaves `streamedResidentBytes` at 0 is charged its whole
streamed peak, which refuses too much rather than too little;
`ModelCatalogTests` fails a shipped entry that does it.

**A new backend family** — four things in the app, then the tooling:

1. A `static let` on `BackendID` (a string-backed struct, so a persisted
   unknown family still decodes).
2. A package under `Packages/` whose one public type conforms to
   `ImageGenerationBackend` and whose one public entry point is a
   `BackendFactory` (see `ZImageBackendFactory`). It may import whatever it
   needs; nothing above it may.
3. Catalog entries naming that `BackendID`.
4. One line in `Sources/Zephra/ZephraApp.swift`:
   `registry.register(.yourFamily, YourBackendFactory.make(environment))`,
   plus `YourBackendFactory.runtime` in the `CombinedInferenceRuntime` list —
   `MLXInferenceRuntime` over the family's own `VAETileSetting`. No family
   writes a runtime type of its own; no kit reads an environment variable.

Then one line each in `project.yml`, `MLX_PACKAGES` and `FAMILIES` in the
`Makefile` (the lint's one family list), `QuantizeFamily` in
`Sources/ZephraQuantize` (if it packs), `BenchBackends` in `Sources/ZephraBench`,
`ModelPortrait` and `scripts/make-samples.sh` for the chooser's card, and the
import patterns in `make lint-layers`, which lint nothing they do not name.

**Choosing and loading.**

- `bootstrap` reads availability first; `fallBackIfUnrunnable()` steps a
  saved choice this Mac cannot run — gone from the disk, or more than it has the
  memory to hold — onto the first model it can run and has.
  A model that merely needs a download is kept. The chosen model is persisted
  from the composition root's `onChange` of `rememberedModel`, never by the menu.
- Selecting a picture chooses its model without loading it: `select(_ image:)`
  and `select(_ item:)` move `descriptor` and take the picture's settings
  wholesale (not clamped) while `modelAwaitsGenerate` keeps the loaded weights
  where they are, and `drain()` leaves the loaded model alone while the flag is
  up. Every explicit choice clears it: Generate, a menu pick (`switchModel`,
  which treats a pick of the waiting model as "load it now"), a variation, a
  load landing on the chosen model, `watchRun()`. `retry()` over another
  model's weights goes through `reload` so the old lease is returned. A menu
  pick cancels a square's read in flight and a picture on its way into the
  well. While the flag is up the canvas headline, window subtitle and
  background notice name `modelInUse`, and the Generate tooltip says what a
  press loads first. A picture from a dropped model keeps the current model
  and takes its schedule clamped. `DeferredModelTests`,
  `DeferredModelEdgeTests` and `AnimateTests` pin it.
- `InferenceActor` keeps one backend at a time and rebuilds it when a
  descriptor names a different family, so old weights are released before new
  ones are asked for. An unregistered family is `EngineError.noBackend`.
- `availability(of:locations:)` answers from the disk alone — never downloads,
  never disturbs what is loaded.
- Every disk-touching call takes a `ModelLocations`: one root
  (`Downloads/<org>--<repo>` for a release, `<descriptor id>` for a local
  build) plus `previous` roots as read-only fallbacks. Settings changes it
  only through `GenerationStore.changeModelDirectory(to:moving:)`, which gates
  new work and cancels and awaits pending preparation first; the low-level
  `setModelLocations(_:)` is for startup preferences and interrupts nothing.
  It is passed down, never
  read from a preference at the bottom; `InferenceActor` pins it per
  `prepare`, and only `ZephraApp.swift` knows which preferences decided it. A
  backend looks in the built variant, then `locations.downloads` under every
  root, then the hub cache, and only then downloads.

**A model whose download is not what gets loaded** implements
`build(_:at:locations:onProgress:)`, called between `ensureAvailable` and
`load` and shown as `EngineState.building`; the default returns the download
untouched. Non-zero `builtBytes` with a repository source is `isBuiltLocally`.
Availability gains `.needsDownloadAndBuild(bytes:)` and `.needsBuild`. The
variant lives at `locations.built(descriptor)`, `<models>/<descriptor.id>`.
The packer's `shouldContinue` hook makes a build stoppable between tensors.

**A built variant published ready-made**: `ModelDescriptor.mirror` names the
one `ModelCatalog.mirror` (`https://zephra-assets.urandom.io/models`), and
`isPublishedPrebuilt` is that plus `isBuiltLocally`. A backend with neither
variant nor release asks `ModelAcquisition.fetchPrebuilt` before `fetch`: it
takes the index's file list only when its `source` matches
`PackedProvenance.identity` word for word, fetches into the built directory's
`.partial` sibling through the same transfer lane as a release, checks each
file's SHA-256 before renaming it into place, and moves the directory into
`locations.built` last. `build` then finds the variant and packs nothing. The
mirror is a shortcut, never a dependency: `fetchPrebuilt` answers nil for any
reason and the backend proceeds to release and build with a log line only. An
unreadable index is `mirrorUnavailable`, permanent, so a down mirror costs one
request. `ModelDownloaderTests+Mirror` pins it.

Written once for every family: `SnapshotBuild` (`.partial` renamed on success,
removed on failure, free-space refusal before reading), `BuildTally` (progress
weighted by a dictionary of gigabytes per component), and
`LocalSnapshot.downloadedRelease(of:in:)` (app folder, then hub cache, adapters
counted). A `<Family>SnapshotBuild` is its plan and its weights, nothing else.

**A model whose build needs more than the release** lists `ModelAdapter`s on
`ModelDescriptor.adapters`, fetched into `locations.adapter(_:)` by the same
`fetch` call in one transfer. `transferBytes` is release plus adapters;
availability charges only what `ModelLocations.bytesToFetch` says is missing,
and an adapter already under any root or in the hub cache is not fetched
again. The adapter is a build input only; nothing downstream sees one.

**A model that edits** reads `GenerationSettings.referenceImage`, PNG bytes
capped at 1024 pixels an edge. `ModelCapabilities.supportsReferenceImage` is
the gate: `clamp` drops the picture for any model without it, and the well
shows only for one that has it. The picture persists in a second PNG chunk.

`ReferenceAdoption` (`Support/`) is the one door every picture enters the well
through: a library image hands back what it was itself edited from. It holds
no state; the store's `claimReference`/`adoptReference` number a choice when it
is made, not when its bytes arrive, so a slow read never lands on a later
choice. The well's three doors are the `ReferencePickerSheet` (whole library
but Recently Deleted, keyboard-walked by `ReferencePickerKeyboard` over
`LibraryCursor`), "Choose File…", and a drop of a Finder file or a
`LibraryItemReference`.

Full detail: `docs/adding-a-model.md`.

## Starting from a picture

Every model takes a reference picture, in one of three ways that look identical
from the interface:

- **Conditioning on it.** FLUX.2 klein encodes the picture to tokens placed
  after the image being made on their own rotary image index, and still walks
  the whole schedule from noise (`Flux2ReferenceConditioning`,
  `Flux2Pipeline+Denoise`). There is no "how much to keep".
- **Starting from a noised copy.** Z-Image and Qwen-Image encode the picture,
  noise it to a step's level and resume from there (SDEdit). How far down is
  `GenerationSettings.referenceStrength`.
- **Holding it as the first frame.** LTX-2.5 encodes one picture to one causal
  latent frame, holds it there and generates the clip around it; strength is
  how strongly to hold, inverted (`1 - strength`) in `LTX2RequestMapper` only.

`referenceStrength` is a plain `Double`, 1 changing nothing.
`ModelCapabilities.referenceStrengthBounds` says whether it applies: a
degenerate `1...1` means it does not (as `guidanceBounds: 0...0` means no
guidance) and `clamp` pins it. klein declares `1...1`; Z-Image and Qwen-Image
`0.1...0.9` default `0.6`; LTX-2.5 `0.0...0.9` default `0`, where 0 holds the
frame exactly. The interface decides whether to draw a slider from the range
alone, and "lower keeps more of the picture" is true of all three.

For the noised-copy models:

- Strength is "how much of the picture to throw away"; neither end is offered.
- **Strength buys a share of the steps, not a noise level.** `steps * strength`
  run, truncated and never fewer than one, entering that far from the end from
  the encoded picture mixed with that step's share of the seeded noise. A
  distilled ladder is not evenly spaced, so reading strength as a sigma sent
  most of Qwen-Image's slider to its last step and returned the picture
  untouched. Truncation rather than diffusers' ceiling keeps the top of the
  slider from discarding the picture; the product is nudged up (`1e-9` in
  `QwenImageReferenceLatents`, `1e-7` in `ReferenceLatents`) before truncating,
  safe at the slider's 0.05 granularity.
- Progress still counts the full step count, so skipped steps read as finished.
- `ZImage.ReferenceLatents` and `QwenImage.QwenImageReferenceLatents` are two
  copies on purpose: one is inside re-synced vendored code and the schedules are
  typed differently.
- `GenerationRecord.referenceStrength` records what ran: nil for no picture, 1
  when the model conditioned directly. `referenceOrigin` (settings and record)
  is the library **file name** the picture came from — nil for a chooser pick or
  a drop — cleared with the picture and dropped by `clamp` wherever it drops
  the picture; `LibraryIndex.item(named:)` looks it back up, Recently Deleted
  excluded.

Extending a clip is the fourth way, one call: `GenerationStore.extend(_:)` takes
a `ContinuationSource` (the poster's library name, the MP4 on disk or in
memory, the record), picks `ModelCatalog.continuer(for:)` — the clip's own model
when it `supportsContinuation`, else the animator — chooses it without loading
it, reads the last `defaultContinuationFrames` frames through the store's
injected `ClipEditing` under the reference ticket, and sets the capsule up with
the clip's prompt and size, the model's default length and strength, the tail's
last frame in the well and the tail behind it as
`GenerationSettings.continuation` (`ClipContinuation`: PNG frames oldest first,
the origin name, the source's frame count). Any other picture put in the well,
or none, drops the continuation. `ModelCapabilities.continuationFrames` says how
many frames a family holds (`0...0` cannot; LTX-2.5 `1...25` on its ladder,
default 9, held as `k + 1` clean latent frames with the keyframe embedding on
the first alone; Wan `1...1`, the last frame held as a first frame is), and
`clamp` drops or trims it. `LTX2RequestMapper` holds the tail over the well's
picture; `WanRequestMapper` holds its last frame. When the segment lands, `run`
joins it onto its source inside the generation (`GenerationStore+Stitching`):
the source is found by name in the images folder or Recently Deleted, the
segment's first `contextFrames` frames (the held ones, re-drawn) are dropped,
and one clip is published whose poster is the source's stripped of its chunks
and whose record says `continuedFrom`, `contextFrames` and the whole
`frameCount`; the published settings keep the continuation without its pixels
and no reference picture. A source gone from both folders fails the run and
writes nothing. `canExtend` is `acceptsWork`, a `clips` reader and an animator;
`canExtend(_ record:)` adds that the continuer draws the clip's size on its own
grid. `ExtendTests` and `ContinuationCapabilitiesTests` pin it.

Animating is one call, `GenerationStore.animate(origin:read:)`: it picks the
entry that makes clips and reads a picture (`ModelCatalog.animator(among:)`, a
capability question), chooses it without loading it, sets the clip length to
that model's default, reads the picture through the numbered choice, and keeps
the prompt. `canAnimate` is `acceptsWork` plus such a model existing. The size
follows the picture in `useAsReference`, not `animate`, so drop, picker, Use as
Reference and Animate agree: on a clip model it becomes the picture's own
shape at the pixel budget of the size in force
(`ModelCapabilities.size(matchingAspectOf:budget:)`), or the clip model's
default budget when Animate switched families; a picture model leaves its
size alone.

Each backend package decodes bytes to a `CGImage` in its own
`ReferenceImageDecoding`, duplicated because no backend may import another;
kits are handed decoded images and never touch the filesystem.

## Upscaling

Upscale 2x / 4x is Real-ESRGAN's compact network (`realesr-general-x4v3`,
BSD-3-Clause), the seam a later post-process should copy:

- `ImageUpscaler` in `ZephraCore/Upscale/` is the whole protocol: PNG in, PNG
  out at `UpscaleRequest.factor`, progress by tile, cancellation between tiles.
  Deliberately not `ImageGenerationBackend`: it needs no model loaded.
- `InferenceActor` owns the one upscaler, built lazily from the injected
  `UpscalerFactory`, resident across model switches, on the same serial queue
  as generation so two Metal jobs never overlap. `GenerationStore+Upscale`
  drives it through `EngineState.upscaling`, restores the prior state, and
  starts only from idle, ready or failed; Generate greys out meanwhile.
- The result is `<parent stem>-x<factor>.png` in the library root, carrying the
  parent's record with the new size, `upscaledFrom` and `upscaleFactor` set,
  `batchID` cleared, and the reference chunk copied verbatim; an imported
  parent gets a minimal record. Nothing rewrites the parent. Cells and squares
  wear an `UpscaleBadge` (`ZephraStyle`).
- Weights are a bundled package resource converted by
  `Tools/convert_weights.py`; `PROVENANCE.md` records the checksum. 2x is the
  4x pass followed by an exact 2x2 box mean. The picture runs through
  `TiledDecode` in 512-pixel input tiles. Alpha is dropped. Written from
  `srvgg_arch.py`, never from `xocialize/realesrgan-mlx`, which has no license.

What the upscaler leaves out is in `ROADMAP.md`.

Full detail: `docs/reference-pictures.md`.

## Build & run

Prerequisites: the full Xcode 26 `Xcode.app` selected with `xcode-select`
(the Command Line Tools cannot compile Metal), its license accepted and
`-runFirstLaunch` done, the Metal toolchain fetched once with `xcodebuild
-downloadComponent MetalToolchain`, and `xcodegen` on `PATH`. `make doctor`
checks each and prints the fix.

`Zephra.xcodeproj` is generated from `project.yml` and gitignored; never edit
it. mlx-swift's Metal kernels need `xcodebuild`: `swift build` and `swift test`
work only in the MLX-free packages, `Packages/ZephraKit`, `Packages/ZephraLink`
and `Packages/ZephraStyle`. The first Release build compiles the kernels
and takes minutes. Benchmark and make performance claims against Release only.

Makefile targets:

- `doctor` — check prerequisites; exit status is the failure count.
- `gen` — regenerate the project. `open` — generate and open in Xcode.
- `build` — generate, then `xcodebuild` the `Zephra` scheme (`CONFIG=Release`).
- `run` — build and open the app. `run-fresh` — launch as a never-run Mac
  under `ZEPHRA_FRESH_START=build/fresh` (emptied first; `FRESH_RESET=0` keeps
  it, `FRESH_DIR` relocates it); runs beside a real Zephra.
- `bench` — build and run `ZephraBench` (`ARGS=...`).
- `test` — `swift test` in `Packages/ZephraKit`, no MLX. `test-app` —
  `ZephraTests` hosted in the Debug app. `test-mlx` — every package in
  `MLX_PACKAGES` (`directory:scheme`); `test-backend` is an alias.
- `build-ios` — the companion for the simulator, Debug only, since there is
  nothing to benchmark on a phone that renders nothing. `run-ios` — that,
  booted and launched (`PREVIEW=<state>` freezes it in one). `test-ios` —
  `ZephraMobileTests` hosted in it. `screenshot-ios` — the simulator's window.
  `IOS_SIM` names the simulator; `scripts/ios-sim.sh` finds one.
- `archive-ios` — the phone's Release archive into
  `build/ZephraMobile.xcarchive`, signed automatically, stamped 0.1.0 and the
  UTC minute because App Store Connect refuses a build number it has seen.
  `testflight` — that archive exported straight up to App Store Connect as a
  TestFlight build, through `scripts/ExportOptions-testflight.plist` and
  `scripts/testflight.sh`, which sources `signing.env` for `ASC_KEY_PATH`,
  `ASC_KEY_ID` and `ASC_ISSUER_ID` and refuses by name without all three. The
  export signs **manually**, with the distribution certificate and App Store
  profile `scripts/testflight-signing.sh` issues from that same key and
  reinstates when they are missing, because Xcode's automatic signing wants a
  cloud-managed certificate the team's key is refused.
  Never an App Store submission. `testflight-status` — what App Store Connect
  did with it; `ARGS=--watch` waits rather than asking once, and
  `scripts/asc-build-status.sh` also carries `attach`, `detail` and
  `compliance`, which put a valid build in front of the internal testers over
  the same minted token. **Say which build**: `BUILD_NUMBER=<stamp>` (or
  `--build`) is what makes the watch and the attach mean the build just
  uploaded. Without one they take the newest build App Store Connect *lists*,
  and for some minutes after an upload that is the build before it — a watch
  that answers VALID at once and an attach that hands the testers the wrong
  build. `attach` refuses a build that is not VALID rather than attaching one
  nothing will install.
- `relay-test` — the link relay (`Relay/link`) against fakes for DynamoDB and
  the API Gateway management API, `node --test`, seconds and no AWS account.
  `relay-deploy` — that, then the zipped `index.mjs` up with
  `lambda:UpdateFunctionCode`, a wait for the function to settle, and a real
  socket to `wss://zephra-link.urandom.io` checking that `hello` is answered
  with a `challenge`. `RELAY_FUNCTION`, `RELAY_WSS` and `RELAY_PROFILE` (empty
  in CI, which is the OIDC role).
- `lint-layers` — the gate, before every commit. `lint-size` — advisory list
  of files over 150 lines.
- `icon` — resize the approved masters in `design/branding/zephyr/`; never
  replace the artwork with a procedural glyph. The phone's one square is cropped
  out of the master's transparent margin and drawn opaque and full bleed, since
  App Store Connect refuses an iOS icon carrying any alpha.
- `signed-build` — Release signed with a Developer ID identity (sources
  `~/Documents/Zephra Signing/signing.env`). `release` — signed, hardened,
  timestamped app plus `build/Zephra.zip` and `build/Zephra.dmg`, the DMG's
  volume icon verified. `create-dmg.sh` copies the finished image into
  `build/` with `ditto`, never `mv` (a cross-device move drops the resource
  fork and the custom-icon flag silently), and asserts both at the destination; `VERSION` and `BUILD_NUMBER` stamp the bundle. Never an
  App Store build. `notarize` — submit both packages, staple, verify.
  `notarized-release` — the two in sequence.
- `ship` — `publish-release` (`notarized-release` then `release-upload`), then
  `deploy-production`, then `release-commit`.
- `website-build` — static export of `product-mockups/`. `deploy-production`
  — that, then `scripts/deploy-website.sh` to `zephra-site-urandom-io` with a
  CloudFront invalidation; `deploy-website.yml` runs it on every push to `main`
  touching `product-mockups/`.
- `release-upload` — `scripts/publish-download.sh`: upload the DMG, copy the
  alias, verify the public download, write `product-mockups/app/release.json`.
  The site's Download button links the `Zephra-latest.dmg` alias
  (`product-mockups/app/download.ts`); the manifest only gives it the version.
- `prefetch`, `prefetch-flux2`, `prefetch-qwen`, `prefetch-ltx2`,
  `prefetch-wan` — `hf download` a release to where the app would have written
  it (`MODELS_DIR`, `QWEN_MODELS`, `LTX2_MODELS`, `WAN_MODELS`); the Qwen, LTX
  and Wan ones name files explicitly because those repositories ship more than
  the build reads.
- `quantize`, `quantize-qwen`, `quantize-flux2`, `quantize-ltx2`,
  `quantize-ltx2-audio`, `quantize-wan` — the build the app does on first
  load, by hand, into the app's models folder (`QUANT_OUT`, `QWEN_OUT`,
  `FLUX2_OUT`, `LTX2_OUT`, `LTX2_AUDIO_OUT`, `WAN_OUT`; `BITS`, `GROUP_SIZE`).
  `prefetch-ltx2` fetches the two audio files too, so one pack serves both
  LTX builds.
- `mirror` (and `mirror-<variant>`, `mirror-index`, `mirror-sync`) — build
  every packed variant into `MIRROR_DIR` laid out for the bucket with
  `index.json`, and sync to `MIRROR_BUCKET` under `MIRROR_PROFILE` with
  `aws s3 sync --delete`, files first and `index.json` last.
- `vendored-diff` — fail on any `ZImageKit` hunk without a `ZEPHRA-PATCH`.
- `logs` — `log stream` for `io.zephra`. `screenshot` — capture the window by
  id (`WINDOW=<title>` for a Settings tab). `clean`.

Shipping, until further notice: no version bumps. Every build is `0.1.0` and
the build number is the UTC minute the build started (`YYYYMMDDHHMM`), so the
file is `Zephra-0.1.0-<stamp>.dmg` under an immutable name; the upload also
copies it to `releases/Zephra-latest.dmg` (short cache, invalidated) with
`releases/latest.json` naming the build and its SHA-256. The upload refuses a
name that already exists with other bytes. Superseded builds are deleted by
hand, never in `ship`: the bucket has no versioning. `mirror-sync` runs with a
ship and not before, because the shipped app matches the mirror index's
`source` to its own descriptor word for word. `release-commit` stages the one
manifest path and nothing else, commits it naming the build, and pushes the
current branch; a re-run with nothing changed stops rather than committing.

Pull requests run the fast Gates job, including ZephraLink tests, without any
publication jobs. Every publication job requires a non-PR event on main.

**CI ships main.** `.github/workflows/release.yml` runs on every push to `main`
and does the whole of a ship with no manual step: `gate`, then `mac-release`
(`make publish-release`), `ios-testflight` (`make testflight`, the watch and the
attach) and `relay-deploy` (`make relay-deploy`) in parallel, then
`release-commit`. Every step is a Makefile target, so the local path and the CI
path are one path. The version is still `0.1.0` and the build number is still the
UTC minute — computed once in `gate` and handed to the Mac and the phone alike,
so one push is one build number everywhere. Two tiers of gate: every push runs
`doctor`, `lint-layers`, `test`, the ZephraLink package tests, `relay-test` and `test-ios`; `test-app` and
`test-mlx` are an hour of Metal and run only under `workflow_dispatch` with
`full_gates: true` — locally before every merge as always. A push touching only
`docs/**`, any `.md`, or `product-mockups/**` ships nothing, and
`release-commit`'s message carries `[skip ci]`, so a release cannot start
another. The website is `deploy-website.yml`'s, on every push touching
`product-mockups/`, and a release needs no site deploy. `make ship` remains the
by-hand path and is unchanged.

`ZephraQuantize` safety: `--family` is required with no default; `BITS` other
than 4 is refused unless `--out` is explicit, since every default name says
`4bit`; an `--out` that is the source, inside it or around it is refused (the
packer empties what it writes to); it builds into a sibling `.partial` renamed
on success and removed on ^C; an `--out` named for a catalog entry checks the
volume for that entry's `builtBytes` first and writes the
`.zephra-packed-source` stamp the app checks, so a build by hand is one the app
accepts; and Qwen-Image refuses to build without `--lora`
(`QuantizeFamily.requiresAdapter`) — `--no-lora` needs an `--out` other than the
catalog's.

## Updates

Zephra updates itself, from the feed `scripts/publish-download.sh` already
writes. No Sparkle and no publish-path change: the ship is unchanged, and the
updater reads what a ship leaves behind.

- The feed is `https://zephra-assets.urandom.io/releases/latest.json`, four
  fields — `url` (the immutable stamped DMG), `version`, `build`, `sha256` —
  cached for a minute and revalidated. `UpdateFeed` reads it over an ephemeral
  session with no cache at all, `Cache-Control: no-cache`, a 15 s timeout and
  `waitsForConnectivity` off; offline is an answer, not a wait.
- **Newer is the build compared as an integer, never the version.** Every build
  is `0.1.0`, so the version orders nothing; the build is the UTC minute
  (`YYYYMMDDHHMM`). `ReleaseManifest.isNewer(than:)` refuses anything that is
  not twelve ASCII digits at either end, so `project.yml`'s own `1` never
  updates.
- `UpdateEligibility` is the safety gate, in order: a translocated copy (its
  path carries `/AppTranslocation/`, so it is running from a disk image and
  nothing near it may be written), a build that is not a stamp (every
  development build), then a copy outside `/Applications` and `~/Applications`
  or nested inside another app's bundle. Only the last is lifted, and only for
  a launch driving its own feed through the Debug hooks.
- **Nothing is fetched before the click.** A check that finds a release puts it
  on the banner and stops there. `UpdateDownload` then streams the image
  through the same `ChunkedDownload` a model transfer uses, into
  `<Application Support>/Zephra/Updates/<build>.dmg.incomplete`, and renames it
  only once its SHA-256 is the published one. No resume: a release is one file
  and a minute, so a broken transfer starts over (`ROADMAP`).
- **Verify before copy, on the mounted image.** `hdiutil attach -nobrowse
  -readonly -noautoopen` on a mount point of ours, then `codesign --verify
  --deep --strict`, `spctl --assess --type execute` (Gatekeeper's own verdict,
  which honours the stapled ticket with no network), the team identifier, and
  the `Info.plist`'s identifier and `CFBundleVersion` against the manifest
  (`UpdateInstaller.acceptance`, pure and tested). `stapler` is Xcode's, not
  macOS's, so it is never run in the app. A `Zephra.app` on the image that is a
  symbolic link is refused before any of them, since every one of those tools
  would follow it.
- **The team is `AppFacts.teamIdentifier`, a constant, and the check fails
  closed.** `spctl` passes any notarized Developer ID app, so an app from
  another team carrying Zephra's identifier and build would clear it; the team
  identifier is what closes that, and it is compared against a written-down
  literal rather than against whatever `SecCodeCopySelf` says this process is.
  Every way that call can answer nothing looks like "ad-hoc", and a check that
  stands itself down when it cannot run is not a check. A candidate with no
  readable team is refused; only a Debug launch driving its own feed
  (`UpdateEnvironment.isOverridden`) may take an unsigned one, and Release
  never can, since the hooks are `#if DEBUG`.
- **Rename aside, then `ditto`.** The running bundle becomes
  `Zephra.previous.app` — a running bundle may be renamed, since its executable
  is mapped by inode — and `ditto` copies the new one into its place, because
  it carries extended attributes, resource forks and symbolic links that a
  plain copy drops. The copy is `codesign --verify`ed, and any failure removes
  it and moves the original back — and *checks that the move landed*, since a
  partial copy that will not delete leaves a Mac with no `Zephra.app` at all;
  that one case names the aside path so the person can rename it themselves.
  **Quit waits for that window.** `AppLifecycle` consults an injected
  `isInstalling` closure through `QuitReply`, so a Command Q between the rename
  and the end of `ditto` is deferred rather than leaving only
  `Zephra.previous.app`. A parent folder that cannot be written to is
  refused before anything moves, with the drag-it-yourself sentence and Show in
  Finder on the verified image. No quarantine handling:
  `LSFileQuarantineEnabled` is unset, a mounted image's files carry no such
  attribute, and `spctl` already assessed these bytes.
- **Quit through the normal path.** `Relaunch.afterExit` spawns
  `/bin/sh -c 'while /bin/kill -0 <pid>; do /bin/sleep 0.2; done; exec
  /usr/bin/open -n "<bundle>"'` and has the **run loop** call
  `NSApp.terminate(_:)` (`perform(_:with:afterDelay:)`), never `exit()` and
  never `terminate` from the main-actor task itself: a deferred reply spins a
  nested event loop inside that call, and the shutdown that answers it is a
  main-actor task, so a job that calls `terminate` directly holds the one
  executor the reply needs and the app never quits — which is exactly what the
  first shipped updater did. Through the run loop, `AppLifecycle` runs
  `GenerationStore.shutdown`, `LibraryIndex.shutdown` and the Metal synchronize. The helper has to wait for
  the pid: a copy opened while this one lives is stood down at once by
  `SingleInstance.yieldToRunningCopy`. `UpdateChecker.start()` sweeps
  `Zephra.previous.app` and empties `Updates/` at the next launch.
- `UpdateChecker` is `@MainActor @Observable`, built in `ZephraApp` and handed
  down; never a singleton. It checks ten seconds after launch and every six
  hours, and `start()` returns at once for a frozen `ZEPHRA_PREVIEW_STATE`
  build, for a copy `UpdateEligibility` refuses, and while Settings > General's
  "Check for new versions of Zephra automatically" is off — **a preview build
  reaches no network at all**, the rule `startCompanion` follows, and
  `checkNow` refuses there too, so the menu item cannot go round it. The
  preference is re-read at every tick, so switching it off stops the checking
  rather than only the next launch's.
- The banner is `RootView`'s `.safeAreaInset(edge: .top)`, a `ZephraChrome.barHeight`
  strip with a determinate `ProgressView` and no repeating animation; Update Now
  is greyed by `UpdateDecision.installBlockedReason` (downloading, building,
  generating, upscaling, cancelling, or a transfer in flight) with the reason as
  its tooltip. Cancel stands beside the bar while the bytes come down, and only
  there: the download session does not wait for connectivity, so a Mac off the
  network fails with a sentence rather than sitting on a bar at zero, and once
  the swap has started there is nothing safe to stop. Later snoozes the build **for the session only**: with no version
  bumps, a persisted skip is a skip of every later ship.
- Zephra > Check for Updates… reports through `ModalHost.report`, except a
  release found, which brings the app forward to the banner already saying so.
  A check nobody asked for reports nothing. A published release is announced by
  `BackgroundNotice.updateAvailable` through the existing `BackgroundNotices.post`,
  so it honours `!NSApp.isActive` and the one General toggle.
- The two hooks are in "Debugging hooks"; `ZEPHRA_PREVIEW_STATE=update`
  photographs the banner.

Full detail: `docs/build-and-release.md`.

## Tests

Swift Testing (`@Suite`/`@Test`), never XCTest. Name suites and tests as
sentences about behaviour.

- `make test` — `ZephraCoreTests`, `ZephraSnapshotTests`, `ZephraEngineTests`,
  `ZephraMediaTests`; seconds, no Metal. Anything testable without Metal
  belongs here. `CompanionHost`'s own suites are in `ZephraEngineTests`, not
  beside the host: what they drive is `EngineTestBed` and `MockBackend`.
- `cd Packages/ZephraLink && swift test` — the wire, the roads and the phone's
  client, over doubles rather than a socket; seconds, and not in `make test`,
  which stays inside `Packages/ZephraKit`.
- `make test-ios` — `ZephraMobileTests`, hosted in the companion on the
  simulator `IOS_SIM` names. Seconds once the app is built; the first build is
  minutes, since `ZephraCore` and the protocol compile for the simulator from
  scratch.
- `make test-app` — `Tests/ZephraTests`, hosted in the Debug app
  (`@testable import Zephra`; Release turns testability off). Pure interface
  logic, nothing that needs a window. The scheme sets
  `ZEPHRA_PREVIEW_STATE=ready`. Never write a media file with `AVAssetWriter`
  inside the host, which leaves the host unable to exit; a test that needs a
  clip belongs in `ZephraMediaTests`, whose committed fixture
  (`Fixtures/red-then-blue.mp4`) and in-process writes are fine under
  `swift test`.
- `make test-mlx` — the MLX packages, through `xcodebuild`, each package's
  suites run serially (`-parallel-testing-enabled NO`): in parallel, whichever
  autoencoder parity suite lands beside a heavy one reads a tensor back off by
  whole units, and the same suite passes alone.
- One suite: `cd Packages/ZephraKit && swift test --filter ModelSwap`. The
  filter is a regex over *type* names, not `@Suite` display names. For an MLX
  package: `xcodebuild test -scheme <Package> -destination 'platform=macOS'
  -skipPackagePluginValidation -only-testing:<Tests>/<Suite>` (`ZephraMLXKit`'s
  scheme is `ZephraMLXKit-Package`). For the app: the `test-app` line with
  `-only-testing:ZephraTests/<Suite>`.
- `QwenImageKit`, `Flux2Kit` and `LTX2Kit` check the ports against tensors
  dumped from `diffusers`/`transformers` by each kit's
  `Tools/dump_reference.py`, which pins the reference versions in
  `Fixtures/versions.json`. Adding a component means adding its fixture in the
  same commit; the clean-room claim in `PROVENANCE.md` rests on it. Each kit's
  `WeightKeyCoverageTests` checks every published tensor against the module
  trees. `ZephraMLXTests` pins the shared pieces.
- No test loads model weights. A few kit suites read a real snapshot's
  config, tokenizer and safetensors headers through `SnapshotUnderTest`
  (`ZephraTestSupport`), looking in order at `QWEN_IMAGE_SNAPSHOT`,
  `FLUX2_KLEIN_SNAPSHOT` or `LTX2_SNAPSHOT`, the app's models folder, then a
  hub cache holding exactly one snapshot; header tests gate on `hasRelease`.
  Under `xcodebuild test` spell the variable `TEST_RUNNER_<NAME>`.
- Engine tests drive `MockBackend` through `MockBackendControl`, a
  lock-protected dial a `@Sendable` factory closes over, inside an
  `EngineTestBed` with a throwaway output folder; `ZephraCoreTests` uses the
  smaller `StubBackend`.

Full detail: `docs/build-and-release.md`.

## Model weights

Every measured figure — download, built and resident sizes, peaks, step times,
streaming rates, and which of those is owed a rerun — is in `BENCHMARKS.md`.
This section is the rules those figures decide and what is load-bearing about
each family.

- Weights live in the folder Settings > Models names
  (`~/Library/Application Support/Zephra/Models` by default):
  `Downloads/<org>--<repo>` for a release, `<descriptor id>` for a variant
  packed here. `make prefetch` writes exactly what the app would; an
  interrupted prefetch is finished by the app, which then removes the
  `.incomplete` partials `hf` left under `.cache/huggingface/download`.
- The hub cache is read if it holds a release, never written; `HF_HOME` and
  `HF_HUB_CACHE` do not decide where a download goes.
- Every catalog repository is public and ungated. `ModelDownloader` never sets
  an `Authorization` header, whatever `HF_TOKEN` or the `hf` token files hold.
  No metered-network refusal: the size is on screen before the download starts.
- `DownloadRetry` (`ZephraCore`) retries five times with a doubling pause,
  each file resuming from its `.incomplete` bytes; only a missing repository or
  file, or a 4xx that is not a timeout or rate limit, stops it early.
- Settings > Models (`ModelStorage` in `ZephraSnapshot`, observed through
  `ModelInventory`) lists every directory the catalog's models occupy, with its
  `origin`; a release two variants pack from is one row, a stopped download and
  an adapter are rows of their own, and a directory the loaded model is using
  cannot be deleted. Changing the folder offers Move Models, Keep in Place, or
  Cancel: Keep retains previous roots as read-only fallbacks; Move unloads,
  copies into staging, verifies bytes, publishes, then removes originals, and
  refuses on a collision rather than overwrite. Neither touches the image
  library or the hub cache, and generation, queued work, upscaling and
  deletion cannot race a migration.

### Z-Image-Turbo: `z-image-turbo-8bit`, `z-image-turbo-4bit`

- The 8-bit entry (`mzbac/Z-Image-Turbo-8bit`) is the one model loaded exactly
  as downloaded. Always pass the model explicitly into the vendored pipeline:
  its own default is the 32.9 GB bf16 repo, a build source Zephra never loads.
- The 4-bit entry is packed on the user's Mac from `Tongyi-MAI/Z-Image-Turbo`
  on first load (`make quantize` by hand), group size 64. A 16 GB Mac is
  offered it; 768 and 1024 fit once the decode is tiled.
- The packed tensor set must match the reference eight-bit export exactly: the
  loader decides what is quantized by a `.scales` key, so packing a tensor the
  reference left alone breaks the module tree. `QuantizableWeight` is the rule,
  `QuantizableWeightTests` pins it.
- Manifest layer names are bare module paths (`layers.0.attention.to_q`), not
  component-prefixed as the reference writes them; bare names are what make
  mixed precision work.
- Scales and biases are written float32; the transformer's
  `castFloatParameters` patch makes them bfloat16 at load. That patch
  **evaluates nothing** now: the cast has to stay lazy for a stream to capture
  it, and `ZImageResidentParameters.eval` is the one place a load is read in,
  last of all and after the streams are attached.
- Both entries stream: the transformer's three block stacks (`layers`,
  `noise_refiner`, `context_refiner`) and the text encoder's 36 layers, through
  `loadModel(modelSpec:streaming:)` and `ZImageStreaming(depth:)`. The
  checkpoint keys are bare in both layouts; the encoder's stack is the one place
  the module tree and the shards differ (`encoder.layers` against
  `model.layers`), and `ZImageResidentParameters` holds both spellings. The
  encoder is not cast at load, so a streamed encode is bit for bit a resident
  one. `QwenEncoder.forwardCausal` — the prompt enhancer, which Zephra never
  enables — keeps its plain loop.
- A 16 GB Mac is offered the 8-bit entry now, "Streams from disk", and it is
  **not** what that Mac is started on: `default(fitting:)` prefers klein 4-bit,
  which fits resident. Streamed at 1024 it is minutes a picture there.

### Qwen-Image-2512: `qwen-image-2512-4bit`

- Packed on the user's Mac from the bf16 release with the
  `lightx2v/Qwen-Image-2512-Lightning` adapter merged as it packs; the runtime
  never sees an adapter. `make quantize-qwen` is the same build by hand;
  `QWEN_SOURCE`, `QWEN_LORA` and `QWEN_IMAGE_SNAPSHOT` point at the copy on
  `/Volumes/ExternalStorage/Models`, or set `MODELS_DIR` there instead.
- **The adapter is not optional.** The base model wants fifty steps and real
  guidance; the merged weights were distilled to four steps without either,
  which is why the entry reads `guidanceBounds: 0...0` and
  `supportsNegativePrompt: false`. A build without it is soft and hazy.
- The modulation layers stay at eight bits while the rest goes to four: they
  decide how strongly every other layer responds, and four-bit builds that pack
  them lose coherent structure.
- The vision tower and `lm_head` are neither ported nor loaded; the pipeline
  never supplies pixels. `WeightKeyCoverageTests` asserts it.
- The autoencoder's encoder is loaded unconditionally, for starting from a
  noised copy; a lazily rebuilt module would have to keep the shard mapped.

### Streaming the weights

`LayerWeightStream` (`ZephraMLX`) runs a model on a GPU that cannot hold it by
reading it from disk every step. Every family does it now — Qwen-Image, LTX-2.5,
Wan, Z-Image and klein — so every catalog entry carries a measured
`streamedPeakBytes` and no model is ever loaded resident and left to page.
MLX reads a shard's
arrays with `pread` only when evaluated and has no mmap path, so the stream
keeps, per layer, the very `MLXArray` objects the forward pass reads. One pass:
open fresh lazy nodes for every tensor; `asyncEval` the first `depth` layers;
then for each layer run its work, `asyncEval` its outputs, wait for the layer
before it, `asyncEval` the layer `depth` ahead, and hand each of the layer's
arrays a fresh node from the next pass with `_updateInternal`, cast back to the
dtype the tree held at capture.

Three choices are load-bearing:

- The cast back keeps a load-time cast alive: the packer's scales are float32
  on disk and MLX's quantized matmul takes its output dtype from them, so a raw
  node would widen every block to float32 from the second step. The load order
  is fixed: fill the module tree, cast its float32 parameters to the activation
  dtype, attach the streams, and only then evaluate the resident parameters —
  evaluating a stack before its stream is attached reads the whole model in.
  The autoencoder stays float32 on purpose.
- Outputs are committed per layer because an unevaluated graph holds every
  layer's weights as inputs; one eval per step would read most of the model
  before any of it ran.
- Waiting on the layer before bounds the window at `depth + 2` layers: MLX
  allocates a buffer when a read is queued, not when bytes arrive.

Block stacks stream; embeddings, projections, norms and autoencoders stay
resident. A streamed step is one read of the transformer, so
`Task.checkCancellation()` sits between blocks. A streamed image is byte for
byte the resident one. `Packages/ZImageKit` takes `ZephraMLX` in its manifest
for this — the one Zephra dependency the vendored kit has, logged under
"Manifest changes" in `VENDORED.md`, because a copy of the stream would not
report into the one `WeightStreamMeter` the bench and the Performance tab read.

What decides it: `ModelDescriptor.streamedPeakBytes` (zero only for a family
added later that has not learned to stream, which then loads resident under
every mode); `MemoryFit` tries it after `fitsTiled` and answers `fitsStreamed`;
`WeightResidencyPolicy` turns the Performance preference and
the budget into a `WeightResidency` for the load, streamed under Automatic
whenever the model does not fit resident, `.tight` included. That answer is
**static**, from a budget that does not move, because the menu's note and the
Performance tab are catalog facts; `MemoryGuard.loadResidency` adds the live
half at the load and steps a resident answer down to streamed under Automatic
when the Mac has not the room free for it that minute. `MemoryFit` is the
catalog question — could this Mac ever hold it — and `ModelCatalog.default(fitting:)`
prefers a **resident** fit over a streamed one, since streaming is the way to run
a model this Mac cannot hold and not the way to start it. What the Mac has free
*now* is `MemoryGuard`'s, over `HostMachineMemory`'s reading and the runtime's
own `memorySnapshot()`; `InferenceActor.unload()` calls `releaseCache()` last,
after the backend is dropped, because MLX keeps a released buffer for reuse and
those gigabytes are charged to this process while the next model is measured.
`InferenceActor` pins the residency
beside `loadedPath`, so asking for the same model the other way is a reload.
A family's two variants share one streamed peak, measured: the stream leaves the
same resident tensors behind whichever width the blocks pack at, and the peak is
those plus the tiled decode and the depth-2 window. The width is paid in bytes
read per step, which is time. What a streamed load *holds* is
`ModelDescriptor.streamedResidentBytes`, measured beside the peak, and it is the
held figure `MemoryGuard.transientBytes` subtracts under `.streamed` — never
`residentBytes`, which is larger than the streamed peak for every family and
would charge a streamed run nothing at all.
`MemoryBudget` (`ZephraCore`) is Metal's `recommendedMaxWorkingSetSize`, read
once at launch (`GPUMemoryBudget`) and handed down; MLX's memory and wired
limits are set from it. Settings > Performance shows the
`sudo sysctl -w iogpu.wired_limit_mb=N` command with a Copy button when raising
it would make the chosen model run; the app never runs `sudo`. A RAM-only
budget (tests, GPU-less builds) assumes four fifths.

### FLUX.2 klein 4B: `flux2-klein-4b-4bit`, `flux2-klein-4b-8bit`

- One download, the bf16 release without the root single-file checkpoint;
  both variants pack from it on first load (`make quantize-flux2`), and the
  release is kept because the other variant packs from it.
- The text encoder is Qwen3-4B; only its first 27 layers are built, loaded or
  packed (`layersNeeded`), and the three shared modulation linears are held
  whole. `WeightKeyCoverageTests` pins the leftover set.
- Three stacks stream under `WeightResidency.streamed`: the five dual-stream
  blocks, the twenty single-stream ones and the encoder's 27 layers, attached
  per component in `Flux2Pipeline+Loading` in the order `LayerWeightStream`
  demands — load, cast, attach, evaluate what is left. The encoder's taps at
  layers 9, 18 and 27 are counted **inside** the stream's closure, since `run`
  hands back the layer and not its index, and a tap read off the wrong layer is
  the one thing about this stack a plausible picture of the wrong prompt would
  not give away.
- The stream is bfloat16 except on an M5-class GPU, where
  `Flux2ActivationPrecision` (`ZephraBackendFlux2`) runs it float32 for the
  mlx-swift split-K bug; `ZEPHRA_DIT_DTYPE` overrides either way, the kit reads
  no environment variable, and the gate is unverified on real hardware. The
  packer's scales and a reference's tokens are both cast to the stream's dtype
  at load and at encode, or every activation widens to float32.
- Two deliberate departures, listed in `PROVENANCE.md`: the pipeline's
  empirical shift, not the scheduler config's; and the config's 1e-6 qk-norm
  epsilon, not the ports' 1e-5.
- An edit fits the reference to at most a megapixel, trims to multiples of 16,
  and places its tokens after the image on rotary image index 10; the shift
  counts only the image being made.

### LTX-2.5: `ltx-2.5-distilled-4bit`, `ltx-2.5-distilled-audio-4bit`

- Two entries from one pack. The first runs the official `audio=None` forward,
  video only, for Macs without the memory for the lane; its pictures differ
  from the audio-video model's, since that forward drops the audio-to-video
  term. The second, "4-bit, with sound", runs the whole model: the audio lane
  in every block, the audio connector, the audio autoencoder's decoder and the
  vocoder, and its MP4 carries a stereo AAC track at 48 kHz.
  `ModelCapabilities.producesAudio` is the one flag: the plan, the snapshot
  checks, the load and the player's mute all read it or the file. Listed last
  in `all`, so Animate still picks Wan.
- Lightricks' repositories are gated and Zephra sends no token, so the catalog
  names the ungated `mlx-community/ltx-2.5-mlx` pack: six files for the video
  entry (distilled transformer, connector, Gemma 4 encoder with tokenizer,
  video decoder, video encoder, spatial upsampler), the audio autoencoder and
  vocoder added for the entry with sound, the dev files omitted by pattern.
  The mirror is the path users take.
- The audio lane (`LTX2AudioLane` in each block, `LTX2AudioHead` on the
  transformer, both nil on a video-only tree): per block, video self-attention,
  audio self-attention, both text cross-attentions, then the two gated
  cross-modal attentions on five-row tables (scale, shift, scale, shift, gate)
  with the queries rotated on their own time table and the keys on the other
  lane's (`keyRotary`), then both feed-forwards. The audio adaLN heads and the
  four `av_ca_*` conditioners read the **scalar** sigma always, even over a
  held frame. Audio latents are `[1, L, 128]` float32, L = round(frames / 24 x
  25), positioned in seconds over a 20-second rotary; both lanes walk one
  ladder, the audio re-noised at the second stage's top the way
  `pipeline_ltx2_condition.py` does, with noise keys of its own (`seed +
  30000`, `+ 50000` per step, `+ 40000` at the second stage). Decode is `LTX2AudioDecoder` (2D causal convolutions, float32)
  then `LTX2Vocoder`, BigVGAN-v2 twice (16 kHz, then the bandwidth extender
  to 48 kHz) written from diffusers' `vocoder.py`; its depthwise anti-aliasing
  filters run as single-channel convolutions over `[B*C, T, 1]`.
- Pack keys for the lane nest under `audio.` in the module tree
  (`LTX2TransformerWeights.sanitized(_:audio:)`); `WeightKeyCoverageTests`
  claims every one of the 4091 transformer and 262 connector keys for the
  audio variant and keeps `audioOmitted` in step with `audioMarkers` for the
  video one.
- The encoder is causal in time, so one picture encodes to one latent frame
  held as the clip's first. The transformer's video adaLN and output head see a
  **per-token** sigma, `sigma * (1 - mask)`, while the prompt's adaLN keeps the
  scalar; `LTX2FirstFrameConditioning` blends the picture into the
  finished-latent estimate, never into the velocity, and puts a fully held frame
  back after each step.
- The strength runs the other way and `LTX2RequestMapper` is the one place it
  is inverted (`1 - strength`); bounds are `0.0...0.9`, default 0, so the
  default holds the frame exactly and 1 is never offered.
- `QuantizedComponent.sourceFiles` and `sourceDirectory` read the pack's
  layout; keys keep its prefixes (`transformer.`, `connector.`, `vae_decoder.`,
  `vae_encoder.`, `model.language_model.`). `LTX2QuantizationPlan` packs both
  stacks at four bits, the two embeddings at eight, holds conditioning,
  modulation tables, gates and norms whole, and omits the audio side through
  `audioOmitted` unless `plan(audio:)` asks for the lane, when the lane's
  blocks pack at four bits, its ends, adaLN heads and the four conditioners
  stay whole, the audio aggregate projection goes to eight like the video one,
  and `audio_vae` (decoder half) and `vocoder` (inverse basis left out) are
  copied whole. The aggregate projections' scales stay float32: 188160 products
  summed in bfloat16 lose the prompt.
- `LTX2Tokenizer` is Zephra's own byte-pair encoder keyed by UTF-8 bytes,
  pinned against Hugging Face's ids; it prepends BOS (id 2), truncates keeping
  the front, and left-pads to 1024 with id 0.
- Both 48-layer stacks stream under `WeightResidency.streamed`; resident, the
  transformer evaluates every eight blocks (`blocksPerEval`) to stay under the
  watchdog. The decoder has no tiled path, so `tiledPeakBytes` is the plain
  peak. The warm-up run costs a full eight-step, nine-frame clip plus an MP4
  encode.
- **Two stages** (`LTX2StagePlan`, in the backend): a frame whose short edge is
  512 or more runs the eight-step ladder
  at half the size, doubles the latent through the pack's spatial upsampler
  (`LTX2LatentUpsampler`, the `upsampler` component, copied whole), noises it to
  the second ladder's top and walks `LTX2DistilledSchedule.secondStage` (three
  steps) at the full size; the run reports eleven steps as one count. A held
  first frame is encoded at each size. The entry aligns sizes to 64 rather than
  the autoencoder's 32 so every preset, fitted and typed size halves onto the
  grid and takes the path. `ZEPHRA_VIDEO_STAGES=1|2` forces either for one
  launch. A variant packed without `upsampler` and the upscaler's config reads
  as unbuilt and is rebuilt whole; a mirror user re-fetches the whole variant.

### Wan 2.2 TI2V-5B: `wan-2.2-ti2v-5b-4bit`

- The quick clip family: FastVideo's `FastWan2.2-TI2V-5B-FullAttn-Diffusers`,
  Apache-2.0, ungated, in Diffusers layout; the catalog names it directly. Three
  distribution-matched steps at timesteps 1000, 757 and 522 on a grid shifted by
  8 (`WanDistilledSchedule`), no guidance, no negative prompt; frames are
  `1 + 4k` at 24 fps; sizes are multiples of 32.
- A picture is held **exactly** as the first frame, the reference's
  `expand_timesteps` way: put in over the sample before every forward and after
  every step (`WanHeldFirstFrame`), with the held tokens told timestep 0
  (`WanTimestepField`). `referenceStrengthBounds` is `1...1`, so no slider.
- Listed before LTX-2.5 in `all`, so `ModelCatalog.animator()` picks it and
  Animate makes its clips here.
- Keys are the release's own; the kit's module paths equal them, three renames
  apart in the transformer (`WanTransformerWeights`). `WanQuantizationPlan`
  packs both stacks at four bits, the `condition_embedder` and UMT5's token
  table at eight, holds tables, norms, the patch embedding and the head whole,
  copies the float32 autoencoder and the `tokenizer/` directory as they are.
- `WanTokenizer` is Zephra's own Unigram encoder (swift-transformers aborts on
  the file's canonically equivalent pieces), pinned against Hugging Face's ids;
  `WanPromptCleaning` is the reference's `prompt_clean` without ftfy.
- Both stacks stream under `WeightResidency.streamed`. The autoencoder runs in
  bfloat16 (cast at load; the release is float32), decodes one latent frame at
  a time, and tiles spatially at the engine's tile scaled to its 16-pixel cell
  (`WanRequestMapper.vaeTile`: 32 cells for the engine's 64), each tile walking
  every frame with a cache of its own.

### Packing plans

- Each family's plan lives in its backend package's `Quantization` directory;
  the packer is shared in `ZephraQuantization`. Precision is an ordered list of
  rules per component, first match wins. `QuantizableWeight` answers whether MLX
  *can* pack a tensor; `QuantizedComponent.precision(for:)` answers whether we
  *want* it, and is asked first.
- An adapter naming weights the component has not got stops the build, since a
  mismatched adapter merges nothing and hands back the base model. One whose
  tensors follow no naming `LoRAAdapter` reads stops with `adapterNamesNothing`
  before a weight is read. `ZephraQuantize` refuses Qwen-Image without `--lora`
  (`QuantizeFamily.requiresAdapter`); `--no-lora` builds it on purpose only into
  an `--out` other than the catalog's.
- Tensors stream one at a time out of the source shard and spill at four
  gigabytes, so a build runs at a fraction of the source's size.

## Vendored code

`Packages/ZImageKit` is `mzbac/zimage.swift` at commit `970f83e4`; see its
`VENDORED.md` for the license situation, the re-sync procedure and the patch
log. Any change inside it needs a `// ZEPHRA-PATCH:` comment and a `VENDORED.md`
entry.

Full detail: `docs/model-weights.md`.

## Conventions

- Conventional Commits for all git messages.
- Wording follows macOS: US spelling in user-facing strings ("Favorites"),
  Title Case for push buttons and menu items ("Open in Canvas"; "Reveal in
  Finder" is the one verb for the Finder), sentence case for toggles, captions
  and the sidebar's list labels. Code identifiers keep their spelling
  (`isFavourite`, `FavouriteToggle`): no user sees them.
- Swift 6 strict concurrency in our code. The vendored `ZImageKit` stays in
  Swift 5 language mode so its upstream files compile untouched.
- Every package pins the same exact `swift-transformers` version and the same
  exact revision of mlx-swift (`ea8a1796…`, main at 2026-09-11, carrying mlx
  v0.32.2) until a tagged release carries mlx >= 0.32, then the same exact
  version again, `ZImageKit`'s manifest included. A swift-transformers bump is
  checked by `QwenImageKit`'s `TokenizerTests`. An mlx-swift bump re-runs
  `Flux2Kit`'s two bf16 matmul probes, dense and quantized, for the M5-class
  split-K bug (mlx#3797, fixed upstream in mlx 0.32.0); the day both pass on an
  M5 under a fixed mlx-swift, the float32 gate in `Flux2ActivationPrecision`
  goes (`ROADMAP.md`).
- No emojis in code or docs.
- Keep files small; split before a file grows past its target size.
- `ROADMAP.md` is where deferred work lives: an option considered and left out
  goes there in the same change, not only in a session note.
- Zephra may ship commercially. Every new dependency, vendored file, or model
  gets an entry in `THIRD_PARTY_NOTICES.md` (copyright line, license, and any
  NOTICE file) in the same commit. That file is bundled and shown in the
  Acknowledgments window; it is the disclosure, so keep it exact.

## Debugging hooks

Every `ZEPHRA_*` switch the inference path honours is read **once at launch**
into `InferenceEnvironment` (`ZephraCore/Runtime`) by the composition root or
by `ZephraBench/main.swift` and handed down as a value; nothing below the root
reads `ProcessInfo`, and changing a variable after launch changes nothing.
`ZephraQuantize` honours none of them. `ZEPHRA_WEIGHT_RESIDENCY` reaches the
Performance tab's picker the same way, as the `\.weightResidencyOverride`
environment value.

- `ZEPHRA_PREVIEW_STATE=ready|image|editing|tucked|clip|generating|starting|queued|watching|finishing|batch|library|viewer|picker|welcome|downloading|building|update|failed|settings`
  launches a Debug build frozen in that state with no model, for `make
  screenshot`. `tucked` is `image` with the prompt slid to its lip; `welcome`
  opens the chooser whatever the preferences say; `viewer` opens the library on
  its first image full size; `picker` is `editing` with the reference sheet
  open (`InterfacePreview.wantsReferencePicker`); `clip` stands the store on
  the invented `PreviewModel.video` with a poster stamped as
  `ModelCatalog.ltx2Distilled4bit`, since the inspector reads the record's
  model; `generating` and `queued` follow a made-up run, `watching` does not,
  `starting` has no frame yet, `finishing` is a clip after its last step;
  `downloading`, `update` and `failed` sit over a picture, `update` with a
  frozen `UpdateChecker` holding a made-up release and no timer or feed under
  it. `settings` freezes the engine
  but uses a live library index at the configured `imagesDirectory`, for
  folder-change UAT with temporary fixtures.
- `ZEPHRA_UPDATE_FEED=<url>` points the update check at another manifest and
  `ZEPHRA_UPDATE_BUILD=<stamp>` makes this build claim to be an older one, so
  the whole updater runs against `python3 -m http.server` without a ship. Both
  are Debug-only (`UpdateEnvironment.current`, read once in `ZephraApp`), and
  either one also lifts `UpdateEligibility`'s "must be in Applications" rule —
  a development build is still refused, so the hand run needs `ZEPHRA_UPDATE_BUILD`
  set to a twelve-digit stamp.
- `ZEPHRA_FRESH_START=<directory>` launches as a Mac that has never run Zephra:
  its own preferences suite, `<directory>/Models` and `<directory>/Images`, and
  the single-instance guard lets it run beside a real Zephra. `make run-fresh`.
  **One suite per directory**, named from the path
  (`FreshStart.defaultsSuite`), so two fresh starts are two Macs rather than
  one; a directory with no `.zephra-fresh-preferences` stamp in it has its suite
  emptied before a preference is read, which is what makes `FRESH_RESET=1`'s
  `rm -rf` a reset and `FRESH_RESET=0` a resumed session.
- `ZEPHRA_FORCE_RELAY=1` (the phone, Debug only) shuts every road but the relay:
  `RelayOnlyRoads` (`Support/`) finishes the browse empty and fails every LAN
  endpoint, so a simulator on the Mac's own Wi-Fi pairs and connects the way a
  phone in another country does. `make run-ios FORCE_RELAY=1`; the Mac's relay
  switch has to be on too, or there is no host in the room.
- Debug only: `ZEPHRA_DOWNLOAD_TEST_HUB=http://127.0.0.1:<port>` runs the real
  downloader and UI against disposable HTTP fixtures with an unloaded exercise
  backend; use a separate preferences domain and models folder. No such hook
  exists in Release.
- `make logs` streams `os.Logger` output for subsystem `io.zephra` at info and
  above, which is where the memory guard's admitted and refused lines sit; `log
  stream` without `--level info` shows none of them.
- A locally built Zephra (every `make run`, `make build`, any ad-hoc signature)
  keeps its companion identity and pairings in
  `~/Library/Application Support/Zephra/Companion/` (`identity`, `devices.json`),
  never in a keychain: the login keychain identifies an app by its signature and
  a local build has a new one every build, which asked for the password at
  launch and on every pairing write. Delete the folder to forget every phone and
  pair again; the launch log names the store in use. A signed build keeps them
  in the keychain under `io.zephra.link`, touched at most once a launch; clear
  with `security delete-generic-password -s io.zephra.link -a identity` and the
  same for `-a devices`.
- `make screenshot` photographs the window by its CoreGraphics id and fails
  rather than grabbing the screen when there is no window; `WINDOW=<title>`
  takes the window with that title (a Settings window is titled after its tab).
  A frozen Mac build opens no road at all: `startCompanion` refuses while
  `InterfacePreview.requestedState` is set, so a screenshot build is never on
  the network.
- The phone has the same switch and a shorter list:
  `make run-ios PREVIEW=<state>` passes `SIMCTL_CHILD_ZEPHRA_PREVIEW_STATE` to
  the simulator, and `MobilePreviewState` is
  `pairing|ready|generating|capsule|library|viewer|today|offline|settings` —
  which surface is up and whether the wire is live, since there is no engine
  here to freeze. Every state but `pairing` is a `LinkClient.frozen` with no
  road under it. `make screenshot-ios` photographs the simulator; see
  `docs/mobile.md`.
- `swift scripts/ax-press.swift "<title>" [role]` presses a control by
  `AXTitle` or `AXDescription` through the accessibility tree without
  activating the app or moving the mouse, or, for a Form `Toggle` with
  neither, by the label linked through `AXTitleUIElement` or
  `AXServesAsTitleForUIElements`; `--dump [depth]` prints the tree, that
  linked label included, and `ZEPHRA_PID` picks the copy to drive. The same script sizes and
  places the window for a screenshot without activating it: `--resize W H` (an AX size counts
  the title bar, so the 880 x 560 floor reads back 880 x 592, and a tiled or zoomed window
  keeps its own frame, which it says), `--move X Y`, and `--reveal "<title>"`, which scrolls a
  control into view — the chooser's greyed cards sort last and are otherwise below the fold.
  `swift scripts/ax-type.swift "<label>"
  "<text>"` sets a labelled text field's value and confirms it, which is how
  the Size menu's custom size is typed hands-off. With `open -g --env
  ZEPHRA_PREVIEW_STATE=settings build/Debug/Zephra.app` and the titled
  screenshot, that is how a Settings tab is photographed hands-off.
- `make bench ARGS="--size 1024 --steps 9 --runs 3 --json"` measures load,
  s/step and peak memory; idle machine, Release only.
  `--reference IMAGE --strength 0.6` measures the editing path and reports
  where the loop entered and how many steps ran; `--micro --size 1024` times
  the DiT's MLX kernels without weights; `--preview` turns frames on, reports
  their count and mean cost, and writes the last as `<stem>.preview.png`
  (`ZEPHRA_PREVIEW_INTERVAL_MS` underneath, 0 off); `--model
  ltx-2.5-distilled-4bit --size 768x512 --frames 49` measures a clip, written
  as `.mp4` with its poster beside it; `--extend CLIP --context N` holds a
  clip's last frames at the head of the run the way Extend Clip does and joins
  the result onto the source as `<stem>-extended.mp4`; `--stream` and
  `--stream-depth N` report gigabytes read per step and the disk's rate.
- `ZEPHRA_PROFILE_STEP=1` prints per-phase timings and MLX's active and peak
  allocation to stderr.
- Precision and padding, for bisecting without a rebuild:
  `ZEPHRA_DIT_DTYPE=f32|bf16`, `ZEPHRA_PAD_PROMPT=full`,
  `ZEPHRA_KEEP_CACHE=1`, `ZEPHRA_CACHE_LIMIT_MB=N`. `ZEPHRA_VIDEO_STAGES=1|2`
  forces LTX-2.5 to one stage or two whatever the size says.
- `ZEPHRA_VAE_TILE=<latent tile edge>` decodes in overlapping tiles so the peak
  is set by the tile, not the image; the bench sets it on the running family's
  runtime handle. In the app it only seeds the Performance tab: `InferenceActor`
  sets the tile through `InferenceRuntime.setVAETileSize` as each run and
  warm-up starts, for that run's own model, tiling under Automatic when its
  `peakBytes` exceeds `MemoryBudget`. The handle writes the family's
  `VAETileSetting`, one locked slot per backend package; no kit holds a static.
- `ZEPHRA_WEIGHT_RESIDENCY=streamed|resident` overrides the streaming
  preference for one launch; `ZEPHRA_STREAM_DEPTH=N` sets the read-ahead
  (2 unless set). Every family in the catalog streams; a family added later with no
  measured streamed figure loads resident regardless.
- `ZEPHRA_GENERATE_ON_LAUNCH=<prompt>` (Debug only; inert in Release, like
  `ZEPHRA_PREVIEW_STATE`) presses Generate once the model is ready, for a real
  in-app run from a shell. `ZEPHRA_REFERENCE_ON_LAUNCH=<path>` fills the well
  first through `adoptReference`, and Generate waits for it. `ZEPHRA_WIRED_LIMIT_MB=N`
  (0 off) and `ZEPHRA_MEMORY_LIMIT_MB=N` replay the app's limits in the bench;
  every `_MB` is `MemoryUnits.mebibyte`.
- `ZEPHRA_GPU_WORKING_SET_MB=N` (Debug only, `GPUWorkingSetOverride`, read once
  in `ZephraApp` beside `GPUMemoryBudget` and `InterfacePreview.budget()`)
  replaces `MemoryBudget.gpuWorkingSet` with N mebibytes, so this Mac judges
  models as a smaller one would: the chooser, the model menu's notes,
  `MemoryFit`, `WeightResidencyPolicy`, `VAETilingPolicy`, the phone's
  `ModelSummary` and the static half of the memory guard all read that one
  number. `physicalMemory` and `wiredLimitMB` stay this Mac's own, and
  `MemoryGuard`'s live reading still asks the real machine, so a hand check
  meant for a 16 GB Mac (12124 is bender's working set) can be run on a Mac
  that is free. Absent or malformed it changes nothing.
- Launch from a shell (`./build/Release/Zephra.app/Contents/MacOS/Zephra`)
  rather than `open` when the point is the error text: MLX prints the Metal
  error to stderr and the crash report carries only `abort() called`. A GPU
  restart is in `log show` under `IOGPUFamily`, and
  `/Library/Logs/DiagnosticReports/gpuEvent-*.ips` names the blamed process.

Full detail: `docs/debugging.md`.

## Environment notes

- In shell tooling, use `/bin/ls` rather than the interactive `ls` — the
  shell's `ls` function can hang on this volume.

## Website deployment destinations

Website iterations and modifications go to ChatGPT Sites first. Production is
`zephra-site-urandom-io`, deployed by `deploy-website.yml` on every push to `main`
touching `product-mockups/` (`make deploy-production` by hand). Notarized app
releases belong in `zephra-assets-urandom-io/releases/`. Keep both deployments on
the same page source.
