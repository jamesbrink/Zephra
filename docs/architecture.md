# Architecture and layering

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

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
  ZephraKit/ZephraMedia        Foundation, AVFoundation — frames in, an H.264 MP4 out
                                                  (`MP4Writer`), which a video backend takes
                                                  for its clip; the app never reads it, its
                                                  player is AVKit's over the file
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
                                                  which serves one guest at a time
  ZephraLink/ZephraLinkClient      Foundation, Observation, ZephraLinkProtocol,
                                                  ZephraLinkTransport — LinkClient, the one
                                                  object the phone's views observe, over an
                                                  injected LinkRoads and LinkKeyStore;
                                                  Sources/ZephraMobile is what links it
  ZephraStyle                  SwiftUI, ZephraCore — the chrome both apps draw with:
                                                  ZephraChrome's radii, hairlines and
                                                  heights, the washes, the palette's colour
                                                  sets, and the badges that are only those.
                                                  No AppKit, no UIKit, no engine
  ZephraMLXKit/ZephraQuantization  MLX, ZephraCore, ZephraSnapshot — the streaming weight
                                                  packer, and the one descriptor build every
                                                  family runs through it
  ZephraMLXKit/ZephraMLX           MLX, MLXNN, ZephraCore — the packed loader, the manifest
                                                  reader, the rotary table, the pixel packer,
                                                  the tiled decode, the allocator's knobs and
                                                  the streamed layer stack; <Family>Kit may
                                                  take it
```

- `ZephraCore` (in `Packages/ZephraKit`): Sendable value types + protocols.
  Zero dependencies — no model package, no MLX, no SwiftUI. It builds for iOS
  18 as well as macOS 15, because the companion app reads the same catalog and
  the same capabilities; the three pure parsers that turn typing into them,
  `SeedEntry`, `SizeEntry` and `ReferenceRole`, live here for that reason
  rather than in the app's `Support/`, where they began.
- `ZephraStyle` (its own package): the chrome both apps draw with — every
  radius, hairline and height in `ZephraChrome`, every wash in
  `ZephraChrome+Washes`, the palette's colour sets in `Palette.xcassets` read
  through `.module`, and `Chip`, `ModelDot`, `UpscaleBadge` and `VideoBadge`,
  which are nothing but those numbers. SwiftUI and `ZephraCore`; `make
  lint-layers` refuses AppKit, UIKit and `ZephraEngine` here, because a token
  that names one platform's toolkit or the engine's state is one app's again.
  The hairline is the one constant spelled twice, under `#if os(macOS)`, since
  each platform has a separator colour of its own. What stays in the app's
  `Style/` is the chrome that is AppKit-bound or names an app type.
- `ZephraSnapshot` (in `Packages/ZephraKit`): downloading a model, checking a
  local model directory, reading the Hugging Face cache as a fallback, and
  listing what the catalog's models occupy on disk. Foundation only, which is
  the point: `make test` covers all of it, so these suites need no Metal and
  the downloader is driven through a `URLProtocol` stub.
  - `Download/` is the downloader. `ModelDownloader` first asks
    `/api/models/{repo}/revision/{revision}` which commit the catalog's branch
    names and pins the transfer to it in `.zephra-revision` beside the files —
    a download of hours, or one resumed a week later, must list and fetch one
    commit, not a mix of two — then lists that commit from
    `/api/models/{repo}/tree/{commit}?recursive=true` (paged by the `Link`
    header, decoded by `RepositoryListing`), filters it with the descriptor's
    globs (`FilePattern`, fnmatch rules, so `*` crosses directories the way
    the hub's own matching does), and fetches each file from
    `/{repo}/resolve/{commit}/{path}` into
    `<models>/Downloads/<org>--<repo>/`, flat, as the repository names them.
    A file in flight is `<name>.incomplete` beside where it will live and is
    renamed only when its size matches the listing, so a stop or a broken
    connection resumes with a `Range` — and an `If-Range` naming the `ETag` the
    first answer carried, kept in `<name>.incomplete.etag` — and a truncated
    file is never taken for a finished one; a 200 answer to a `Range` request
    means the server ignored it or the file changed, and a 206 that does not
    begin where the file ends is refused, so in both cases the file starts over
    rather than being spliced onto another. The pin goes when the part's last
    file lands and `.zephra-commit` records what the folder holds, so a later
    transfer at another commit empties it first rather than keeping a shard of
    the same size from the wrong one; a path in the listing that would leave
    the folder is refused before anything is written, with links followed, so a
    component that already points out of the folder is refused too; a partial
    that is a link is replaced rather than appended to, and a folder that is a
    link is never emptied for a newer commit, since either would reach wherever
    the link points. The transfer
    is paused above 64 MiB of body not yet written and resumed under 16 MiB
    (`ChunkedDownload`, told of each drain by `ChunkedBody`; the task's pause and
    the count saying it is paused change under one lock, so a drain can never
    resume a task a moment before it is suspended for good), so a fast
    connection cannot pile a shard up in memory ahead of a slow disk. Cancellation is checked
    between chunks. The standalone `fetch` entry point removes unfinished writable download folders
    when cancelled, after file handles close, including cancellation during retry backoff.
    The app injects `TransferAcquisition` instead: `ModelTransfers` owns at most two
    physical repository transfers, with one writer per canonical destination. Matching
    file sets/revisions share work; incompatible requests wait for read/write claims to
    release. Multi-repository claims are admitted atomically to avoid crossed-dependency
    deadlocks. `ModelDownloads` keeps model requests alive independently of the selected
    foreground load. Switching detaches that waiter, Pause preserves partials, and explicit
    Cancel discards unfinished files only after the final owner and writer settle.
    Completed repositories and cached releases stay; network failures remain resumable.
    The canvas offers Cancel Download during initial loading and model switches. **No
    `Authorization` header is ever sent** — every repository the catalog names
    is public — so no token, in the environment or in a file, can turn a
    public model into a login wall.
  - `HubSnapshotCheck` is what says a directory is a finished download: a
    config, some weights, every shard a `*.safetensors.index.json` names, and
    nothing still `.incomplete` — or a `.zephra-revision` — anywhere under it.
  - `HubCache` and `HubRepository` read the two layouts in
    `~/.cache/huggingface/hub` — `hf download`'s
    `models--<org>--<repo>/snapshots/<commit>/` and the flat
    `models/<org>/<repo>/` an older Zephra wrote. That cache is a **read-only
    fallback**: a Mac that has a release there does not fetch it again, and
    nothing is ever written to it.
- `ZephraQuantization` (in `Packages/ZephraMLXKit`): the streaming weight
  packer, shared by every family. It knows nothing about any model — a family
  hands it a `QuantizationPlan` saying which directories hold weights, which
  tensors to leave alone, how finely to squeeze the rest, and which low-rank
  adapters to merge on the way past. `SnapshotBuild` beside it is the safe way
  to run that from the app and from `ZephraQuantize` alike: a `.partial`
  directory renamed on success, removed on failure, and a free-space refusal
  before anything is read. Both refuse, first of all, a destination that is
  the source, inside it, or around it, links followed
  (`SnapshotQuantizer.requireDisjoint`): the packer empties each component
  directory it writes to before reading the component, so `--out` spelled one
  directory wrong would have deleted the release it was reading. The
  `pack(release:into:descriptor:plan:componentWeights:onProgress:)` overload
  is the whole of a catalog build — space checked against `builtBytes`, one
  progress event per component through `BuildTally`, cancellation between
  tensors, and the provenance stamp — so each `<Family>SnapshotBuild` is its
  plan and its component weights and nothing else. That overload is why the
  package takes `ZephraCore` and `ZephraSnapshot`.
- `ZephraMLX` (in `Packages/ZephraMLXKit`): MLX work that is the same job for
  every family, written once. `Loading/` is how a snapshot gets into a module
  tree: `PackedSnapshotManifest` reads `quantization.json` (nil when absent,
  `PackedSnapshotError.malformedManifest` when present and unreadable, never
  "unpacked" by mistake — read that way, it loaded packed shards into an
  unpacked tree and failed a component later with a shape error naming
  neither file nor reason), `PackedWeightLoading` reshapes a tree for
  whichever tensors carry a `.scales` and fills it, refusing packed shards
  with no manifest before the tree is touched, and casts the packer's float32
  scales to the stream's dtype with `castFloatParameters`; `SafetensorsShards`
  lists and reads a component's shards in one order. `Rotary/` is
  `RotaryFrequencies`, the cosine and sine table both ports build, and
  `rotate(_:computeDType:)`, where the one difference between them — klein
  rotates in float32, Qwen-Image in the stream's dtype — is the argument.
  `PixelBuffer` turns a decoded `[1, h, w, 3]` in -1 to 1 into a PNG or into
  RGBA8 bytes, rounding to the nearest byte as `diffusers` does. `TiledDecode`:
  an autoencoder's decode allocates in proportion to the image, so decoding
  overlapping latent tiles bounds the peak by the tile. `MLXRuntime`: the
  process-wide allocator's limits and readings, with `WiredLimitReservation`
  beside it replacing the one wired-memory ticket in the order asked, and
  `MLXInferenceRuntime` the one `InferenceRuntime` every family hands out — it
  takes the family's `VAETileSetting`, the locked slot the engine's per-run
  tile lands in, which is the only thing about it that is not process-wide. `GPUGeneration`: whether this is an
  M5-class GPU, read once from Metal, for the one dtype gate that needs to
  know. `LatentPreview`: how far to pool a latent for a preview frame, and the
  frame's bytes through `PixelBuffer`. `Streaming/`: the `LayerWeightStream`
  that runs a stack of identical layers with a window of their weights in
  memory, reading each layer from its shards a couple ahead of the one running
  (see "Streaming the weights" in `docs/model-weights.md`). A model package may
  depend on this; nothing in it may depend on a model package. The vendored
  `ZImageKit` keeps its own copy of the tiled decode and the preview as a
  `ZEPHRA-PATCH`, because pointing vendored code at ours would complicate
  every re-sync. What the two ports deliberately do *not* share — the final
  norm's bias, the scheduler's shift, the rotary compute dtype,
  `ReferenceLatents` — is listed in `PROVENANCE.md` under "Shared between the
  two ports, and what is not".
- `ZephraEngine` (in `Packages/ZephraKit`): concurrency + state. Depends on
  `ZephraCore` and `ZephraSnapshot`, nothing else. Backends arrive as an
  injected `BackendRegistry` of `@Sendable` factories; this layer never names
  a concrete backend. `ModelInventory` is the one thing it takes
  `ZephraSnapshot` for: the list Settings > Models observes, measured off the
  main actor and re-read after every deletion.
- `ZephraBackendZImage`, `ZephraBackendQwenImage`, `ZephraBackendFlux2` and
  `ZephraBackendLTX2` (their own local packages): translate `ZephraCore` types
  to and from one family's types. No state, no UI. Each depends on `ZephraKit`'s
  `ZephraCore` and `ZephraSnapshot` products, on `ZephraQuantization` for its
  packing plan, and on its own family's kit; the video one takes `ZephraMedia`
  too, for the MP4. All four also pack a download into the variant they load,
  on first load, through the protocol's `build` step — every model in the
  catalog but the 8-bit Z-Image is built here. This split keeps `Packages/ZephraKit` free of MLX
  dependencies, so `make test` (`swift test` there) stays fast and doesn't
  touch Metal.
- `Packages/ZImageKit`: vendored. Edit only with a `// ZEPHRA-PATCH: <reason>`
  comment and a matching entry in `VENDORED.md`.
- `Packages/QwenImageKit`: ours, clean-room. Written from Qwen-Image-2512's own
  config files and from `diffusers`, never from the GPL-3.0
  `mzbac/qwen.image.swift`. `PROVENANCE.md` records why and how; keep it true.
- `Packages/Flux2Kit`: ours, a translation with attribution from two MIT Swift
  ports (`xocialize/flux2-klein-swift`, `VincentGourbin/flux-2-swift-mlx`) and
  `diffusers`, pinned against `diffusers` and departing from the ports where
  the reference says so. Never from GPL code, and never from
  `xocialize/flux2-vae-mlx-swift`, which has no license. `PROVENANCE.md` lists
  the deliberate departures; keep it true.
- `Packages/LTX2Kit`: ours, a translation with attribution from the Apache-2.0
  `diffusers` (the LTX-2 transformer, connectors and video autoencoder) and
  `transformers` (Gemma 4), pinned against both by dumped fixtures, with two MLX
  ports read as cross-checks and nothing copied from the official `Lightricks/LTX-2`
  code, whose license is unstated. Video only: the audio stream is a seam, not a
  module. `PROVENANCE.md` lists the departures; keep it true.
- `ZephraUpscaleRealESRGAN` (its own local package): the Real-ESRGAN upscaler,
  a post-process beside the backends rather than one of them. It conforms to
  `ZephraCore`'s `ImageUpscaler`, takes `ZephraMLX` for the tiler, and imports
  no family kit; no backend imports it. See "Upscaling" in `docs/reference-pictures.md`.
- Nothing in the app target may import a model package or `MLX`. Only
  `Sources/Zephra/ZephraApp.swift` (the composition root) may import a
  `ZephraBackend*` or `ZephraUpscale*` package, to register it. Everywhere else in the
  app target goes through `ZephraEngine` and `ZephraCore`.
- No backend package may import another backend package, or a build for one
  family drags in every other family's pipeline.
- `Packages/ZephraLink` is the one package an iOS app links too, so what it may
  import is a short allow-list rather than a short ban: Foundation-level
  frameworks, `ZephraCore`, `ZephraEngine` and itself. `ZephraEngine` is there
  for `GenerationRecord` and `LibraryAnnotation` alone, which cross the wire as
  themselves rather than as a second shape of the same provenance. Its three
  targets stack in one direction only — `ZephraLinkProtocol`, then
  `ZephraLinkTransport`, then `ZephraLinkClient` — so the wire is tested without
  a socket and the client without a network. See `docs/companion.md`.
- `Sources/ZephraMobile` links the value layer, the wire and the chrome and
  nothing else: no engine, no folder on disk, no backend, and no AppKit, which
  would compile on nothing and mean the file was written for the wrong app. See
  `docs/mobile.md`.

Code rules:

- One public type per file; file name matches the type name.
- Target ≤150 lines per file.
- No `*Manager`, `*Helper`, `*Utils`, or `*Service` type names — name types
  for what they are. The one exception is a subclass that keeps AppKit's own
  name: `PromptLayoutManager` is an `NSLayoutManager`.
- Views hold at most 3 stored properties, or get split into subviews.
- `ModelCatalog` is the only static registry in the codebase. No other
  singletons.
- Vendored code in `ZImageKit` is edited only under `// ZEPHRA-PATCH:`
  discipline (see `Packages/ZImageKit/VENDORED.md`).

Run `make lint-layers` before every commit. It greps for forbidden imports
across the layers above and fails the build if any are found, and beside those
it enforces four smaller rules that had each drifted at least once: no repeating
animation in either app target, `hoverWash` named only where `allowsHitTesting(false)`
keeps it off a button, US spelling in user-facing string literals, and the
`Manager`/`Helper`/`Utils`/`Service` type-name ban with `PromptLayoutManager` as
its one documented exception. The spelling rule matches whole lines rather than
`grep -o`, since the match alone cannot tell a doc comment from code, and it skips
`LibraryScope`, whose `"favourites"` is the stable spelling written into
preferences — the one place the British word is correct.

`make lint-size` is advisory and never a gate: it lists the files over the
150-line target so the drift stays visible. The three-stored-properties-per-view
rule is deliberately not linted at all — telling a stored property from a computed
one or from a local inside a function needs the parser, and every regex tried for
it flagged properties that were neither. A rule that cries wolf is worse than one
a reviewer applies by eye.
