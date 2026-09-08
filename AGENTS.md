# Zephra

Zephra is a native macOS app that generates images locally on Apple Silicon,
via MLX/Metal. It runs four model families today, Z-Image-Turbo,
Qwen-Image-2512, FLUX.2 klein 4B, and LTX-2.5 (video), behind one backend seam.

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
  ZephraKit/ZephraTestSupport  Foundation, ZephraCore — Scratch, the filesystem test
                                                  fixture, and SnapshotUnderTest, the real
                                                  snapshot a kit's suite may read
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
  Zero dependencies — no model package, no MLX, no SwiftUI.
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
  (see "Streaming the weights" under Model weights). A model package may
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
  no family kit; no backend imports it. See "Upscaling" below.
- Nothing in the app target may import a model package or `MLX`. Only
  `Sources/Zephra/ZephraApp.swift` (the composition root) may import a
  `ZephraBackend*` or `ZephraUpscale*` package, to register it. Everywhere else in the
  app target goes through `ZephraEngine` and `ZephraCore`.
- No backend package may import another backend package, or a build for one
  family drags in every other family's pipeline.

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
across the layers above and fails the build if any are found.

## Download lifecycle

`ModelAcquisition` in Core is injected into every backend's `ensureAvailable`.
`ModelResolution` creates a private unloaded backend for family-specific disk checks;
it never shares the inference actor's mutable backend or calls build/load/generate.
`ModelDownloads` in Engine owns request observation and foreground borrowing;
`ModelTransfers` in Snapshot owns network slots, preflight, compatible repository claims
and per-volume space reservations. A claim spans validation, build and resident use,
so acquisition completion never opens a deletion gap, and is borrowed once: Retry on
a resident model answers ready without touching the pool, and a load that reaches a
lease the store already holds reuses it (`unloadModel` asserts the request is gone
after its one release). Failed/canceled loads unload before releasing their claim. Foreground events carry an operation identity; superseded
progress and completion cannot change the selected model's state.

`GenerationStore.acceptsWork` (`+Admission`) is the one gate every entry point
reads — no folder changing, no storage being deleted, not quitting — and a caller
adds only the conditions that are its own; `drain()` reads it too, so
`deleteModelStorage` drains again on its way out. `canQueueVariation(of:)` is the
variation's own answer, and does not wait for a reference still on its way into
the well: a variation replaces the settings outright and cancels that read.
All UI storage deletion goes through `GenerationStore.deleteModelStorage`, which
checks active requests/residency/queued work and closes new admission while deleting.
Folder changes close download admission, pause every request and await file closure.
`AppLifecycle` defers normal Quit while `GenerationStore.shutdown` settles tasks,
then `LibraryIndex.shutdown` stops watching and drains its write chain and scans (store
first, because the store's last save inserts into the index), then the runtime seam
synchronizes Metal before allowing process teardown.

## How a generation runs

Three types in `ZephraEngine`, one concern each. The split is what lets the
engine be tested in seconds without Metal.

- `GenerationStore` (`@MainActor @Observable`) is the only object the UI
  observes, and it is split across `GenerationStore+*.swift` by concern —
  loading (the entry points in `+Loading`, the borrow-prepare-release body in
  `+Preparation`), the admission gate (`+Admission`), generation (`+Generation`,
  with the write that follows in `+Saving`, which moves an image deleted while
  its write was in flight straight on to Recently Deleted rather than announcing
  it saved), the queue,
  batches (several seeds of one prompt from
  one press of Generate), model switching, history, availability, preview,
  the public convenience init (`+Init`), the tiled decode (`+Tiling`),
  the reference picture, the library, following the run, upscaling and filing
  the upscaled result, the interface's own questions (`+Interaction`), the
  download requests it keeps alive (`+Downloads`), the two folder changes
  (`+ImageDirectory`, `+ModelDirectory`), and weight residency (`+Residency`).
  Add a new concern as another extension file, not as more lines in
  `GenerationStore.swift`.

  What a backend hands back is `GeneratedMedia`: `.image(png:)` from the three
  picture families, `.video(GeneratedVideo)` — the MP4, its first frame as the
  poster PNG, the frame count and rate — from LTX-2.5. One return type rather
  than two protocol methods, because the actor, the timer, the cancellation
  check and the queue are the same whatever comes back; only the last step
  reads the kind. `GenerationSettings.frames` is the clip's length (1 for a
  picture, pinned there by `clamp` for every model whose
  `ModelCapabilities.frameBounds` is the degenerate `1...1`), and a video
  model's `frameAlignment` snaps it to the `1 + 8k` ladder its autoencoder makes.
- `InferenceActor` is the only place backend code runs. It overrides
  `unownedExecutor` with a serial `DispatchQueue`: a generation is tens of
  seconds of synchronous Metal work, and on the cooperative pool that would
  starve every other task in the process. Backends are not `Sendable`, which is
  why a registry of `@Sendable` factories goes in and the backend is built here.
  A backend looks for a cancel between steps and not after its decode, so both
  `InferenceActor.generate` and the store's `run` check again once the bytes are
  back: a Stop that lands during the decode keeps no image, publishes nothing
  and writes nothing. A finished image carries its own job's batch and model
  (`QueuedGeneration`), not `running`'s, which a cancel empties, nor the store's
  `descriptor`, which a switch moves before the run is over. The VAE tile is chosen
  the same way, per run from the job's model, by `GenerationStore+Tiling` and set
  by the actor as the run starts; see `ZEPHRA_VAE_TILE` under Debugging hooks.
- `EngineEventPump` carries progress from that queue back to the main actor. Its
  `AsyncStream` buffers the newest four events and drops the rest — progress is
  a snapshot, not a log — and `run` drains before returning, so the state a
  caller sets after an operation is never clobbered by an event still in flight.

`current` is what the canvas is showing, and only that.
`GenerationStore+FollowingRun.swift` is the other half of that sentence: pressing
Generate — or asking for a variation — starts *following the run*, and opening or
selecting any other picture stops. A result is published to `current` only while
`followsRun`; one that lands while the user is looking elsewhere still enters
history, the wall and the library, and leaves the canvas where it is.
`watchRun()` follows again and, when a picture picked up from the sidebar has
replaced the capsule's settings and model since (`capsuleHoldsPicture`, which
any edit to `settings` clears), puts the run's own back — a capsule the user
has been working in, a model picked mid-run or a prompt typed since, it leaves
alone; `isShowingRun` is
"following, and something is running", and `hasPicture` in the app target is
`current != nil || isShowingRun`, so the inspector has something to describe
from the moment a run starts. Two ways onto the canvas from the library, told
apart by what they do to the capsule: `open(_ item:)` only looks, so the grid's
"Open in Canvas" never replaces the prompt being written, and `select(_ item:)`
adopts the picture's settings and chooses its model as `select(_ image:)` does
for a session's own (see "Selecting a picture chooses its model without
loading it" under Adding a model), which is what every square on the canvas
sidebar's wall does — a square is a run to pick up again, and the running card
is the way back to the one in flight. The
upscale result follows the same rule by the one test it can apply: it takes the
canvas only when the canvas was showing its parent, or was showing nothing.

`livePreview` is the newest frame of the run in flight — `GenerationPreview`,
RGBA8 pixels of at most 256 pixels an edge, decoded by the family's own VAE from
a pooled copy of the latent. It rides in on `GenerationProgressEvent.preview`,
which is why that type hand-writes `==` and `hash(into:)` to ignore it:
`EngineState` is `Hashable` and compared on every transition, and hashing a
quarter of a megabyte per step to answer a question nobody asks is not worth it.
The store keeps the frame outside the state and puts it down on every way a run
can end, and only then: looking away keeps it for the running card, and a press
of Generate that queues behind the run in flight leaves it on the canvas. `StepTimer.annotated` rebuilds the event field by field, so a new field
there has to be forwarded by name or it never reaches the canvas.

Where a frame comes from: each kit has a `<Family>LatentPreview` that takes a
latent in its loop's own packed space, unpacks it, pools it so its long edge is at
most 32 cells (8 for LTX-2.5, whose cell is 32 pixels), and decodes that through the family's own autoencoder with the
tiling skipped — `LatentPreview` in `ZephraMLX` holds the pooling and the byte
packing for Qwen-Image and klein, and the vendored `ZImageKit` keeps its own copy
for the same reason it keeps its own `VAETiledDecode`. Each loop calls an optional
`onPreview` **after** the step's `MLX.eval`, never on the last step, handing over
the step index and a *closure* that makes the frame rather than a frame: the
backend owns a `PreviewThrottle` (0.75 s, `ZephraCore`) and never pays for the
frames it drops. The existing before-step `onProgress` is untouched, so
a frame never splits a step: `BenchStepClock` and `StepTimer` ignore any update
carrying a frame, because a frame is reported after its step rather than before
the next one. A frame's decode does land inside the step it follows, and both
leave it there on purpose. On screen the pace is what the remaining steps will
really take, frames included; in the benchmark `--preview` is for finding out
what turning frames on costs, and it reports the frame's own mean beside the
step time so the two can be told apart. A family that never calls `onPreview`
simply shows no frames.

What each loop passes is the run's estimate of the **finished** latent,
`x - sigma * v`, and not the latent it is holding. This is the whole feature
working or not: all three schedules are bent towards their noisy end, and klein's
four-step ladder at 1024 pixels is still at sigma 0.77 on its third rung, which
decodes to flat brown mush. One more Euler step of the velocity already in hand,
all the way to zero noise, is what a person means by "how is it coming along".
It costs one elementwise operation, and it is computed inside the frame closure,
so a dropped frame does not pay for it.

## The library

`~/Pictures/Zephra` is the default library. Settings > General can select another
folder and optionally migrate images, sources, albums, and Recently Deleted.
`AppSettings.imageLibrary()` supplies the same persisted root to the store and index.
`GenerationStore.changeImageDirectory` gates work and drains writes while
`LibraryIndex` pauses mutations and scans; only a successful change is persisted.
Migration moves owned PNGs and manifests without overwriting destination files.
Keep in Place switches the visible library and leaves the old folder untouched.

The selected folder is the library. There is no database: the folder is the
truth, and everything the app knows about an image is inside that image's own
PNG. Move a file, rename it, or copy it to another Mac and its prompt, its
favourite, and its tags go with it. `ZephraEngine/Library/` is that folder read
as an index, and it is Foundation only, so `make test` covers all of it.

- Two text chunks, two owners. `zephra:generation` is provenance —
  `GenerationRecord`, written once when the image is saved, never edited. A PNG
  without it was not made here and is skipped, so a folder can hold more
  pictures than the library lists. `zephra:library` is `LibraryAnnotation`: favourite,
  tags, albums — the things a person changes afterwards. Anything mutable goes
  in the second chunk; nothing rewrites the first. The record also carries the
  `batchID` of the press of Generate that made the image, so a run survives the
  session that made it: the canvas sidebar's timeline groups by it after a
  relaunch, and falls back to adjacency for files written before the field
  existed.
- `PNGTextChunks+Header` reads a chunk without reading the file: 64 KiB, stop at
  the first IDAT, grow only if the chunks have not been seen yet. A grid of two
  thousand images is two thousand header reads, not two thousand full decodes.
  `PNGTextChunks+Replacing` writes one back by splicing before IDAT and
  dropping the same keyword, so repeated writes do not grow the file.
- `LibraryScan` fingerprints the directory from one `contentsOfDirectory` and
  re-reads only the paths whose (mtime, size) moved. `LibraryFolderWatch` is a
  `DispatchSource` on the directory, debounced, and re-opens the fd when the
  folder is renamed away and back.
- `LibraryIndex` (`@MainActor @Observable`) is what the UI observes, split by
  concern the way `GenerationStore` is. Mutations take a set of ids, apply
  optimistically, queue onto one serial chain, and revert by re-reading the one
  file that failed — unless a newer change for that file is still `pending`, in
  which case the older write neither overwrites what is on screen nor reverts
  nor reports: the newer write is about to land and speaks for itself.
  `LibraryQuery` holds the scope, the text, and the sort, and
  `sections` are recomputed when it changes — the view never filters.
- Undo. Every edit to the annotation chunk — a favourite, the tags, album
  membership — and every album made, renamed or deleted registers its inverse
  on `LibraryIndex.undoManager`, an optional `UndoManager` (Foundation, so the
  engine stays Foundation-only) that the app sets from the window's own through
  `LibraryUndoRegistration` in `Sources/Zephra/Support/`; nil, which a test or
  the preview index leaves it at, records nothing. The index registers rather
  than the call sites because it is the one thing that still knows every
  touched image's previous annotation, and it registers only what changed, so a
  favourite set on a picture already favourite leaves no "Undo" that does
  nothing. `LibraryIndex+Undo` is the whole of it: putting annotations back is
  an ordinary `annotate`, which records the redo on its way. The menu names
  are "Favorite", "Tag", "Album", "New Album", "Rename Album" and "Delete
  Album"; deleting an album is one entry covering the album and its members'
  memberships, and each inverse carries its name through, so "Undo New Album"
  redoes as "Redo New Album" rather than as the deletion it ran. Changing the
  images folder empties the stack, since every entry names files no longer
  indexed. Recently Deleted stays out on purpose: a delete already has thirty
  days of Put Back. No `CommandGroup` replaces `.undoRedo`, which is what lets
  the standard Edit items reach the window's manager whenever a text field is
  not first responder. `LibraryUndoTests` pins all of it.
- Deleting moves the file to `Recently Deleted/` with a `deletedAt` and an
  `origin` (the root or `Sources/`) in that folder's own manifest, and a scan
  purges anything older than thirty days (`ImageLibrary+Purge`). Both kinds of
  picture are deleted into it and listed there, a generated one by its record
  and an imported one by its `SourceRecord`; Put Back returns each to the folder
  it came from — the manifest's word, else the file's own header for a manifest
  written before origins were recorded. The purge rechecks that a file is ours
  for every candidate, entry or not, since a name can be reused by somebody
  else's picture, and drops the stale entry rather than the picture; Delete
  Immediately forgets the entry too, so a later file under that name gets its
  own thirty days. Nothing is unlinked on the user's behalf before then.
- A clip is its poster. LTX-2.5 hands back `GeneratedMedia.video`: the MP4 and
  its first frame as a PNG, and the library indexes the PNG exactly as it
  indexes a picture — the record inside it carries `frameCount` and `frameRate`,
  which is all that says it is a clip — with the MP4 beside it under the same
  stem. `VideoSidecar` is the one rule for where the MP4 lives; the record never
  names the file, because Put Back may rename both. Everything that moves a PNG
  moves the pair: `ImageLibrary.write` (the MP4 first, so a scan never lists a
  clip whose file is not there), `moveToRecentlyDeleted`,
  `restoreFromRecentlyDeleted` (stepping both around a collision), `discard`
  (which the purge and Delete Immediately go through), and the migration's
  inventory. `LibraryItem.videoURL` and `videoSeconds` answer from the record;
  `LibraryItem.exportURL` in the app target is the clip for a clip and the
  picture otherwise, and Export, Copy, Share, drag and Reveal all go through it,
  in the library and on the canvas alike (`ImageExport.savedFile`, and a
  `Transferable` that exports an MP4 for a saved clip and a PNG otherwise). Two
  things a clip's export does not do yet: the record, the favourite, the tags
  and the albums stay in the poster and do not leave with the MP4, and Copy puts
  the file alone on the pasteboard, with no pixels and no promised TIFF
  (`ROADMAP.md`). Upscale is offered for pictures only, at every entry point.
  `ImageLibraryVideoTests` pins the pairs.
- `LibrarySelection` holds what is chosen; `LibraryCursor` is the pure
  arithmetic of moving through a grid, so keyboard navigation is tested without
  a window. `ImageFacts` formats the rows the inspector shows, the clip's Length
  among them. Every span of seconds on screen — the countdown in the
  window subtitle and the running-run inspector, Elapsed, how long a run took, a
  clip's length in the inspector, the capsule and the badge — is a
  `DurationLabel` (`ZephraCore`): "45 s", "1 min 20 s", "12 min", "1 hr 5 min",
  with a decimal under a minute only where a fraction is a real answer (a clip's
  0.4 s). A per-step pace is a rate, not a span, and keeps its seconds
  ("7.0 s/step").
- Export copies the file, never the bytes in memory, once a picture has one:
  the file is where the favourite, the tags, the albums and the upscale record
  were written, and `ImageExport.exportData(for:)` reads it for Export, Copy
  and a drag alike, embedding the record into the session's bytes only before
  the save has landed. Every copy goes through `ExportPlan`
  (`Sources/Zephra/Support/`), a pure plan of copies, collisions and files
  that are already the file there, so a file is never copied onto itself — a
  save onto the source is a silent no-op — and a batch that would land on
  other files asks Keep Both (numbered the way the Finder does, the default),
  Replace, or Cancel through `ExportCollisionPrompt`. `copyReplacing` writes
  into a hidden sibling in the destination's folder and renames it into place
  (`replaceItemAt` over an existing file, a move otherwise), so the destination
  is whole or absent at every instant and the source is only ever read;
  remove-then-copy is what used to delete an original exported into its own
  folder. Failures are collected into one alert. `ExportPlanTests`,
  `ImageExportReplaceTests` and `ExportDataTests` in `Tests/ZephraTests` pin
  all of it, the middle one on the real filesystem under `Scratch`.
- Copy puts one picture on the pasteboard in every form a paste asks for:
  the file's URL, so the Finder pastes the file; the PNG bytes as they are;
  and a TIFF that is promised rather than written — `PasteboardImage` is an
  `NSPasteboardItemDataProvider` that makes the TIFF only when something asks
  for that type, since four megapixels uncompressed is tens of megabytes
  nobody may ever paste. Several files go on as URLs alone. Plain ⌘C over
  the grid is `LibraryGrid`'s `onCopyCommand`, the responder-chain hook,
  handing out `NSItemProvider`s for the selected files, so the Edit menu's
  own Copy reaches the grid only while the grid has the keyboard and still
  means the text in a field otherwise; ⇧⌘C stays the named "Copy Image".
  Share — the inspector's button, the context menu, and File > Share… — hands
  the same files to the system: `ShareLink` where there is a view to anchor
  on, and `SharePicker` (an `NSSharingServicePicker` over the key window's
  content view) for the menu item, which resolves through `CommandTarget`
  and is greyed out for a canvas picture that has no file yet.
  `PasteboardImageTests` pins the three forms on a private pasteboard.

## The app target's shape

The app is one window — a `Window("Zephra", id: "main")` scene, not a
`WindowGroup` — beside Settings and the two windows About leads to (`AboutScenes`,
below). Everything a window would own (`WorkspaceSelection`,
the caches, the canvas's `current`) is app-wide state built once in `ZephraApp`, so
a second window would only mirror the first; ⌘W closes it and a click on the Dock
icon brings it back, with the Window menu listing it by itself, and
`.defaultLaunchBehavior(.presented)` opens it on every launch, so a session that quit
with the window closed does not come back with none. Per-window state is a ROADMAP
item. It is one process too: `Support/SingleInstance`, from `AppLifecycle`'s
`applicationWillFinishLaunching`, brings a copy already running forward and exits
before a window is up. The system launches an app by bundle identifier when a
notification is clicked and takes whichever copy LaunchServices has registered,
which beside a `make run` build is often the Debug one, and two Zephras over one
library would write over each other. A `ZEPHRA_PREVIEW_STATE` launch is exempt,
since the screenshot builds and the app-hosted tests run beside a real one on
purpose; `SingleInstanceTests` pins the rule.

Four directories, by what a file is rather than what screen it is on:

- `Style/` — the chrome: `ZephraChrome`'s radii, hairlines and heights
  (`fieldRadius`, `fieldHeight`, `barHeight` beside the radii), the colours
  laid over things in `ZephraChrome+Washes` (`badgeForeground` and
  `badgeBackdrop` for a glyph on a picture, `safelightWash` and
  `safelightTint` for the run's surfaces, `hoverWash` over a wall square under
  the pointer, `warningWash` and `warningStroke`
  for `ChromePanel`'s warning, `wellFill`, `wellFillHovered` and
  `wellFillTargeted` for the reference well's empty drop target and
  `wellDash` for its dashed hairline (`ReferencePlaceholder`), `captionShadowOpacity`), `ChromePanel`, `Chip`,
  `SectionHeader`, `CountBadge`, `KeyValueRow`, `WrappingHStack`, `ModelDot`;
  `FactsRow` and `FactsTable`, the one line and the one column every inspector's
  facts are drawn from; `SearchFieldChrome`, the modifier that dresses the
  sidebar's search and the reference picker's alike; and `MenuChevron`, the
  inline chevron a capsule menu's title ends with (a `Menu` reads its label the
  way `Label` does, so a chevron drawn as a view lands in front of the title or
  nowhere, and `.menuIndicator` draws nothing under `.accessoryBar` outside a
  toolbar). A view that reaches for a literal radius or a raw colour belongs
  here instead. Safelight amber means "only while the model works" and appears
  nowhere else. The radii step down by what a thing is: 16 for the capsule, 10
  for the picture in the reference well, 8 for a card or a thumbnail, 6 for a
  field, 5 for a square on the sidebar's wall, so a card reads as a thing to
  act on and a square as a thing to look at.
- `Workspace/` — which pane is up, which query the library is showing, whether
  the inspector is open, and the labels those enums draw themselves with.
  `WorkspaceSelection` is one `@Observable`, injected by the composition root
  and persisted through `AppSettings`.
- `Support/` — caches, exports, pickers, previews. The thumbnail pipeline lives
  here: `ThumbnailKey` names a baked file by path, mtime, size and edge,
  `ThumbnailFolder` is an actor that bakes off the main thread, four at a time
  through a gate that hands a finished bake's slot straight to the next waiter
  (`ThumbnailFolderTests` pins the four), and `ThumbnailCache` coalesces the
  in-flight requests; `ThumbnailRequest`, the identity of a cell's task, names
  the file's mtime and size as well as its path and bucket, so a rewritten file
  bakes again while the old picture stays up. Beside it, `ImageCache` is the
  same shape for the pictures this session made: `cached` for the first frame,
  `load` decoding in a detached task and coalesced by image id and kind
  (`ImageCache+Decoding` is the Image I/O half, injectable for
  `ImageCacheTests`), and `referenceThumbnail` digesting and decoding the
  reference bytes off the main actor. `Views/Canvas/SessionImage` is the one
  view over it — the canvas, the fresh-image inspector and the filmstrip all
  draw through it, holding the request's aspect until the pixels land and
  fading only the canvas's whole picture in — and `Views/ReferenceThumbnail` is
  the well's, keyed on `GenerationStore.referenceChoice`, the ticket every way
  of choosing a picture moves, so nothing hashes the bytes in `body`. Nothing
  decodes an image on the main actor: a drop, the file chooser and every library
  door hand `adoptReference` a closure and the read runs in its detached task.
  `AppSettings` is the one list of preference keys and
  starting values; a preference is bound with `@AppStorage` at its picker and
  read outside a view through `AppSettings`'s helpers. `DirectoryRow` is the
  labelled path with an Open button that General and Models both show, plus
  whatever else that folder can be done to — which in Models is `Change…` and
  `Use Default`, in `ModelsDirectoryRow`. The appearance
  preference is applied by `AppearanceApplier`, set on `NSApp` from the
  composition root rather than as a colour scheme on a scene, so the Settings
  window, the menus, and the alerts change with the main window.
  `CommandTarget` is what the menu bar's file commands — Export, Share, Copy,
  Reveal, Delete, Use as Reference, Animate, Upscale — are about: the canvas's picture while the
  canvas pane is showing one (not while it follows a run, which has no file
  yet), the grid's focused selection filtered to the sections on screen, and
  otherwise nothing, which greys them all out; there is no fallback from an
  empty library selection to the picture hidden behind it. `singlePicture` is
  the one question Animate reads beyond what Use as Reference does: nil for
  none or for several, and otherwise whether the one picture or clip is a
  clip, which is what `animateTitle` says "Animate from Last Frame" from —
  and `ZephraCommands+Library`'s `canAnimateTarget` excludes Recently Deleted
  the same way the two Upscale items do. `StepProgress` is
  the step bar's reading — the loop's own total once it reports, the run in
  flight's steps before that, the next run's only with nothing running — read
  through `GenerationStore.stepProgress` by the capsule, its lip and the
  running card, so the bar never counts the slider. `ReferenceRole`
  (`Support/`) is the one place every string a reference picture's role
  changes — the well's caption and help, its accessibility label, the open
  panel's message, the strength slider's help, and the inspector's row label
  — is spelled, derived from a model's `ModelCapabilities`
  (`.firstFrame` when it makes clips, `.startFrom` when it adjusts reference
  strength, `.reference` otherwise, in that order, since LTX-2.5 is both a
  clip model and a strength-adjusting one and the clip reading wins).
  `ReferenceImageWell`, `ReferenceStrengthControl` and `ReferenceImagePicker`
  all read it from `store.descriptor.capabilities`; `ReferencePlaceholder`
  itself stays a plain view in `Style/` that only takes the words it is given.
  `ModelLoadNote` (`Support/`) is what `GenerateButton`'s tooltip and
  `AnimateButton`'s share: what pressing Generate costs first when the model
  that would run is not the one resident, read against an arbitrary target
  rather than only `store.descriptor`, since Animate's tooltip has to say
  this before Animate has been pressed and the clip model chosen.
- `Views/` — one subfolder per surface (`Canvas/`, `Library/`,
  `Library/Inspector/`, `Library/Viewer/`, `ReferencePicker/`, `Sidebar/`,
  `Sidebar/Timeline/`, `Toolbar/`); the prompt capsule, its controls, the
  commands, and Settings
  sit at the top of `Views/` because they belong to no one surface. The
  three-stored-property rule is what keeps them small; a view that needs a
  fourth wants a subview — `LibraryPaneHeader` holds the filter bar's
  animations for `LibraryPane`, `LibraryGridKeyboard` the arrow keys for
  `LibraryGrid`, each honouring Reduce Motion, as `WorkspaceDetail` and
  `PromptTuckOverlay` do with `.animation(reduceMotion ? nil : .snappy,
  value:)`; the wall's hover wash does not fade at all. The wall's hover wash and its selection ring are `WallSquareChrome`, and both are
  `allowsHitTesting(false)`: a filled shape in an overlay is what the pointer hits, and the
  wash is up exactly when the pointer is over the square, so without that every click on the
  wall landed on the wash and the tile's button never fired — while an accessibility press,
  which goes straight to the action, still worked, so hands-off UAT did not catch it.
  `WallSquareChromeTests` clicks a hosted button through the chrome with a real mouse event,
  and `make lint-layers` keeps `hoverWash` out of every other file. `focusEffectDisabled()`
  on the library grid, the reference picker's grid and the viewer is the one
  exemption from the system's focus ring, deliberate: a ring round a whole pane
  says nothing, and the ring round the selected cell is what shows where the
  keyboard is — which is why an arrow key with nothing selected selects an end
  of the grid (`LibraryCursor`) rather than doing nothing. `SettingsView` is
  four tabs, and `SettingsTab` says how tall each stands: the window follows the
  tab (`.windowResizability(.contentSize)` on the scene) rather than standing at
  the tallest tab's height for all four, and Escape does not close it, which is
  what every Settings window on the Mac does. About is two windows of its own rather than the
  standard panel, the Mac's own pattern (Xcode's and most apps'): `AboutScenes`
  declares `Window("About Zephra", id: "about")` — `Views/About/AboutView`, the
  icon, name, version line, what Zephra is in two sentences (`AppFacts` in
  `Support/`, the one place those strings, the website and the bundle's version
  and copyright are read), an Acknowledgments… button and a Website button, and
  the copyright — and `Window("Acknowledgments", id: "acknowledgments")`, which
  lays `THIRD_PARTY_NOTICES.md` out whole through `NoticesDocument` in `Support/`
  (the parser, with `NoticesParser` behind it, reading exactly the Markdown the
  file uses and keeping its fenced NOTICE and license texts verbatim) and
  `NoticesView`. Neither opens at launch nor is restored. `AboutCommands` points
  the application menu's About item at the first; Settings > About
  (`AboutSettings`) shows the same facts in the tab's shape with the same two
  buttons, and no longer lays the notices out inline, since a tab that opened on
  seven hundred lines of license text read as legal text where a person expected
  to learn what the app was. The notices file is written so it reads right in
  the app too: it names no `LICENSE` file, because none is bundled — the app's
  own terms are the copyright line's "All rights reserved" until terms are
  decided (`ROADMAP.md`). A keyboard shortcut has one owner, the menu bar
  (`ZephraCommands`, `WorkspaceCommands`, `LibraryCommands`,
  `ThumbnailSizeCommands`); a button that shows a chord shows it as text, the
  way `GenerateButton` writes ⌘⏎, and never declares it too, because a chord
  declared twice is one stray SwiftUI change from firing twice. Return in the
  library belongs to the grid's `LibraryOpenCommand` alone. The only
  `.keyboardShortcut` outside the menu bar are a sheet's own `.defaultAction`
  and `.cancelAction`, which is a key loop of its own. File > "Stop
  Generating" is `EngineState.stopCommandTitle`, so the item names what it
  stops ("Cancel Download", "Stop Building", …), and File > "Export…" (⇧⌘E)
  is what was "Save as…": the picture is already on the disk, and nothing is
  a document with changes to keep. `SeedControl`'s label is `SeedLabel`, a
  button: it opens `SeedEntryPopover`, where a seed is typed as the number the
  tooltip shows or as the short hex label off another picture's inspector,
  and `SeedEntry` (`Support/`) is the one parser — digits are decimal, a hex
  letter, a `0x` or the label's middle dot make it hex, eight hex digits are
  the label and come back as the seed's leading half over zeros, sixteen are
  the whole value, and any other count is refused rather than guessed at
  (`SeedEntryTests`). How a seed is spelled on screen is one preference,
  `AppSettings.seedFormat`, a `SeedFormat` in `ZephraEngine` beside
  `shortSeedLabel`: the short hex label by default, or the whole number, set
  in General under "Show seeds as". The root puts it in the environment as
  `\.seedFormat` through `SeedFormatPreference`, and every seed on screen —
  the chip, the popover's prefill (the whole value in that spelling, so
  Return keeps the seed it had) and its hint, `ImageFacts`' Seed row through
  `LibraryFactsView`, `FreshImageInspector` and `SharedFactsView`, and the
  running run's column — reads that one value. Nothing on disk follows it:
  the record, the file name and the search key keep the number, and the
  search key carries the label too (`SeedFormatTests`).
  `ImageFactsView`'s reference row is `ReferenceFactsRow`
  (`Library/Inspector/`): the source model's own `ReferenceRole` label
  ("First frame", "Started from", "Edited from"), a 40 pt thumbnail, the
  strength ("Strength 0.60", or "Held exactly" for a clip whose strength is
  0), and a "Show Source" button when `ImageFacts.referenceOrigin` names a
  file `LibraryIndex.item(named:)` still finds. `LibraryFactsView` and
  `FreshImageInspector` each work out the role from the *record's* model —
  `ModelCatalog.descriptor(id:)?.capabilities`, not the model currently
  chosen in the picker — and hand `ImageFactsView` a `ReferenceFactsRow.Source`
  naming either a `LibraryItem` or bytes already in memory; `ImageFactsView`
  itself stays at two stored properties, facts and that optional source. The
  thumbnail is never read on the main actor: `LibraryItem.referenceImage` is
  a synchronous whole-file read, so `ReferenceFactsRow` runs it inside a
  detached task started from `.task(id:)` and hands the bytes to
  `ImageCache.referenceThumbnail(_:)` for the decode, the same door
  `ReferenceThumbnail` uses for the well; a session's own picture already has
  its bytes in memory and only needs that decode. `Support/BackgroundNotice` is what a change of engine
  state is worth telling the Mac about while another app is in front: a
  download that ended in a build, a load or a ready model finished, one that
  ended in a failure failed, and one the person stopped says nothing; it is a
  pure function over two states, pinned by `BackgroundNoticeTests`, and
  `BackgroundNoticeObserver` on `RootView` feeds it every transition. A saved
  image is the other notice, posted from the `onImageSaved` wiring in
  `ZephraApp+Library`, titled "Image Saved" or "Clip Saved" and carrying the
  prompt folded to one line and cut at a word (`BackgroundNotice.summary`),
  since the file name is a stamp and a seed and says nothing to a person who
  walked away. `BackgroundNotices.post` is the one place
  `UNUserNotificationCenter` is touched: it posts only when `NSApp` is not
  active and the General toggle (`AppSettings.backgroundNotifications`)
  allows, and asks permission the first time it has something to say rather
  than at launch. `Sidebar/CanvasSidebar` is the canvas sidebar,
  which builds today's runs once and hands them to `Sidebar/Timeline/` — a
  card per run still waiting, the running run's card in amber, and under those
  the wall of today's pictures in small squares — and to the "Today in
  Library" bar pinned at its foot. `SessionTimeline` in `ZephraEngine` works
  out the runs and lays the wall as one flow, newest run first, of finished
  pictures only (a block per run ended every batch's row early and made the
  wall ragged); a seed still to come has no square there at all, only the
  running card's own step segments above the wall, and its finished squares
  join the wall at the running run's head, adjacent, the moment they land.
  `TimelineRun.seedCount` is what a waiting run's card counts instead, since
  it has no tiles yet to count. Nothing here filters, groups, or sorts. The inspector is `WorkspaceInspector`, a
  fixed column `WorkspaceDetail` puts beside whichever pane is up, under the
  toolbar rather than splitting it, and only when it has something to
  describe: always in the library, on the canvas only while a picture is
  showing (`GenerationStore.hasPicture`, which the toolbar toggle and the menu
  read too). `Library/Inspector/` describes the grid's selection and
  `Canvas/CanvasInspector` the picture on the canvas, which is the library's
  own inspector once the file is indexed and `FreshImageInspector` until then.
  An empty canvas shows `CanvasEmptyState`, with the last three prompts from
  the index (`RecentPrompts`, nothing persisted) as chips. `CanvasStateView`
  is what the canvas says otherwise, centred, and in a floating panel when a
  picture is under it; the one state that steps aside is a model that simply
  is not loaded over a picture, which sits at the top edge with its Load
  Model button so a picture opened from the sidebar is seen and not covered. On Liquid Glass
  the window toolbar floats over content by default, so `RootView` forces
  its background visible (`.toolbarBackgroundVisibility(.visible, for:
  .windowToolbar)`), making it an opaque full-width strip with a hairline
  under it; `CanvasView` no longer ignores the vertical safe areas, and
  `WorkspaceDetail`'s `HStack` (the pane, its `Divider`, and the inspector)
  stays inside the top one too, so the sidebar, the pane, and the inspector
  all start below the strip rather than the divider cutting through it.

  A clip plays where its poster would be: `Canvas/ClipPlayerView`, an
  `NSViewRepresentable` over AVKit's `AVPlayerView` with no transport controls,
  fed by an `AVPlayerLooper`, muted, over the MP4 beside the poster — on the
  canvas once the save has landed and `fileURL` says where (the poster shows
  until then), and in the library viewer through `Library/Viewer/LibraryViewerClip`
  for any item with a `videoURL`. Both play on while a run is in flight: H.264
  decode is the media engine's work and not the GPU's, and a clip that stopped
  the moment Generate was pressed read as broken. SwiftUI's
  `VideoPlayer` was tried first and rejected twice over: its controls take the
  click that tucks the prompt, and linked only through SwiftUI it aborted the
  first clip resolving its superclass, which is why `project.yml` still names
  `AVKit.framework` in the app's link rather than leaving it to autolink.
  `Style/VideoBadge` is the clip's mark on a grid cell and a sidebar square, in
  the corner `UpscaleBadge` uses, since a picture is one or the other. The
  capsule shows `DurationControl` — the shortest clip, then one choice per
  whole second, each snapped to the model's ladder (9, 25, 49, 73, 97, 121
  frames at 24 fps) — only when `frameBounds` is a range, and hides
  `StepsControl` when `stepBounds` is a single value, the way it already hides
  guidance: a slider over one value is not a slider, and LTX-2.5's eight steps
  are the checkpoint's. The inspector's Length row comes from `ImageFacts`.

  Every picture in the app wears the same right-click menu: `LibraryItemMenu`
  for anything indexed — the grid, the sidebar wall, the library viewer, and
  the canvas once the file has been indexed — and `FreshImageMenu` for a
  session's own picture before that indexing has caught up, both in
  `Views/Canvas/` beside `CanvasImageMenu`, which picks between them for
  whatever the canvas is showing. `LibraryItemMenu`'s `selection` is optional,
  taken only where there is a `LibrarySelection` to keep in step with the
  choice; the sidebar wall and the canvas have none and pass nil.
  `LibraryIndex.canvasItem(for:)` is the one lookup behind that choice and
  behind `CanvasInspector`, so the two never disagree about what the picture
  on the canvas is; deleting it from either fires
  `LibraryIndex.onRecentlyDeleted`, which `GenerationStore.forget(fileAt:)`
  answers by stepping the canvas to the next image in history.

  Animate sits beside Use as Reference everywhere a single picture's actions
  are offered — `LibraryItemMenu`, `FreshImageMenu`, `InspectorActions`,
  `FreshImageActions`, and the menu bar's own Animate item (⌥⌘A) — and both
  show **disabled rather than hidden** when the model, or this build, cannot
  take them, the macOS convention: a build with no clip model still shows
  Animate, greyed. `AnimateButton` (`Views/Library/`) is `LibraryItemMenu`'s
  and `InspectorActions`'s button, titled "Animate" for a picture and
  "Animate from Last Frame" for a clip (`item.isVideo`); `FreshImageMenu` and
  `FreshImageActions` wire the same rule inline, since neither has a
  `LibraryItem` to hand the button. Both paths go through
  `ReferenceAdoption.animate(_:into:)`, one overload per kind of picture,
  never `adopt(_:into:)`: an edit hands back its own source under `adopt`,
  which is right for "use this as a reference" and wrong for Animate, which
  means exactly the picture in front of you. A clip's last frame — what
  Animate reads instead of the poster, since the poster is only the first
  frame — is `ClipFrames.lastFrame(of:)` (`Support/`): `AVAssetImageGenerator`
  asked for the frame a step before the asset's duration, tolerant a step
  either side, its bytes re-encoded through `ReferenceImageEncoder` like
  every other door into the well.

  A double-click in the grid, or Return on the selection, no longer opens the
  canvas — it opens `Library/Viewer/LibraryViewer`, the picture full size in
  the library pane itself, with `LibraryViewerBar` stacked above it ("Library"
  back, "n of N", previous/next) — stacked, not inset, so the picture is fitted
  to the height under the bar — `ViewerPlaceholder`, the grid's thumbnail at
  the picture's own aspect, standing in until the decode lands, and `LibraryViewerNavigation` underneath
  (Escape or a second double-click closes it; the arrow keys step, crossing
  day headings the way the grid's own do, through the pure arithmetic in
  `ZephraEngine`'s `LibraryViewerStep`). `WorkspaceSelection.viewing` names
  the one item shown, cleared whenever the pane changes; `LibraryPane` is the
  one place that keeps the grid's selection in step with it, so the inspector
  beside the viewer always describes what is on screen and closing scrolls
  the grid back to it. "Open in Canvas" — the `\.openLibraryItem` action, on
  the cell's menu, the sidebar wall, and the inspector's own button — is
  unchanged; the viewer answers to the twin `\.viewLibraryItem` instead.

  What the canvas shows while the model works is decided by one question,
  `GenerationStore.isShowingRun`. While it is following, `CanvasView` draws
  `Canvas/LivePreviewView` — the run's own frames, a `CGImage` over the RGBA8
  bytes, `.medium` interpolation because a frame is an estimate, letterboxed
  into the run's own aspect so the finished picture lands in the rectangle its
  frames were filling. Before the first frame `Canvas/RunPlaceholderView` sits in
  that rectangle: a still safelight card, the system spinner, and the phase in
  words. Still on purpose, and `make lint-layers` keeps it so: **nothing in the
  app target may run a repeating animation**, because while the model works the
  GPU is the model's. A breathing opacity animation there, sixty composited
  frames a second over a streamed Qwen-Image step, took a 16 GB M4 mini's GPU
  down every time — a GPU restart the driver blamed on whichever command buffer
  was in flight, which MLX turns into an uncaught C++ exception on Metal's
  completion queue, so the app aborted a step in. Reduce Motion off, the same
  launch crashed at 38 s; on, it made its picture in 144 s. The system's
  indeterminate spinner stayed on screen through that run and is fine. There is
  no context menu and nothing to drag, because there is no file yet; a click
  still tucks the prompt away. The run is not over when the steps are: the
  backend reports `.decoding` while the latents are developed and, for a clip,
  `.saving` while the frames are encoded, tens of seconds on a 121-frame clip,
  and the last frame sits still meanwhile. `EngineState.isFinishing` is that
  stretch, and everything that reads the run reads it: `StepProgress` keeps
  the bar up and full, `Canvas/FinishingNote` floats the phase with the
  system spinner at the top of the frame (after a second, so a half-second
  decode flashes nothing), the inspector's Steps row says "8 of 8" and its
  Left row says the phase, and `StepTimer` lets the loop's pace ride on those
  events so Elapsed keeps its figure. The phase is worded for the kind of run
  (`detail(clip:)`, `generationPhase(clip:)`, `subtitle(for:clip:)`, from
  `GenerationStore.runMakesClip`): "Developing the clip" and "Encoding the
  clip" against "Developing the image" and "Saving". The capsule's `StepSegments` ride its top edge
  inset by `ZephraChrome.capsuleRadius`, on the lip too, so the corners' curve
  clips no segment; `StopButton` beside Generate is a bordered "Stop" in
  safelight; the size menu and the seed count show their chevrons, and the
  count says what it counts ("4 seeds"). The controls under the prompt stay
  live while the model works, as the prompt does: a run carries its own
  settings, so a size, seed or strength moved mid-run is the next run's, and
  Generate queues it. The tuck is `Canvas/PromptTuckHost`'s,
  and it is visual only: `PromptTuckOverlay` slides the capsule under a lip and
  the prompt's text view stays first responder underneath it — the host hands
  it the caret as the prompt tucks and never takes the keyboard itself — so
  whatever is typed lands in the real editor, composed input included, and the
  first change to the prompt brings the capsule back; Escape arrives as
  `cancelOperation:` through `onExitCommand`. It once focused itself and
  appended raw characters to the prompt, which broke every input method that
  composes.
  `Canvas/RunningRunInspector` is the column beside it: prompt, model, size,
  the step of how many, seed, elapsed and left — the last two from the pace
  `store.state` already measures rather than a clock of the view's own — and
  Stop. When it is *not* following, the picture is on the canvas at full
  strength even with the model running; the dim to 60 % went with the frames,
  which say "this is not the new one" properly.
  `Sidebar/Timeline/RunningRunCard` is the way back: a button calling
  `watchRun()`, which also puts the run's settings back in the capsule after a
  square on the wall (`RunTile`, through `GenerationStore.select(_ item:)`)
  replaced them with its picture's, still amber, wearing the accent ring the
  wall's squares wear when the canvas is showing the run — and no square wears
  it meanwhile —
  with `RunPreviewThumbnail`, the newest frame at 36 pt, at its leading edge,
  so a run is worth glancing at while you are looking at something else.
  `GenerationPreview.makeImage()` in `Support/` is the one place bytes become
  an image, and each view keeps the result until the bytes change: `body` runs
  on every progress update and frames arrive far more rarely.

The prompt is `PromptTextView`, an `NSTextView` of our own on TextKit 1 rather
than `TextEditor`, for one reason: a text view paints a selected line break out
to the trailing edge of its container, which in the capsule is the whole prompt
area, and `PromptLayoutManager` clips every selection rectangle to the line's
used width instead. `CapsuleTextView` underneath it stays as tall as its clip,
so a click in the empty part of the band still places the caret, and reports
focus from the responder chain rather than from the delegate's editing
callbacks, which are not sent for a click in and straight back out.

Albums are made and filed from the library sidebar, and both of those are worth
knowing about before touching `Sidebar/`:

- An album is made by `NewAlbumBar`, pinned at the foot under
  `RecentlyDeletedRow`, or by ⌘N, and it is named in its own row rather than in
  an alert. The album is created first, called "Untitled Album", and what
  follows is a rename of a real album — so `AlbumEdit` has one naming path
  instead of two, and Escape leaves the album behind the way the Finder leaves
  "untitled folder". `SidebarView` owns that one `AlbumEdit`, above both the
  list and the bar, because the making and the naming happen in different
  views. Only the deletion still asks in an alert.
- `AlbumNameField` enters its own focus in `.task`, after one `Task.yield()`.
  In a `List(selection:)` the first click selects the row rather than reaching
  the field, and focus set on the list's first pass — before the row is in a
  window — is dropped. `NSTextField` selects all on programmatic focus, which
  is what puts "Untitled Album" under the cursor ready to be typed over.
- Images are filed by dragging them from the grid onto an album row.
  `LibraryItem`'s `Transferable` exports `LibraryItemReference` first and the
  file second: a `FileRepresentation` cannot be received by a
  `dropDestination`, and inside the app the id is what is wanted anyway. The
  type is `io.zephra.library-item`, declared in
  `Sources/Zephra/Resources/Info.plist` under `UTExportedTypeDeclarations` —
  `UTType(exportedAs:)` is only the reading half of that. A drag that started
  inside the grid's selection files the whole selection, the rule
  `LibraryGrid.targets(for:)` already uses; `AlbumDropTarget` reads it through
  `@FocusedValue(\.librarySelection)`.
- ⌘N reaches `SidebarView`'s state through `@Entry var newAlbum` in
  `FocusedValues`, an action rather than a piece of state. The menu bar cannot
  see a view's `@State`, and putting album state in `ZephraEngine` or in
  `WorkspaceSelection` would put interface bookkeeping somewhere it does not
  belong. Publishing nothing on the canvas is what greys the menu item out.

## Adding a model or a backend

This is the seam priority 2 exists for. Both cases are additive: no view and
nothing in `ZephraEngine` has to learn the model's name. (Adding Qwen-Image did
touch both, once each, for behaviour that turned out to be family-generic: a
cross-family switch takes the new family's schedule, and the tiling caption
reads the model's own peak.)

**A model an existing backend can already run** — one entry in that family's
`Packages/ZephraKit/Sources/ZephraCore/Model/ModelCatalog+<Family>.swift`
(Z-Image's two are in `ModelCatalog.swift` itself), listed in `all` in
`ModelCatalog.swift`. `ModelDescriptor` carries where the weights come from
(`ModelSource`: a Hugging Face repo or a local directory), the download and
resident sizes,
and a `ModelCapabilities` the interface draws itself from — size presets and
bounds, step and guidance bounds, whether a negative prompt or a seed does
anything, and for a model that makes clips the frame bounds, default, ladder
and rate (`frameBounds`, `defaultFrames`, `frameAlignment`, `frameRate`), a
range in the first being what draws the length control and says the backend
answers `GeneratedMedia.video`. Every number in an entry is hand-written because every number is
measured; leave a comment saying where a figure came from. `ModelMenu` lists
`ModelCatalog.all` and `GenerationStore.switchModel(to:)` does the rest.

**A new backend family** — four things in the app, then the tooling:

1. A `static let` on `BackendID` in `.../ZephraCore/Model/BackendID.swift`
   (it is a string-backed struct, not an enum, so a persisted setting naming
   an unknown family still decodes).
2. A package under `Packages/`, alongside `ZephraBackendZImage`, whose one
   public type conforms to `ImageGenerationBackend` and whose one public
   entry point is a `BackendFactory` (see `ZImageBackendFactory`). It may
   import whatever it needs; nothing above it may.
3. Catalog entries naming that `BackendID`.
4. One line in `Sources/Zephra/ZephraApp.swift`:
   `registry.register(.yourFamily, YourBackendFactory.make(environment))` —
   the `InferenceEnvironment` the root read once — and
   `YourBackendFactory.runtime` in the `CombinedInferenceRuntime` list beside
   it — `MLXInferenceRuntime` over the family's own `VAETileSetting`, the way
   the four factories build theirs; no family writes a runtime type of its
   own, and no kit reads an environment variable. That file is the only place
   in the app target allowed to name a concrete backend.

Then the places that are not the app, each a one-line switch case or list entry:
the package and target dependencies in `project.yml`, `MLX_PACKAGES` in the
`Makefile` so `make test-mlx` runs its suites, `QuantizeFamily` in
`Sources/ZephraQuantize` if the family has a packing plan, `BenchBackends`
in `Sources/ZephraBench` so `--model` can name it, and the family lists in
`make lint-layers`, which name every family by hand and lint nothing they do
not name.

A saved choice that is no longer on the disk — a local build deleted from
Settings > Models, or a preference carried to a Mac that never made it — is not
loaded into a failure: `bootstrap` reads availability first and
`GenerationStore.fallBackIfUnobtainable()` steps onto the first model this Mac
can run and does have. A model that merely needs a download is kept, since
choosing it chose the download. The chosen model is persisted from the
composition root's `onChange` of `store.rememberedModel`, not by the menu, so
the model the engine stepped onto is the one the next launch opens on — and a
model only looked at through a picture is not: `rememberedModel` is the loaded
one while `modelAwaitsGenerate` (below) says the choice is waiting.

Selecting a picture chooses its model without loading it. `select(_ image:)`
and the sidebar's `select(_ item:)` move `descriptor` onto the model that made
the picture, when the catalog still knows it, and take its settings wholesale
(not clamped: a strength of 1 that says "no picture" would be pinned into the
slider's range); the menu and the capsule then say what Generate will run,
while `modelAwaitsGenerate` keeps the loaded weights where they are — looking
at pictures made by three models must not swap weights three times. `drain()`
on an empty queue, which otherwise brings the loaded model in line with the
chosen one when a run ends, leaves it alone while the flag is up. Every
explicit choice clears the flag: Generate (the drain then swaps to the first
entry's model as it always did), a pick in the menu (`switchModel`, which
swaps nothing when the pick is the model already loaded, and which takes a
pick of the model the menu already shows as "load it now" when that model is
waiting — the one way a person has to say so), a variation, and a load that
lands on the chosen model. `retry()` over another model's weights — a run on
them failed, and a picture's model was chosen since — goes through `reload`
so the old lease goes back rather than a bare load leaving it held, and
Resume on a download row takes the retry branch only while nothing is
loaded. A menu pick cancels a square's read still in flight, and abandons
a picture still on its way into the well (an Animate whose read has not
landed), so neither lands on top of it. The running card's `watchRun()` restores the run's
model the same way, which is the loaded one, so nothing waits. While the
flag is up, the Generate button's tooltip says what pressing it loads or
downloads first, and the canvas headline, the window subtitle and the
background notice name `modelInUse` — the loaded model, or the one on its
way in — rather than the chosen one. A picture from a model this build has
dropped keeps the current model and takes its schedule, clamped, as a
variation of one does. `GenerationStore.animate(origin:read:)` chooses the
clip model by exactly this rule, so Animate never swaps weights either; see
"Starting from a picture". `DeferredModelTests` and `DeferredModelEdgeTests` pin
all of it, `AnimateTests` the animation's half.

`InferenceActor` keeps one backend at a time and rebuilds it whenever a
descriptor names a different family, so the old weights are always released
before the new ones are asked for. A descriptor whose family was never
registered surfaces as `EngineError.noBackend`, not as a crash.

`ImageGenerationBackend.availability(of:locations:)` must answer from the disk
alone — never download, never disturb what is loaded. It is what lets the picker
say "13.3 GB download" without starting one.

Every disk-touching call takes a `ModelLocations`: one root, with
`Downloads/<org>--<repo>` for what was fetched and `<descriptor id>` for what
was packed here, plus `previous`, the last few roots the folder was set to
before, which are read-only fallbacks unless an explicit migration is requested,
and a model a person already has is never fetched again because a setting
moved. It is passed down rather than read from a preference at the bottom —
`InferenceActor` pins it per `prepare`. Settings uses
`GenerationStore.changeModelDirectory(to:moving:)`, which gates new work and cancels
and awaits pending preparation before switching destinations. The low-level
`setModelLocations(_:)` applies startup preferences without interrupting work, and
`Sources/Zephra/ZephraApp.swift` is the only place that knows the preferences
`AppSettings.modelsDirectory` and `previousModelsDirectories` decided it. A
backend looks in the built variant, then `locations.downloads` under every
root, then the hub cache, and only then downloads.

**A model whose download is not what gets loaded** is the third case, and all
four families now have one: FLUX.2 klein's two variants, LTX-2.5's, the 4-bit Z-Image
Turbo, and the 4-bit Qwen-Image. In each the release is bfloat16 and the loader
reads a packed variant. Such a family implements
`ImageGenerationBackend.build(_:at:locations:onProgress:)`, which the engine calls
between `ensureAvailable` and `load` and shows as `EngineState.building`; every
other model takes the protocol's default, which returns the download
untouched. `ModelDescriptor.builtBytes` says what the packed variant costs on
disk, and non-zero (with a repository source) is `isBuiltLocally` — what tells
the engine a build is involved. Availability
then has two more answers, `.needsDownloadAndBuild(bytes:)` and `.needsBuild`,
so the picker says what choosing the model will cost. The packed variant lives
at `locations.built(descriptor)`, which is `<models>/<descriptor.id>` — the
naming every locally built variant already follows. The packer's `shouldContinue`
hook is what makes a build stoppable between tensors.

**A built variant that is published ready-made** is the shortcut in front of that
case, and every locally built entry takes it. `ModelDescriptor.mirror` names a
`ModelMirror`, the one static directory `ModelCatalog.mirror` points at
(`https://zephra-assets.urandom.io/models`, the `models/` prefix of the
`zephra-assets-urandom-io` bucket, written by `make mirror` and synced by
`make mirror-sync`), and `isPublishedPrebuilt` is that plus `isBuiltLocally`. A
backend that has neither the packed variant nor the release asks
`ModelAcquisition.fetchPrebuilt` before it asks `fetch`: the downloader reads the
mirror's `index.json`, takes the variant's file list only when the index's
`source` is word for word what `PackedProvenance.identity` stamps for this
catalog's descriptor, fetches the files into the built directory's `.partial`
sibling as a `RepositoryDownload` whose `origin` is `.mirror` — the same lane,
`Range` resume, space reservation and single writer as a release, through
`ModelTransfers` in the app — checks each against the index's SHA-256 before it is
renamed into place (`checksumMismatch` discards it and the retry fetches it
again), and moves the directory to `locations.built(descriptor)` when the last
file is down. `build` then finds the variant and packs nothing, so the release
never lands on the Mac; availability says `.needsDownload(bytes: builtBytes)`
rather than `.needsDownloadAndBuild`. The mirror is a shortcut and never a
dependency: `fetchPrebuilt` answers nil for any reason at all — no mirror on the
descriptor, no index, a variant not listed or listed as packed from something
else, a host that is down, a transfer broken past its retries, no room — and the
backend goes on to the release and the build exactly as before, with a line in
the log and nothing on screen. An index that cannot be read is
`mirrorUnavailable`, permanent on purpose, so a mirror that is down costs one
request and not five tries. The release stays on the descriptor because it is
still where the weights came from and the way to build them when the mirror has
not got them. `ModelDownloaderTests+Mirror` pins all of it against the stub hub.

Three pieces of that job are written once, because they are the same job
whatever is being packed. `SnapshotBuild` in `ZephraQuantization` writes into a
sibling `.partial` directory and renames on success, removes it when the build
fails, and refuses before reading anything when the volume cannot take
`builtBytes` — a component that ran out of disk half way reads as a snapshot to
a loader, which is the one failure that produces a model that loads and is
wrong. `BuildTally` in `ZephraCore` turns the packer's log lines into a bar
weighted by what each component holds, so a family supplies a dictionary of
gigabytes and nothing else. And `LocalSnapshot.downloadedRelease(of:in:)` in
`ZephraSnapshot` is the "is the download here" question: the app's own folder,
then the hub cache, with the descriptor's adapters counted. A family's own
`<Family>SnapshotBuild` is then the plan, the weights, and nothing else.

**A model whose build needs more than the release** is the fourth case, and
Qwen-Image is the one that has it. `ModelDescriptor.adapters` is a list of
`ModelAdapter` — a repository, a revision, one file name, and its size — fetched
into `locations.adapter(_:)` (`Downloads/<org>--<repo>`, beside the releases) by
the same `ModelDownloader.fetch` call, in one transfer with one progress bar,
because `ModelDownloader.download` takes a list of `RepositoryDownload`s and
lists and tallies them together. `transferBytes` is the release plus the
adapters, what a Mac with nothing cached is told; a release already here — in
the models folder or the hub cache — is never fetched again for want of its
adapter, so availability charges only what `ModelLocations.bytesToFetch` says
is still missing, and `fetch` moves only that. An adapter counts as here under
any root the folder has been or in the hub cache, where `hf download` puts it
(`ModelLocations+Adapters` in `ZephraSnapshot`, since `ZephraCore` knows no
cache), so one fetched by hand beside its release is not fetched twice. The
adapter is a build input, not a runtime one: `QwenImageBackend.build` hands
`locations.adapterFileOnDisk(_:)` to the plan, the packer merges the low-rank update as it goes, and nothing downstream
ever sees an adapter.

**A model that edits** reads `GenerationSettings.referenceImage`, PNG bytes the
interface caps at 1024 pixels an edge before they land there.
`ModelCapabilities.supportsReferenceImage` is the gate: `clamp` drops the
picture for any model without it, and the well beside the prompt shows only for
a model that has it. The picture is persisted in a second PNG chunk beside the
record and comes back when the image is selected. Every model the catalog ships
reads one, in one of the three ways the next section describes.

The well offers three doors to a picture, and `ReferenceAdoption` in
`Sources/Zephra/Support/` is the one place all three read the file through: a
library image hands back what it was itself edited from, when it was one,
rather than itself. It holds no state: which choice is current is the store's
own bookkeeping (`GenerationStore.claimReference`, `adoptReference`), numbered
when the choice is made rather than when its bytes arrive, so a slow library
read or a drop's provider can never land on top of a choice that came after
it. Empty, the well is a `Menu` whose primary action opens
`Views/ReferencePicker/ReferencePickerSheet`, a sheet over the window with a
search field and a grid of the whole library — what was made here and what was
imported to start from, everything but Recently Deleted — newest first; filled, the same
two choices — "From Library…" and "Choose File…" — sit in a context menu
beside Clear. The sheet's grid walks with the arrow keys: `ReferencePickerKeyboard`
runs the same `LibraryCursor` arithmetic as the library grid over one section of
the matches, with `GridColumns.count` (in `Support/`, shared with `LibraryGrid`
and tested) saying what a row holds, and a down arrow in the search field hands
the keyboard to the grid, on the first picture when nothing is picked; the cells
share the row's width so the gaps are one 10 pt everywhere. Both states also take a drop of a `LibraryItemReference`, the
same in-app drag type an album row accepts, so dragging a picture from the
grid or the sidebar's wall onto the well works the way dropping a Finder file
already did.

## Build & run

Prerequisites, on a fresh Mac: the full Xcode 26 `Xcode.app` selected with
`xcode-select` (the Command Line Tools cannot compile Metal), its license
accepted and `-runFirstLaunch` done, the Metal toolchain downloaded once with
`xcodebuild -downloadComponent MetalToolchain`, and `xcodegen` on `PATH`
(`brew install xcodegen` or `nix profile install nixpkgs#xcodegen`).
`make doctor` checks each and prints the fix.

The Xcode project (`Zephra.xcodeproj`) is generated by `xcodegen` from
`project.yml` and is gitignored. Never edit the generated project — edit
`project.yml` and regenerate.

mlx-swift's Metal kernels require `xcodebuild`; plain `swift build` cannot
build the app target or `ZephraBackendZImage`. `swift build` / `swift test`
only work for `Packages/ZephraKit` (`ZephraCore`, `ZephraSnapshot`,
`ZephraEngine`), which has no MLX dependency by design.

Makefile targets:

- `make doctor` — check the prerequisites above and print the fix for any
  that is missing. Exit status is the number of failures.
- `make gen` — regenerate `Zephra.xcodeproj` from `project.yml`.
- `make build` — generate, then `xcodebuild` the `Zephra` scheme
  (`CONFIG=Release` by default).
- `make run` — build, then open `build/Release/Zephra.app`.
- `make open` — generate, then open the project in Xcode.
- `make bench` — build and run `ZephraBench` (`ARGS=...` to pass flags).
- `make test` — `swift test` in `Packages/ZephraKit` (Core, Snapshot, Engine
  and Media, fast, no MLX). Anything testable without Metal belongs here.
- `make test-app` — `xcodebuild test` of `ZephraTests`, the app target's own
  suites in `Tests/ZephraTests`, hosted inside the Debug app. The first run
  builds the Debug app, Metal kernels included, and takes minutes; after that
  it is a link plus the tests.
- `make test-mlx` — `xcodebuild test` over every package that links MLX
  (`MLX_PACKAGES` in the Makefile, written `directory:scheme`). Slower, needs
  `xcodebuild`. `make test-backend` is kept as an alias. Keep `make test`
  MLX-free.
- `make icon` — resize the approved Zephyr PNG masters in `design/branding/zephyr/`
  into `AppIcon.appiconset` and the website icons/marks with `scripts/make-icon.swift`.
  The dark master is the standard Finder/Dock icon; both appearances are retained
  for the website. Do not replace the selected artwork with a procedural glyph.
- `make signed-build` — build Release and sign the app with a Developer ID
  Application identity. Sources `~/Documents/Zephra Signing/signing.env` when present.
- `make release` — build Release, sign with a Developer ID Application identity
  (hardened runtime, secure timestamp), verify, and package `build/Zephra.zip` plus
  signed `build/Zephra.dmg` with an Applications shortcut. The DMG file and mounted
  volume use the app's compiled `AppIcon.icns`; `verify-dmg.sh` checks the volume
  icon matches the bundled app and that the volume custom-icon flag is set. Secure timestamping
  needs Apple's server. `SIGN_IDENTITY` overrides the auto-detected certificate.
  `VERSION=MAJOR.MINOR.PATCH` and `BUILD_NUMBER=<positive integer>` stamp the
  bundle (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, passed to `xcodebuild`
  on the command line and refused by `build` when malformed); without them the
  build carries `project.yml`'s defaults, which is what an ordinary build gets
  and where they are never bumped for a release. The app is unsandboxed and
  Developer ID only, never an App Store build. The release workflow
  (`.github/workflows/notarized-release.yml`, dispatched by hand) is the same
  path with the gates in front: `make doctor`, `make lint-layers`, `make test`,
  `make test-app` and `make test-mlx`, then `make release` with the dispatch
  input as `VERSION` and the run number as `BUILD_NUMBER`, then `make notarize`.
- `make notarize` — submit the ZIP, require Accepted, staple and verify the app,
  then rebuild both packages. Submit the signed DMG separately, staple it, and
  verify its ticket, image checksum, signature, and Gatekeeper assessment. It reads
  App Store Connect API-key variables from the signing config, or falls back to
  the keychain profile named by `NOTARY_PROFILE`.
- `make notarized-release` — produce the notarized DMG and ZIP; packaging and
  notarization run sequentially even with `make -j`.
- `make ship` — the whole pre-release ship in one go, and **how releases are
  done until further notice**: no version bumps. Zephra is pre-release, so
  every build is `0.1.0`, `project.yml`'s default, and what tells one build
  from another is the build number, the UTC minute the build started
  (`YYYYMMDDHHMM`, `date -u +%Y%m%d%H%M`), so the file is
  `Zephra-0.1.0-<stamp>.dmg`. `ship` runs `publish-release` with those two,
  which builds, signs, notarizes both packages, uploads the DMG to the
  releases prefix of the assets bucket under that immutable name and verifies
  the public download, writing `product-mockups/app/release.json`; then
  `deploy-production`, so the site's Download button names the new file.
  Commit `release.json` afterwards. The upload refuses a name that already
  exists with other bytes, which is why the stamp is a minute and not a day;
  a stray build published under another version is deleted from the bucket
  by hand (`aws s3 rm`), never overwritten. When a version bump is wanted,
  the user says so; nothing here bumps one. When a packed variant has been
  rebuilt under a changed plan or pattern list (`make mirror-<family>
  FORCE=1`), `make mirror-sync` runs with the ship and not before: the
  released app matches the mirror index's `source` to its own descriptor word
  for word, so a mirror that moves ahead of the app sends every user of the
  old build to the release and a local build instead. LTX-2.5's variant with
  the video encoder is waiting in `MIRROR_DIR` for exactly that sync.
- `make prefetch` — download the default model weights with `hf download`
  into `$(MODELS_DIR)/Downloads/mzbac--Z-Image-Turbo-8bit`, which is where the
  app itself would have written them, so a first launch finds them. Set
  `MODELS_DIR` when Settings names another folder.
- `make prefetch-flux2` — the same for the FLUX.2 klein 4B release, without the
  7.75 GB single-file checkpoint the loader never reads, so a first launch skips
  the download and goes straight to the build.
- `make prefetch-ltx2` — the four LTX-2.5 files the video-only build reads (the
  distilled transformer, the connector, the Gemma 4 encoder with its tokenizer,
  the convolutional decoder; 69 GB) from the ungated `mlx-community/ltx-2.5-mlx`
  pack into `LTX2_MODELS` (external storage by default), as the app names it.
- `make prefetch-qwen` — download Qwen-Image-2512 and its four-step Lightning
  adapter into `QWEN_MODELS` (external storage by default; 57.7 GB does not
  belong on a boot volume, and this release is a build source rather than
  something the app loads). Name the adapter file explicitly: the repository
  also ships whole merged checkpoints of twenty gigabytes each, and pulling it
  whole costs 101 GB.
- `make quantize` — the build the app does on first load, by hand: download the
  bf16 release into the app's own folder and pack the 4-bit variant into
  `~/Library/Application Support/Zephra/Models/z-image-turbo-4bit`. `BITS`,
  `GROUP_SIZE`, and `QUANT_OUT` override the defaults (4 bits, group 64).
  `ZephraQuantize` takes a required `--family`; there is deliberately no
  default, because the wrong one silently produces the wrong artifact an hour
  later. For the same reason it refuses any `BITS` other than 4 unless the
  output directory is given explicitly: every default output name says `4bit`.
  It refuses an `--out` that is the source, inside it, or around it (the packer
  empties what it writes to), builds into a sibling `.partial` renamed into
  place when it finishes — ^C stops it between tensors and removes the partial,
  so nothing a loader would take for a model is left behind — and, when the
  output is named for a catalog entry, checks the volume for that entry's
  `builtBytes` first and stamps the result with the `.zephra-packed-source` the
  app checks, so a build by hand is one the app accepts as its own.
- `make quantize-qwen` — likewise for Qwen-Image, from `QWEN_SOURCE` with
  `QWEN_LORA` merged into its transformer, into
  `~/Library/Application Support/Zephra/Models/qwen-image-2512-4bit`
  (`QWEN_OUT` overrides). About a minute with the source local. The app fetches
  the same two things itself and does the same build; this is for keeping the
  57.7 GB source off the boot volume. The adapter is required: with `QWEN_LORA`
  empty the tool exits with the reason rather than building the undistilled
  model under the distilled name (see "The Lightning adapter is not optional"),
  and `ARGS=--no-lora` with a `QWEN_OUT` other than the catalog's is the way to
  build one on purpose.
- `make quantize-flux2` — the build the app does on first load, by hand: pack
  the klein release from the app's own folder (or `FLUX2_SOURCE`) into
  `~/Library/Application Support/Zephra/Models/flux2-klein-4b-4bit`
  (`FLUX2_OUT` overrides, and its default already follows `BITS`, so `BITS=8` lands
  in `flux2-klein-4b-8bit` without one). About a minute.
- `make quantize-ltx2` — the build the app does on first load, by hand: pack the
  LTX-2.5 pack from `LTX2_SOURCE` into
  `~/Library/Application Support/Zephra/Models/ltx-2.5-distilled-4bit` (`LTX2_OUT`
  overrides), fetching the source first when it is not there. 88 s once the
  source is local; 19.8 GB out, the video encoder copied beside the decoder.
- `make mirror` — build every variant the app packs on first load into one directory
  laid out for a bucket: `MIRROR_DIR/<catalog id>/`, each exactly what
  `locations.built(descriptor)` holds on a Mac, provenance stamp included, plus an
  `index.json` (`scripts/mirror-index.swift`) listing every file's path, size and
  SHA-256 and the stamp's contents. `mirror-z-image`, `mirror-qwen`,
  `mirror-flux2-4bit`, `mirror-flux2-8bit` and `mirror-ltx2` are the five variants alone, each
  skipped when its stamp is already there unless `FORCE=1`; `mirror-index` rewrites the
  index by itself; `mirror-sync` pushes the directory to `MIRROR_BUCKET`
  (`s3://zephra-assets-urandom-io/models` by default) with `aws s3 sync --delete`, files
  first and `index.json` last, under the `MIRROR_PROFILE` AWS profile (`dev.urandom.io`;
  empty in CI, where the `github-actions-zephra` OIDC role is assumed instead). The bucket
  and its CloudFront host, `zephra-assets.urandom.io`, are Terraform-managed in the
  `urandom.io` repository's `modules/zephra`; the repository's Actions variables
  `AWS_ROLE_ARN`, `AWS_REGION`, `ZEPHRA_ASSETS_BUCKET` and `ZEPHRA_ASSETS_HOST` name them. The default `MIRROR_DIR` is
  `ZephraMirror` beside the Qwen source on the external volume, since the five variants
  are 61 GB. The releases are read from where the quantize targets read them, so set
  `MODELS_DIR` and `QWEN_MODELS` the same way. This is the supply side of a CDN source
  for packed variants (`ROADMAP.md`); the app does not read a mirror yet.
- `make lint-layers` — enforce the layering rules above.
- `make vendored-diff` — fetch `mzbac/zimage.swift` at the pinned commit into a
  scratch clone and fail on any hunk of `Packages/ZImageKit` that carries no
  `ZEPHRA-PATCH` marker; see `VENDORED.md`'s re-sync procedure.
- `make logs` — stream app logs (`log stream`, subsystem `io.zephra`).
- `make screenshot` — capture the app window (see debugging hooks);
  `WINDOW=<title>` captures the window with that title instead, which is how
  a Settings tab is photographed.
- `make clean` — remove build output and the generated project.

The first Release build compiles MLX's Metal kernels from scratch and takes
several minutes. Always benchmark and make performance claims against
Release, never Debug — Debug has Metal validation and full debug info on.

## Starting from a picture

Every model Zephra ships can take a reference picture, and they take it in three
different ways. The difference is the whole of this section, because the setting
looks identical from the interface and means something else underneath.

- **Conditioning on it.** FLUX.2 klein encodes the picture to tokens,
  concatenates them after the image being made with their own image index on the
  rotary embedding, and still walks the whole schedule from pure noise. See
  `Flux2ReferenceConditioning` and `Flux2Pipeline+Denoise`. The picture is
  something the model attends to, so there is no "how much of it to keep".
- **Starting from a noised copy of it.** Z-Image and Qwen-Image have no such
  conditioning path, but their autoencoders can encode and their schedules
  interpolate `x_t = (1 - sigma) * x0 + sigma * noise`, which is all SDEdit
  needs: encode the picture, noise it to the level some step expects, and resume
  from there. How far down to resume is a real choice, and it is
  `GenerationSettings.referenceStrength`.
- **Holding it as the first frame.** LTX-2.5 makes clips, and its autoencoder is
  causal in time, so one picture encodes to one latent frame that means what it
  would at the head of a longer clip. The picture is put there and the model is
  told, per token, that those tokens are less noisy than the ones it is making;
  the rest of the clip is generated around it. How strongly to hold it is a real
  choice too, and it is the same `referenceStrength` read the other way round —
  see "Fifth model" for the whole of it, and `LTX2RequestMapper` for the one
  place the inversion happens.

`referenceStrength` is a plain `Double`, not an optional, because every
generation has one whether or not its model reads it, and 1 is the value that
changes nothing. `ModelCapabilities.referenceStrengthBounds` says whether it
applies at all: a degenerate `1...1` means it does not, the way `guidanceBounds`
of `0...0` means guidance does not, and `clamp` pins it there. klein declares
`1...1`; Z-Image and Qwen-Image declare `0.1...0.9` with a default of `0.6`;
LTX-2.5 declares `0.0...0.9` with a default of `0`, because 0 there means the
first frame is held exactly rather than "the picture is returned unchanged". So
the interface can decide whether to draw a slider by reading the range, without
knowing which family it is looking at, and "lower keeps more of the picture" is
true of all three whatever the backend does with it.

For the models that start from a noised copy:

- Strength reads as "how much of the picture to throw away". 1 discards it
  entirely and is the ordinary text-to-image path; 0 would return it unchanged.
  Neither end is offered, which is why the bounds stop at 0.1 and 0.9.
- **Strength buys a share of the steps, not a noise level.** `steps * strength`
  of them run, truncated and never fewer than one, so every strength the slider
  offers keeps some of the picture, and the loop enters that far from the end,
  starting from the encoded picture mixed with that step's share of the run's
  own seeded noise. So 0.6 of Z-Image's nine steps enters at 4 and runs 5; 0.6
  of Qwen-Image's four enters at 2 and runs 2; and 0.9 of Qwen-Image's four is
  3.6, which runs 3 from an entry of 1. Reading strength as a share is
  diffusers' `get_timesteps` mapping, and following it rather than entering at
  the first sigma at or below the strength is load-bearing: a distilled ladder
  is not evenly spaced. Qwen-Image's four sigmas are 1.0, 0.767, 0.456 and
  0.02, so the noise-level reading sent every strength from 0.1 to 0.4 to that
  0.02 and handed the picture back untouched. The truncation is a deliberate
  departure from `get_timesteps`, which takes the ceiling of the share: the
  ceiling of 0.8 or 0.9 of four steps is four, an entry of 0, where the mix is
  pure noise and the picture is discarded at the top of the slider. The product
  is nudged up by a hair before it is truncated (`1e-9` on the double product
  in `QwenImageReferenceLatents`, `1e-7` on the `Float` strength in
  `ReferenceLatents`), because `100 * 0.29` lands at 28.999999999999996 and
  ten `Float` steps of 0.7 at 6.9999999; the slider's 0.05 granularity is what
  makes the nudge safe.
- Progress still counts against the full step count, so a queue card drawing one
  segment per step shows the skipped ones as finished rather than showing a
  shorter run.
- `ZImage.ReferenceLatents` and `QwenImage.QwenImageReferenceLatents` are the
  entry-point arithmetic, one per family, pure and pinned by their own suites.
  Two copies on purpose: one lives inside vendored code that is re-synced against
  upstream, and the two schedules are typed differently.
- `GenerationRecord.referenceStrength` records what ran, beside
  `referenceBytes`. Nil when there was no picture; 1 when the model conditioned
  on it directly, which is how a klein edit says it had no distance to travel.
- `GenerationSettings.referenceOrigin`, recorded as `GenerationRecord`'s field
  of the same name, is the library **file name** the picture came out of — nil
  for a file chooser pick or a drop, and a name rather than a path for the
  reason the record lives inside the PNG. `useAsReference` and `adoptReference`
  take it beside the picture, clearing the picture clears it, and `clamp` drops
  it wherever it drops the picture; `LibraryIndex.item(named:)` is the lookup
  back to the file, Recently Deleted excluded. `ImageFacts` shows it beside
  `referenceStrength` and the raw `referenceStrengthValue`, since LTX-2.5's
  scale runs the other way and its 0 is a phrase rather than a number.

Animating a picture is the third thing a picture can be, and it is one call:
`GenerationStore.animate(origin:read:)` picks whichever catalog entry makes
clips *and* reads a picture (`ModelCatalog.animator(among:)` — a capability
question, so the engine still names no family), chooses it without loading it,
sets the clip's length to that model's default, and reads the picture through
the same numbered choice every other door into the well uses. The prompt is
kept: the person is animating this picture with their prompt, which is what
tells Animate apart from a variation. `canAnimate` is `acceptsWork` and this
build having such a model, which is what the interface greys the button by,
disabled rather than hidden the same way `supportsReferenceImage` greys Use
as Reference. The size follows the picture in `useAsReference` rather than in
`animate` — on a model that makes clips a picture landing in the well moves
`settings.size` to `ModelCapabilities.preset(nearestAspect:)` of the picture's
own pixels — so a drop, the picker, Use as Reference and Animate all agree.

Each backend package decodes the bytes to a `CGImage` in its own
`ReferenceImageDecoding` — a small file duplicated per package, because no backend
package may import another. Backends decode; the kits are handed decoded images
and never touch the filesystem.

## Upscaling

Upscale 2x / 4x is Real-ESRGAN's compact network (`realesr-general-x4v3`,
SRVGGNetCompact: 34 convolutions at 64 channels with per-channel PReLU, a pixel
shuffle, and a nearest-neighbour residual), 1.2M parameters, BSD-3-Clause. It is
the first non-diffusion step in the app, and the seam it sits behind is the one a
later post-process should copy:

- `ImageUpscaler` in `ZephraCore/Upscale/` is the whole protocol: PNG bytes in,
  PNG bytes out at `UpscaleRequest.factor` times each edge, progress by tile,
  cancellation between tiles. It is deliberately not `ImageGenerationBackend`:
  that protocol is about one model family resident at a time, and an upscaler
  needs no model loaded and holds five megabytes.
- `InferenceActor` owns the one upscaler, built lazily from the injected
  `UpscalerFactory` and kept resident across model switches; it runs on the same
  serial queue as a generation, so two Metal jobs never overlap. The store's
  `GenerationStore+Upscale.swift` drives it through `EngineState.upscaling`,
  restores whatever state it started from, and refuses to start unless the engine
  is idle, ready, or failed; Generate greys out for the seconds it runs.
- The result is a new PNG in the library root named `<parent stem>-x<factor>.png`,
  carrying the parent's record with the new size, `upscaledFrom` and
  `upscaleFactor` set, `batchID` cleared, and the parent's reference chunk copied
  verbatim. An imported parent gets a minimal record so the result is indexed.
  Nothing rewrites the parent. A grid cell and a sidebar square wear an
  `UpscaleBadge` (`Style/`) in the top-left corner, because an upscale looks
  exactly like its parent at thumbnail size.
- The weights are bundled as a package resource, 2.4 MB of float16 safetensors
  converted once by `Packages/ZephraUpscaleRealESRGAN/Tools/convert_weights.py`
  from the v0.2.5.0 release asset; `PROVENANCE.md` there records the checksum.
  2x is the 4x pass followed by an exact 2x2 box mean; the network is 4x only.
  The picture runs through `TiledDecode` in 512-pixel input tiles at scale 4;
  a 1024 input measured 2466 MB peak and 3.75 s at 4x on an M4 Max, and 2x
  costs the same peak because the 4x join sets it. Alpha is dropped; library
  PNGs are opaque. The port is written from `srvgg_arch.py` and never from
  `xocialize/realesrgan-mlx`, which has no license.

Everything the upscaler leaves out on purpose is listed in `ROADMAP.md`.

## Tests

Swift Testing (`import Testing`, `@Suite`/`@Test`), never XCTest. Suites and
tests are named as sentences about behaviour ("the revision's refs file picks
the snapshot, not whichever is listed first"); match that when adding one.

- `make test` — `ZephraCoreTests`, `ZephraSnapshotTests`, `ZephraEngineTests` and
  `ZephraMediaTests` (which round-trips a clip through `AVAssetWriter`), seconds,
  no Metal.
- `make test-app` — `ZephraTests` in `Tests/ZephraTests`, the app target's own
  suites, hosted in the app so they can `@testable import Zephra`; Debug only,
  since Release turns `ENABLE_TESTABILITY` off. Pure interface logic belongs
  here — export planning, display strings, layout arithmetic, the workspace
  selection — and nothing that needs a window. The scheme's test action sets
  `ZEPHRA_PREVIEW_STATE=ready`, so the host launches frozen with no model. The
  test target takes `ZephraTestSupport` for `Scratch`, and its files default to
  the main actor the way the app's do. A test that needs a media file reads
  one committed under `Tests/ZephraTests/Fixtures` (a resource folder of the
  target, found through the test bundle) and never writes one with
  `AVAssetWriter` inside the host: a writer run there left CoreMedia's threads
  parked after the suite, the frozen host never exited, and `make test-app`
  waited on it for good. `ClipFramesTests` is the example. One suite:
  `make test-app` with `-only-testing:ZephraTests/ExportPlanTests` appended to
  the `xcodebuild` line, or from Xcode.
- One suite or test:
  `cd Packages/ZephraKit && swift test --filter ModelSwap`. The filter is a
  regex over the *type* names, not the `@Suite` display names, so `ModelSwap`
  takes both swap suites and `--filter 'model swap'` matches nothing.
- The MLX packages' suites need `xcodebuild`, and their filter is likewise the
  type name: `cd Packages/ZephraMLXKit && xcodebuild test -scheme
  ZephraMLXKit-Package -destination 'platform=macOS'
  -skipPackagePluginValidation
  -only-testing:ZephraQuantizationTests/QuantizableWeightTests`. A package's
  scheme is its own name, except `ZephraMLXKit`, which ships two library
  products and so is tested through `ZephraMLXKit-Package`.
- `QwenImageKit`'s, `Flux2Kit`'s and `LTX2Kit`'s suites check the ports against
  tensors dumped from `diffusers` (and, for Gemma 4, `transformers`) by each
  kit's `Tools/dump_reference.py`, whose inline metadata pins the reference
  stack's versions and which writes `Fixtures/versions.json` with what a run
  actually used; `LTX2Kit`'s entry point imports one sibling module per
  component (`dump_text_encoder.py`, `dump_transformer.py`, `dump_vae.py`), any
  of which `--only` regenerates alone, and its tokenizer fixture is ids from the
  real Gemma tokenizer, which the dumper fetches into a gitignored
  `Tools/.cache`. Adding a component means adding its fixture in the same
  commit; that is what the clean-room claim in `PROVENANCE.md` rests on. What
  the ports share through `ZephraMLX` is pinned by every kit's fixtures through
  the shared copy, and `ZephraMLXTests` pins the shared pieces on doll's-house
  tensors of their own. Each kit also has a `WeightKeyCoverageTests` that reads
  the real release's safetensors headers and checks every published tensor
  against the module trees; `LTX2Kit`'s pins the 1362 video-lane transformer
  keys, the connector's video side, all 666 Gemma keys and the video encoder's 86.

No test loads model weights. The `ZephraKit` suites never touch Metal; the MLX
packages' suites run doll's-house tensors through it, and a few of `QwenImageKit`'s,
`Flux2Kit`'s and `LTX2Kit`'s read a real snapshot's config, tokenizer, and safetensors
header files (`LTX2Kit`'s tokenizer suite is the one gated on a real snapshot, and
accepts the pack's `gemma4-12b-ltx-v1/` or the built `text_encoder/`). `SnapshotUnderTest` in `ZephraTestSupport` is where they look, in order:
`QWEN_IMAGE_SNAPSHOT`, `FLUX2_KLEIN_SNAPSHOT` or `LTX2_SNAPSHOT` when set; the app's own models
folder, where a variant packed on this Mac (`<models>/<descriptor id>`) carries
the configs and tokenizer and the download (`Downloads/<org>--<repo>`) is the
release itself; then the hub cache when it holds exactly one snapshot. A test
that reads the release's shard headers gates on `hasRelease` and takes
`release`, which skips the packed variants. Under `xcodebuild test` the variable
has to be spelled `TEST_RUNNER_QWEN_IMAGE_SNAPSHOT`: only `TEST_RUNNER_`-prefixed
variables reach the test process. The engine tests drive `MockBackend`
through `MockBackendControl`, a lock-protected dial a `@Sendable` factory can
close over — it fails a load, delays one so cancellation lands mid-flight,
pretends to build, tallies loads, unloads and builds, and records the last
settings a generation was asked for — while `EngineTestBed` gives each test a
throwaway output folder. `ZephraCoreTests` uses the smaller `StubBackend`.

## Model weights

Default model: `mzbac/Z-Image-Turbo-8bit` — 13.3 GB download (excluding
`assets/`), 12236 MB resident once loaded and peaking at 23501 MB during the VAE
decode at 1024 pixels, so 32 GB of RAM is the practical floor.

Weights live in the folder Settings > Models names, which is
`~/Library/Application Support/Zephra/Models` until the user changes it:
`Downloads/<org>--<repo>` for a release, `<descriptor id>` for a variant packed
here. `make prefetch` writes exactly what the app would have written, so it
seeds a first launch; and a prefetch that was interrupted is finished by the
app, which then removes the `.incomplete` partials `hf` left under the folder's
`.cache/huggingface/download`, since a partial nothing will finish would
otherwise hold the folder incomplete for good. The hub cache is still read if it holds a release — a Mac
that ran `hf download`, or an older Zephra — but nothing is written there any
more, and neither `HF_HOME` nor `HF_HUB_CACHE` decides where a download goes.

Every repository the catalog names is public and ungated, so no download needs a
Hugging Face token — and Zephra sends none: `ModelDownloader` never sets an
`Authorization` header, whatever is in `HF_TOKEN` or in the token files the `hf`
tool reads, which is one whole class of "authentication required" for a public
model that cannot happen. There is no metered-network refusal either: the size
is on the screen before the download starts, so whether to spend it on a hotspot
is the user's call. A download that breaks is tried again by `DownloadRetry` in
`ZephraCore`, five times with a doubling pause, and each file resumes from its
`.incomplete` bytes, so a retry and a later Try Again both continue rather than
start over. Only a missing repository, a missing file, or a 4xx that is not a
timeout or a rate limit stops the retrying early.

Settings > Models lists every directory the catalog's models have on this Mac —
the app's own folder first, then either hub layout — with where it is, its size,
and a Delete that permanently removes its files after confirmation. `ModelStorage` in `ZephraSnapshot` is
the listing and the measuring, and each `ModelStorageItem` says where it was found
(`origin`: the app's folder or the hub cache), since only a partial in the app's own
folder resumes when its model is chosen; `ModelInventory` in `ZephraEngine` is what the
tab observes. A release two variants pack from is one row naming both, a
download stopped part-way is a row saying so, an adapter is a row of its own
named for the model it serves ("Qwen-Image 2512 adapter"), and a directory the
loaded model is using cannot be deleted from under it. Changing the folder offers
Move Models, Keep in Place, or Cancel. Keep retains previous roots as read-only
fallbacks. Move unloads the model, copies catalog-owned downloads and builds into
staging, verifies bytes, then publishes them before removing originals. A collision
refuses the move without overwriting either copy. Cleanup failure keeps the new
location and reports leftover originals. Move Models Here chooses one previous root
explicitly. Neither migration path touches the image library or the hub cache.
Preparation is stopped by a folder change and resumes only when requested from the
canvas; generation, queued work, upscaling, and deletion cannot race migration.

Always pass the model explicitly when calling into the vendored pipeline —
its own default is the 32.9 GB bf16 repo, which Zephra reads only as a build
source and never loads.

Second model: `z-image-turbo-4bit`, packed on the user's own Mac from the bf16
release (`Tongyi-MAI/Z-Image-Turbo`, 32.9 GB excluding `assets/`), because no
repository publishes four-bit Z-Image-Turbo in the manifest format the vendored
loader reads. The app does that itself on first load, the way klein does;
`make quantize` is the same build by hand. 7.1 GB on disk (`builtBytes`) and
6575 MB resident, against 13.3 GB and 12236 MB for the 8-bit model. Peak follows
the image size — 10693 MB at 512 pixels, 14599 MB at 768,
17839 MB at 1024 — because peak is resident plus the unquantized VAE decode's
scratch. So a 16 GB Mac is offered this variant: 512 fits outright, and 768 and 1024
fit once the decode is tiled (12010 MB at 1024, under the 12124 MB working set;
Automatic tiles them). Four bits is not faster: MLX's quantized matmul costs the same at
these shapes whichever bit width it packs, which `make bench ARGS=--micro` shows
directly and the end-to-end step times agree with. Group size 64 rather than 32,
measured: 32 costs 825 MB more resident and 1.1 GB more on disk for no visible
quality gain.

Third model: `qwen-image-2512-4bit` — **Qwen-Image-2512**
(`Qwen/Qwen-Image-2512`, Apache 2.0), a 60-layer dual-stream MMDiT of about 20B
parameters, conditioned on Qwen2.5-VL-7B and decoded by a 3-D causal VAE. Packed
on the user's own Mac, because the release is 57.7 GB of bf16 and the four-step
distillation ships separately as an adapter, so the local build is where the two
are put together. 21.6 GB on disk. The app fetches both and packs them on first
load; `make quantize-qwen` is the same build by hand.

Choosing it therefore costs 59.4 GB of download — the release and the 1.7 GB
adapter, which is what `ModelDescriptor.transferBytes` adds up and what the
picker states on a Mac that has neither; one that has the release is told the
adapter's 1.7 GB alone — and then a build. The adapter is a `ModelAdapter` on the
descriptor rather than a second catalog entry: it is one named file in a
repository of its own (that repository also ships whole merged checkpoints of
twenty gigabytes each, so it is never taken by pattern), it is not optional, and
nothing downstream of the packer ever sees one.

The full-precision source is too large for the boot volume here, so a copy of it
lives at `/Volumes/ExternalStorage/Models/Qwen-Image-2512` with the adapter
beside it in `Qwen-Image-2512-Lightning/`. Point `QWEN_SOURCE` and `QWEN_LORA`
there for `make quantize-qwen`, and `QWEN_IMAGE_SNAPSHOT` there for any test that
wants real weights. Point `MODELS_DIR` at that volume instead and the app's own
download lands there and this copy is unnecessary.

Measured on an M4 Max, four steps, seed 42: 21532 MB resident at every size,
because the weights are the whole of it. 512 pixels takes 6.9 s (1.57 s/step)
and peaks at 26053 MB; 1024 takes 33.6 s (8.15 s/step) and peaks at 30364 MB;
1328, the model's native resolution, takes 66.7 s (16.25 s/step) and peaks at
32520 MB. Tiled at a 64-cell latent tile the peak barely moves with the image —
26068 MB at 1024, 26088 MB at 1328 — because the tile, not the image, sets the
decode's transient and what is left is the transformer. So 1024 is the default
size: half the seconds of native for an image that still renders legible text,
and the entry's `peakBytes` is measured there. Every one of those figures was
taken while the stream ran in float32 by accident — float32 noise, uncast
float32 scales, and a stream handing back raw nodes — and is due a rerun on an
idle machine now that it runs in bfloat16 (see "Streaming the weights").

**The Lightning adapter is not optional.** The base model wants fifty steps and
real classifier-free guidance, which is two forward passes through twenty
billion parameters per step. `lightx2v/Qwen-Image-2512-Lightning` (Apache 2.0)
distils that to four steps and no guidance, and the build — the app's own, or
`make quantize-qwen` — merges it into the transformer as it packs, so the
runtime never sees an adapter. Run the
same seed and prompt against a build without it and the difference is not
subtle: soft, hazy, mesh-textured surfaces against sharp ones. That is also why
the catalog entry reads `guidanceBounds: 0...0` and
`supportsNegativePrompt: false` — the merged weights were distilled without
either. An entry built from the undistilled release would be the opposite, which
is what `ModelCapabilities` being per-descriptor is for.

Text-to-image never runs Qwen2.5-VL's vision tower: the pipeline supplies token
ids and an attention mask and no pixels. So the ViT is not ported and its
weights are not loaded, along with `lm_head` — together 391 of the checkpoint's
729 text-encoder tensors. `WeightKeyCoverageTests` asserts that rather than
leaving it to be assumed.

The autoencoder's *own* encoder is a different matter, and is now ported and
loaded, because starting from a noised copy of a picture needs it. It is
107.2 MB of the 4-bit build's 253.8 MB VAE — half a percent of the model's
21.5 GB — so it is built unconditionally rather than lazily: a nil module
rebuilt on demand would have to keep the shard mapped for the pipeline's whole
life to have anything to fill itself from. The catalog's measured figures have
not been adjusted for it by arithmetic; they are due a rerun.

**Streaming the weights.** A Mac whose GPU cannot hold Qwen-Image still runs it,
by reading the model from the disk on every step instead of holding it. The
mechanism is `LayerWeightStream` in `ZephraMLX`, and its shape is set by how MLX
loads: `MLX.loadArrays` parses a shard's header and hands back arrays that are read
with `pread` into an MLX-owned buffer only when evaluated, and there is no mmap
path (the MLX maintainers measured one and rejected it: the kernel page cache is
the wrong eviction policy for weights). So a stream keeps, per layer, the very
`MLXArray` objects the forward pass reads, and one pass does this in this order:
open fresh lazy nodes for every tensor in the stack's shards; `asyncEval` the first
`depth` layers' arrays, which starts their reads on the CPU stream; then for each
layer, run its work, `asyncEval` its outputs, **wait for the layer before it**, then
`asyncEval` the layer `depth` ahead, then hand each of the layer's arrays a fresh
unevaluated node from the next pass with `_updateInternal`, cast back to the dtype
the tree held at capture. The buffers a layer held live exactly until its command
buffers complete, and nothing has to remember a placeholder. The cast is what lets
a load-time cast survive streaming: the packer's scales are float32 on disk, MLX's
quantized matmul takes its output dtype from them, and a stream that handed back
the raw node would have widened every block after the first to float32 from the
second step on — which is exactly how Qwen-Image ran in float32 until the audit.
Now `QwenImagePipeline.loadModel` casts the text encoder's and the transformer's
float32 parameters to `QwenImageTransformerPrecision.activation` (bfloat16, or
float32 under `ZEPHRA_DIT_DTYPE=f32`) *before* attaching either stream, `generate`
casts the noise and the conditioning to it, and the transformer casts its text to
the latents' dtype at entry; the autoencoder stays float32 on purpose. Two more of
the loop's choices are load-bearing and easy to undo: outputs
are committed per layer at all because an unevaluated graph holds every layer's
weights as inputs, so one eval per step would read most of the model before any
of it ran; and the wait on the layer before is what bounds the window at
`depth + 2` layers, because MLX allocates a tensor's buffer when its read is
*queued*, not when the bytes arrive, and a loop that queued freely would run five
or six layers ahead before MLX's own task limit stopped it. Waiting on the layer
before rather than the one just committed leaves the GPU a layer of work in hand.

In Qwen-Image the transformer's sixty blocks (16.1 GB packed, about 269 MB
each) and the text encoder's twenty-eight layers stream; the embeddings, the input
and output projections, the norms and the whole autoencoder stay resident, which
is what `QwenImageResidentParameters` evaluates at load. `QwenImagePipeline.loadModel`
takes a `QwenImageStreaming` (depth, two by default: three layers held at once)
and attaches a stream to each stack after the loader has filled it and before
anything evaluates it. A streamed step is one read of the transformer, so a
`Task.checkCancellation()` sits between blocks and Stop is answered inside a step.
Every block's tensors have identical shapes, so MLX's buffer cache hands block
i's freed buffers to block i+2's reads; the bench reports `cacheMemoryMB` so a
run where that stopped happening shows up rather than being guessed at.

Measured on an M4 Max at 1024, four steps, seed 42, tiled at 64: 10243 MB peak
streamed against 30473 MB resident in the same session, 1409 MB live between runs,
16.15 GB read per step, and the streamed image byte for byte the resident one
(`cmp` on the two PNGs). The step time was not recorded there: the machine was
busy, and the resident run itself came in at six times the catalog's figure. On
bender, the 16 GB M4 mini (12.7 GB working set), the same variant streamed: 7954 MB
peak and 29.7 s a step at 1024 (123 s a picture), 5447 MB and 7.1 s a step at 512,
the latter read-bound at 2.3 GB/s from its SSD, and swap did not move across either
run. `dd` reads that SSD at 1.6 GB/s in one stream; MLX's four-thread reader does
better.

What decides it: `ModelDescriptor.streamedPeakBytes`, zero for a family that cannot
stream, is the measured peak with the weights streamed and the decode tiled;
`MemoryFit` tries it after `fitsTiled` and before giving up, and answers
`fitsStreamed`, which the picker words "Streams from disk". `WeightResidencyPolicy`
turns the Performance tab's three-way preference (`AppSettings.weightResidency`)
and the budget into a `WeightResidency` for a load — under Automatic, streamed
exactly when the verdict is `fitsStreamed`, and never for a model with no streamed
figure, which is how klein and Z-Image are never asked to. The residency rides on
`ImageGenerationBackend.load(_:at:residency:onProgress:)`; `InferenceActor` pins it
beside `loadedPath`, so asking for a model already up the other way is a reload,
and `GenerationStore.setWeightResidencyPolicy` reloads through the swap path when
the loaded model's answer changes. `ZEPHRA_WEIGHT_RESIDENCY=streamed|resident`
overrides the preference for one launch and `ZEPHRA_STREAM_DEPTH=N` the depth;
`make bench ARGS="--stream"` measures it and prints the gigabytes read per step and
the disk's rate, which is what tells a read-bound step from a slow GPU.

**The memory budget** every verdict is measured against is `MemoryBudget` in
`ZephraCore`: not a fraction of RAM but what the GPU may keep resident, Metal's
`recommendedMaxWorkingSetSize` — 12124 MB on a 16 GB M4 mini, 38338 MB on a
48 GB M4 Max — which is the figure `sudo sysctl -w iogpu.wired_limit_mb=N`
raises. The app reads it once at launch (`GPUMemoryBudget`, from the runtime and
the sysctl) and hands it down as an environment value and to the store; MLX's
memory limit and wired limit are set from it too, so a resident model is kept in
Metal's residency set rather than left for the OS to page. Settings >
Performance shows the figure — and, on an M5-class GPU only, `GPUPrecisionNote` saying that
klein runs float32 there and why, read through `InferenceRuntime.isM5ClassGPU()`, the one
question about the GPU's generation the app target can ask — and, when the chosen model would run with the limit
raised and does not run now, the exact command with a Copy button: the app never
runs `sudo`, and a change to the sysctl is seen at the next launch. A budget
built from RAM alone, which the tests and a GPU-less build use, assumes four
fifths of it.

Fourth model: `flux2-klein-4b-4bit` and `flux2-klein-4b-8bit` — **FLUX.2 klein
4B** (`black-forest-labs/FLUX.2-klein-4B`, Apache 2.0, ungated), a 3.9-billion
parameter rectified-flow transformer of 5 dual-stream and 20 single-stream blocks,
conditioned on Qwen3-4B and decoded by a plain 2-D KL autoencoder, distilled to
four steps with no guidance. The one download is the bf16 release without the
root single-file checkpoint, 16 GB; the app packs it into the chosen variant on
first load (`builtBytes` says what that writes), and `make quantize-flux2` is the
same build by hand. Both variants share the download. The release is kept
afterwards, because the other variant packs from it; deleting it is a row in
Settings > Models.

The text encoder is Qwen3-4B, bit for bit, and the transformer conditions on
the hidden state after its 9th, 18th and 27th layers laid side by side, padded
to 512 tokens with every position kept. So only the first 27 layers are built,
loaded, or packed; layers 27 to 35 and the final norm are omitted by the plan,
`Qwen3Model` builds `layersNeeded` layers rather than what the config says, and
`WeightKeyCoverageTests` pins the leftover set. The three modulation linears are
shared by every block of their kind and held whole: 142 million parameters is
not worth a knob. The autoencoder normalises its packed 128-channel latent with
batch-norm running statistics rather than a scaling factor, and its config
names FLUX.2-dev as its origin; only the copy inside the klein-4B repository is
ever read.

Measured on an M4 Max, four steps, seed 42: the 4-bit variant holds 4941 MB at
every size and peaks at 7651 MB at 512, 9037 MB at 768, and 12087 MB at 1024,
7660 MB tiled; a step is 2.1 s, 4.5 s, and 6.9 s. The 8-bit variant holds 8144 MB
and peaks at 15289 MB at 1024, 10861 MB tiled, for the same step time. So 1024 is
the default size and the 4-bit entry is what a 16 GB Mac opens on, with the exact
decode. An edit is dearer: a 1024 image from a 512 reference peaked at 19227 MB and
took 66 s, the reference's 1024 tokens riding through every attention layer — and
those two figures were measured with the reference's tokens still float32, which
widened the whole edit to float32; `Flux2ReferenceConditioning.encode` now casts
them to the stream's dtype, and the edit is due a rerun on an idle machine. The
stream runs in bfloat16, except on an M5-class GPU, where the backend runs it
float32 at three times the step time: `Flux2ActivationPrecision` in
`ZephraBackendFlux2` resolves the dtype — `ZEPHRA_DIT_DTYPE=f32` or `bf16` if
set, else float32 when `GPUGeneration.isM5Class`, else bfloat16 — and hands it
to `Flux2Pipeline.loadModel(at:activation:)`; the kit reads no environment
variable and has no default of its own beyond bfloat16. The gate is the
workaround for the mlx-swift split-K bug (see "Conventions"), and it is
unverified: none of the project's Macs is an M5. The packer's float32 scales are
cast to the stream's dtype at load, without which MLX's quantized matmul widens
every activation to float32.

Two of this port's choices are load-bearing and easy to undo by accident. The
schedule uses the pipeline's empirical shift, not the scheduler config's
`base_shift` and `max_shift`, which klein's pipeline never reads. And the
query-key norm epsilon is the config's 1e-6, where both MIT ports use 1e-5;
`PROVENANCE.md` lists these with the other two departures.

The same checkpoint edits: a reference picture is fitted to at most a megapixel
keeping its shape, trimmed to multiples of 16, encoded, and its tokens placed
after the image being made on image index 10 of the rotary embedding's first
axis. The schedule's shift counts only the image being made.

Fifth model: `ltx-2.5-distilled-4bit` — **LTX-2.5** (Lightricks, LTX-2.x
Community License), a 22-billion-parameter audio-video DiT of which Zephra runs
the **video stream only**: 13.1 billion parameters across 48 blocks (video
self-attention, cross-attention to text, and a feed-forward, each gated per head
by `to_gate_logits`), conditioned on a Gemma 4 12B encoder — all 49 of its hidden
states, RMS-normalised per token, laid side by side (188160 wide), projected in
float32 to 4096 and passed through an eight-block 1-D connector, built from the
DiT's own gated attention, feed-forward, norm and rotary embedding over one
axis, whose 128 learned registers stand in for the padding — and coded by a 3-D convolutional
autoencoder (temporal x8, spatial x32, 128 latent channels), both halves of it.
Distilled to eight
ancestral Euler steps (`LTX2DistilledSchedule`: nine fixed sigmas, eta 1,
re-noising drawn from `seed + 10000`) with no guidance. Frames are `1 + 8k` at
24 fps, 9 to 121, 49 to start; sizes are multiples of 32, 768 x 512 to start.

**It makes a clip from a picture.** The autoencoder's encoder is causal in time —
the first frame repeated at the front of every convolution and nothing at the
back — so one picture encodes to one latent frame that means what it would at the
head of a longer clip, and that frame is what a reference picture is held as.
`LTX2VideoEncoder` mirrors the decoder (patch-4 patchify, 4/6/4/2/2 blocks at
128/256/512/1024/1024 with a space-to-depth downsampler between each pair) and is
0.64 GB of the pack's 69, loaded with everything else. Its `conv_out` writes 129
channels and only the mean's 128 are taken, which is the `sample_mode: "argmax"`
both official pipelines encode with, and its per-channel statistics are a
different pair from the decoder's under different names.

Holding the frame is one thing to the transformer and three to the loop.
`LTX2Transformer.callAsFunction` gains `firstFrameStrength`, and with it the
video adaLN and the output head see a **per-token** noise level,
`sigma * (1 - mask)`, while the prompt's own adaLN keeps the scalar sigma; one
held frame gives that field exactly two values, so both are computed as one batch
of two sigmas and chosen per token by the marker the keyframe embedding already
builds, row by row after the nine-row table is split. `LTX2FirstFrameConditioning`
is the rest: the loop starts from `noise * (1 - mask) + clean * mask`, and each
step converts the velocity to the finished-latent estimate at the step's
**scalar** sigma, blends the picture into that estimate — never into the velocity,
which the reference's own comment insists on — and converts back. A frame held at
strength 1 is put back after the step, which is what the official image-to-video
pipeline does by slicing it out and never stepping it; a partly held one is left
stepped. The schedule does not change: the same nine sigmas either way. The live
preview of a held run shows the frame *after* the held one, since frame 0 is the
picture that was handed in.

**The strength runs the other way**, and `LTX2RequestMapper` is the one place it
is inverted. The interface's `referenceStrength` reads as "how much of the picture
to throw away" everywhere; here the loop wants how strongly to *hold* it, so it is
`1 - strength`. The entry declares `referenceStrengthBounds: 0.0...0.9` with a
default of 0, so the default holds the frame exactly, which is what
image-to-video means, and 0.9 holds it barely. A bound of 1 is not offered: at 1
the frame is not held at all, which is text-to-video with an ignored picture.

**Lightricks' own repositories are gated.** `Lightricks/LTX-2.5` and its
diffusers layout answer 401 without a logged-in token that has clicked through
the license, and Zephra sends no token, so the catalog names the ungated
`mlx-community/ltx-2.5-mlx` pack instead: the same bf16 weights, one file per
component, `LICENSE.md` beside them. The plan reads five of its files — the
38 GB distilled transformer, the 6.3 GB connector, the 23.8 GB Gemma encoder
with its tokenizer, the 0.8 GB video decoder and the 0.64 GB video encoder a held
first frame is read by — 69.6 GB in all, and omits the audio autoencoder, the
vocoder, the upscalers and the dev transformer by pattern. The gated case is why the packed variant is published on
the mirror as part of first light and not afterwards: the mirror is the path
users take, and the pack is the fallback.

The pack is what the packer reads, so `QuantizedComponent` grew two fields for
it: `sourceFiles`, shards named relative to the release root for a component the
release keeps as one file at the top, and `sourceDirectory`, for a component the
release keeps under another name (`gemma4-12b-ltx-v1/` is written as
`text_encoder/`, configs and tokenizer copied along). Keys keep the pack's
prefixes (`transformer.`, `connector.`, `vae_decoder.`, `vae_encoder.`,
`model.language_model.`) and each kit module maps its paths onto them for the
loader, the manifest and the stream — the one real rename being the encoder's
statistics, which the pack spells `_mean_of_means` and `_std_of_means` and
mlx-swift's parameter filter would drop for the leading underscore. `LTX2QuantizationPlan` packs both stacks at four bits and holds the
conditioning, the modulation tables (float32 in the pack), the gates and the norms
whole; the two embeddings — Gemma's 262144-row token table and the 188160-wide
aggregate projection — go to eight bits, since both are read once per prompt
and both lose more than a block does at four. Every audio-side tensor is left
out by one list, `audioOmitted` (`audio`, `a2v`, `v2a`, and `av_ca_` as a prefix
under `transformer.`), so the audio variant's plan is this plan without it;
`LTX2TransformerWeights.audioMarkers` says the same words in the kit, and
`WeightKeyCoverageTests` is what keeps the two agreeing. The build is 88 s once the pack is local
and writes 19.84 GB (`builtBytes`, measured: 19,843,588,073 bytes): 8.56 GB
of transformer, 1.89 of connector, 8.00 of Gemma, and the 0.81 GB video decoder
and 0.64 GB video encoder copied as they are, since three-dimensional convolutions
cannot be packed. At load the float32 scales are cast to the
stream's dtype for every layer but the aggregate projection, which stays float32
because 188160 products summed in bfloat16 lose the prompt.

Video only is a real departure and not just a subset: the audio-to-video
cross-attention adds a term to the video stream that the `audio=None` forward
has not got, so this variant's pictures differ from the audio-video model's. The
official model accepts `audio=None`, the fixtures are dumped the same way, and
the seam for the audio stream — the place on `LTX2Block` where the audio modules
go, the
transformer's audio heads, a second connector stack, the audio autoencoder and
vocoder, an audio track in `GeneratedVideo` — is written down in `ROADMAP.md`
for Macs with the memory. Nothing else is left out of the video path except the
temporal chunking of the decode, which matters past about 121 frames at 1024,
and the H.264 re-compression the reference puts a held first frame through
before encoding it (`ROADMAP.md`).

The tokenizer is Zephra's own byte-pair encoder over the pack's `tokenizer.json`
(`LTX2Tokenizer`): swift-transformers 0.1.24 splits by grapheme cluster and turns
emoji joined by a zero-width joiner into bytes, and Swift `String` keys merge
canonically equivalent tokens, so the vocabulary is keyed by UTF-8 bytes; the
ids are pinned against Hugging Face's for twelve prompts. Gemma 4's tokenizer
emits no BOS, so the encoder prepends id 2 itself, truncates keeping the front,
and left-pads to 1024 with id 0.

Both 48-layer stacks stream through `LayerWeightStream` under
`WeightResidency.streamed`, as Qwen-Image's do; the token table, the projection,
the connector, the conditioning heads and the decoder stay resident. The
transformer evaluates every eight blocks when resident (`blocksPerEval`), because
forty-eight blocks of a 22B model in one Metal command buffer can outrun the
watchdog on a small Mac. The live preview is the first latent frame only of the
`x - sigma * v` estimate, pooled and decoded through the same decoder
(`LTX2LatentPreview`), so a frame costs a fraction of a step. The first forward
after a load pays for Metal's kernel compilation, which the store's warm-up run
absorbs — at a price the other families do not pay: the actor's one-step 512
picture clamps to this model's eight steps and nine frames plus an MP4 encode,
about ten seconds (`ROADMAP.md`). The decoder has no tiled path, so Automatic
tiling changes nothing for it and `tiledPeakBytes` is the plain peak. Nothing
tells the running-run inspector a clip's length yet; it shows the steps as it
does for every family.

Measured on an M4 Max, seed 42, resident, with the video encoder loaded: the
default 768 x 512 clip of 49 frames in 63.4 s at 7.0 s a step, 18159 MB live and
22425 MB peak, loading in 4.8 s (17521 MB and 21787 MB before the encoder was
part of the load, so the encoder is the 638 MB between); a 9-frame 512 x 288 clip
in 10.4 s at 0.90 s a step with the same peak, which says the peak is the load's
(the float32 scales before their cast) and not the decode's. Holding a first
frame costs nothing the bench can see: 65.6 s at strength 0 and 68.8 s at 0.6 on
a busy machine, the same peak, and the text-to-video poster byte for byte what it
was before the encoder was loaded. Streamed, both stacks, the encoder resident since
convolutions never stream: 9007 MB peak and 4741 MB live holding a first frame (8369
and 4103 before the encoder), 8.09 GB read per step at 1.19 GB/s, the same pace as
resident since the M4 Max's SSD keeps up, and a poster byte for byte the resident run's. On bender, the 16 GB M4
mini, the same streamed clip: 8284 MB peak, 4103 MB live, 25.5 s a step and 232 s
a clip, read-bound at 0.32 GB/s straight after the variant landed from the mirror
(a rerun on an idle disk is owed). The first run made a coherent picture. `make bench ARGS="--model
ltx-2.5-distilled-4bit --size 768x512 --frames 49"` is the run; the clip is
written as `.mp4` beside its poster.

Each family's quantization plan lives in its own backend package's
`Quantization` directory; the packer they drive is shared, in
`ZephraQuantization`. Precision there is a function of the tensor name: an
ordered list of rules per component, first match wins, and a rule resolving to
no precision leaves the tensor alone. `QuantizableWeight` answers only whether
MLX *can* pack a tensor; `QuantizedComponent.precision(for:)` answers whether we
*want* it packed, and it is asked first, because the group size it names is what
divisibility is tested against.

Qwen-Image holds its modulation layers at eight bits while the rest goes to
four. They are 6.8 of the transformer's 20.4 billion parameters and they decide
how strongly every other layer responds; published four-bit builds that pack
them with everything else lose coherent structure. It costs about 3.4 GB — four
more bits for each of 6.8 billion weights — which is why the transformer is 16.2 GB
on disk rather than the 12.8 GB a pure four-bit build would write.

An adapter naming weights the component has not got stops the build. That is the
one check worth keeping: an adapter written against a different port of the same
model matches nothing, merges nothing, and hands back the base model — a failure
that looks exactly like a build that worked. Its narrower twin is caught at the
file: an adapter whose tensors follow no naming `LoRAAdapter` reads — kohya's
`lora_unet_` exports, or any spelling it does not know — used to parse to an
adapter of nothing, "merging 0 adapted weights", and now stops the build with
`adapterNamesNothing` before a weight is read. And `ZephraQuantize` refuses to
build Qwen-Image without `--lora` at all (`QuantizeFamily.requiresAdapter`):
the undistilled build loads under the distilled name and runs, and every
picture is soft and hazy. `--no-lora` builds it on purpose, and then `--out`
must name a directory other than the catalog's.

Three more things about the Z-Image plan are load-bearing and easy to break:

- The set of packed tensors must match the reference eight-bit export exactly. The
  loader decides what is quantized by looking for a `.scales` key, so packing a
  tensor the reference left alone stops the module tree matching the weights.
  `QuantizableWeight` is that rule, and `QuantizableWeightTests` pins it.
- Manifest layer names are the bare module paths the loader looks them up by
  (`layers.0.attention.to_q`, `model.layers.0.mlp.down_proj`), not prefixed with the
  component the way `mzbac/Z-Image-Turbo-8bit` writes them. The reference names never
  match, so its per-layer `bits` and `group_size` are dead and everything falls back
  to the top level. Bare names make mixed precision — a four-bit transformer with an
  eight-bit text encoder — actually work.
- Scales and biases are written float32, as the reference does, because the source is
  cast to float32 before packing. The transformer's `castFloatParameters` patch turns
  them into bfloat16 at load.

Weights stream one tensor at a time out of the source shard — MLX reads each
lazily, on first evaluation, so only the tensor being packed is resident — and spill
once four gigabytes have accumulated, so a 24 GB float32 transformer converts at
about 8 GB resident. The whole build takes about a minute once the source is local.

## Vendored code

`Packages/ZImageKit` is a vendored copy of `mzbac/zimage.swift` at commit
`970f83e4`. See `Packages/ZImageKit/VENDORED.md` for the license situation,
the re-sync procedure, and the running patch log. Any change inside
`ZImageKit` needs a `// ZEPHRA-PATCH:` comment and a `VENDORED.md` entry.

## Conventions

- Conventional Commits for all git messages.
- Wording follows macOS: US spelling in user-facing strings ("Favorites"),
  Title Case for push buttons and menu items ("Open in Canvas", "Reveal in
  Finder" is the one verb for the Finder), sentence case for toggles, captions
  and the sidebar's list labels. Code identifiers are exempt and keep their
  spelling — `isFavourite`, `toggleFavourite`, `FavouriteToggle` — because no
  user sees them and renaming the engine's API would buy nothing.
- Swift 6 strict concurrency in our code. The vendored `ZImageKit` package
  stays in Swift 5 language mode so its 49 upstream files compile untouched.
- Every package pins the same exact `mlx-swift` and `swift-transformers`
  versions (`ZImageKit`'s manifest too, logged in its `VENDORED.md`).
  `QwenImageKit` assembles Qwen-Image's tokenizer itself, and its
  `TokenizerTests` pin the ids against the Hugging Face tokenizer's, so a
  swift-transformers bump is checked by running them. When bumping mlx-swift, re-run
  `Flux2Kit`'s two bf16 matmul probes: mlx-swift up to 0.31.6 miscompiles a
  bf16 split-K matmul on M5-class GPUs at the single block's output shape
  (mlx#3797, fixed in mlx 0.32.0 by mlx#3810, which no mlx-swift release
  carries yet). klein's stream is bfloat16 by default since `a17023e`; on an
  M5-class GPU `ZephraBackendFlux2` runs it float32 instead, at three times
  the step time (`Flux2ActivationPrecision`, gated on `GPUGeneration.isM5Class`,
  overridden either way by `ZEPHRA_DIT_DTYPE`). The gate is unverified — no
  project Mac is an M5 — and the two probes are what will say whether it is
  needed: the dense one runs the GEMM the bug is in, and the quantized one
  runs the packed path both catalog variants actually take, at 4 and 8 bits,
  since whether `quantizedMatmul` reaches the same kernel is not established.
  The day both pass on an M5 under a fixed mlx-swift, the gate goes
  (`ROADMAP.md`).
- No emojis in code or docs.
- Keep files small; split before a file grows past its target size.
- `ROADMAP.md` is where deferred work lives: an option considered and left out
  goes there in the same change, not only in a session note.
- Zephra may ship commercially. Every new dependency, vendored file, or model
  gets an entry in `THIRD_PARTY_NOTICES.md` (copyright line, license, and any
  NOTICE file) in the same commit. That file is bundled and shown in
  Settings > About; it is the disclosure, so keep it exact.

## Debugging hooks

Every `ZEPHRA_*` switch below that the inference path honours — the VAE tile, the stream
depth, the DiT dtype, the preview interval, the residency override, and the three memory
limits — is read **once at launch**, into `InferenceEnvironment` (`ZephraCore/Runtime`), by
the composition root (`ZephraApp.swift`) or by `ZephraBench/main.swift`, and handed down as a
value: the kits take what they need on their requests, the backends hold the rest as instance
state, and nothing below the root reads `ProcessInfo`. Changing a variable after launch
changes nothing. (`ZephraQuantize` honours none of them, so it reads nothing.)
`ZEPHRA_WEIGHT_RESIDENCY` reaches the Performance tab's picker the same way: the root hands
`InferenceEnvironment.weightResidency` down as the `\.weightResidencyOverride` environment
value, and `AppSettings.residencyPolicy(mode:budget:override:)` is pure, so the picker applies
the same override the store runs under without a second read of the process environment.

- `ZEPHRA_PREVIEW_STATE=ready|image|editing|tucked|clip|generating|starting|queued|watching|finishing|batch|library|viewer|picker|downloading|building|failed`
  launches a Debug build frozen in that state with no model, for screenshots (`make screenshot`).
  `tucked` is `image` with the canvas's floating prompt slid down to its lip.
  `viewer` opens the library pane on its first image full size; `picker` runs the
  `editing` build with the reference picker sheet forced open, through
  `InterfacePreview.wantsReferencePicker` — the one flag the well reads on its own,
  since a `@State` local to a view cannot be set from the composition root the way
  `workspace.viewing` can.
  `clip` stands the store up on `PreviewModel.video` — an invented model that makes clips
  and reads a picture, for the well, the length control and the strength slider — with the
  well filled and the canvas showing `PreviewImages.sample(frames:modelID:)` stamped with
  the catalog's own `ModelCatalog.ltx2Distilled4bit` rather than the invented model: the
  inspector's `ReferenceRole` reads the *record's* model, and an id the catalog does not
  carry would fall back to `.reference` ("Edited from") instead of "First frame". `frames`
  past 1 is what makes `GeneratedImage.isVideo` true; there is no drawn MP4 behind it, only
  a poster, so the canvas shows the picture rather than `ClipPlayerView` — the same as a
  real clip before its file has landed, and legible enough for the well's caption and the
  inspector's "First frame" row.
  `generating`, `queued` and `watching` all stand a run up with a made-up frame from it, so
  the live preview is on screen without a model: the first two are following the run, and
  `watching` is the one that is not — the model working while an earlier picture stays on the
  canvas, which is what the running card's ring being off says. `starting` is the same run at
  its first step with no frame yet, which is where `RunPlaceholderView` shows. `finishing` is
  a clip run after its last step, the latents being developed: the bar full and
  `FinishingNote` over the frame.
  `downloading` and `failed` sit over a picture, since that is where they must stay
  legible, and `failed` is a download that gave up.
- Debug only: `ZEPHRA_DOWNLOAD_TEST_HUB=http://127.0.0.1:<port>` uses the real
  downloader and UI with an unloaded exercise backend for disposable HTTP fixtures.
  Use a separate bundle identifier/preferences domain and models folder. No such hook
  exists in Release; ordinary Debug launches still use real backends.
- `ZEPHRA_PREVIEW_STATE=settings` freezes the engine but uses a live library index
  at the configured `imagesDirectory`, for native folder-change UAT with temporary fixtures.
- `make logs` streams `os.Logger` output for subsystem `io.zephra`.
- `make screenshot` photographs the app's window by its CoreGraphics id, so it captures the
  window rather than the rectangle of screen it sits in, and it fails rather than falling back
  when there is no window: a region or full-screen grab returns whatever is in front of Zephra,
  which on a shared machine means somebody else's windows end up in `out/`. With no argument
  it takes the largest window; `make screenshot WINDOW=General` takes the one titled
  "General" — the Settings window is titled after its tab — through the optional title
  argument of `scripts/window-id.swift`.
- `swift scripts/ax-press.swift "<title>" [role]` presses the control with that `AXTitle` or
  `AXDescription` in the running Zephra through the accessibility tree, without activating the
  app, moving the mouse, or posting an event, so it can open Settings > Models or click a
  button while a person keeps working; `--dump [depth]` prints the tree for finding titles.
  The terminal needs Accessibility in System Settings > Privacy & Security. Together with the
  background launch (`open -g --env ZEPHRA_PREVIEW_STATE=settings build/Debug/Zephra.app`)
  and the titled screenshot, this is how a Settings tab is photographed hands-off; the tab
  strip's controls are `AXButton`s titled after their tab, so `ax-press.swift Performance`
  switches tabs. Menu items are controls too (`ax-press.swift "About Zephra"
  AXMenuItem` runs the item without opening the menu), and with a person's Zephra up beside
  the preview launch, `ZEPHRA_PID=<pid>` says which copy to drive; the titled screenshot
  needs no such hint, since only the preview copy has that window. The one `Window` scene is presented on every launch
  (`.defaultLaunchBehavior(.presented)`), so a session that quit with the window closed no
  longer comes back without one; `--args -ApplePersistenceIgnoreState YES` on the launch is
  still the way to drop the last session's window frame and pane.
- `make bench ARGS="--size 1024 --steps 9 --runs 3 --json"` measures load, s/step, and peak memory
  headlessly; benchmark on an idle machine, Release only. `--reference IMAGE` measures the
  editing path on a model that has one.
- `make bench ARGS="--reference /path/to/reference.png --strength 0.6"` adds the strength, on a
  model that starts from a noised copy; the report says which step the loop began at and how
  many steps actually ran, so a run that took a third of the seconds is not mistaken for a
  model that got three times faster.
- `make bench ARGS="--micro --size 1024"` times the DiT's individual MLX kernels at that size's
  token count without loading any weights, so a slow generation can be attributed to a primitive
  rather than guessed at.
- `make bench ARGS="--preview --size 1024"` turns the live preview frames on for the run and
  reports how many were made and the mean milliseconds one took, and writes the last frame
  beside the image as `<stem>.preview.png` — a frame unpacked on the wrong axis is noise of
  exactly the right size, so it wants looking at and not only timing. Frames are off in the
  benchmark otherwise, so a step time measured without the flag is the model's own and stays
  comparable with the figures already recorded here. `ZEPHRA_PREVIEW_INTERVAL_MS` is the switch
  underneath: milliseconds between frames, and 0 switches them off, which is what the benchmark
  does to its own `InferenceEnvironment` without the flag. Measured at 1024 pixels on an M4 Max, mean over the frames of one run: 43 ms for klein
  4-bit, 130 ms for Qwen-Image 4-bit, 192 ms for Z-Image 8-bit, against 0.5 to 8 s for the same
  models' full decodes. The machine was not idle for the last two, so those are ceilings.
- `make bench ARGS="--model ltx-2.5-distilled-4bit --size 768x512 --frames 49"` measures a
  clip: `--size` takes `WxH` as well as one number, `--frames` is rounded down to the model's
  ladder and ignored by a picture model, and the clip is written to `--out` with its extension
  changed to `.mp4` and its first frame as a PNG beside it (`BenchRunner+Output`). The report
  carries the frame count; `--stream` works as for Qwen-Image, and `--micro` still refuses
  every family but Z-Image.
- `ZEPHRA_PROFILE_STEP=1` prints per-phase timings (text encode, per-step graph build, per-step
  eval, VAE decode, and Z-Image's preview decode) and MLX's active and peak allocation to stderr.
- Precision and padding switches, for bisecting a suspected regression without a rebuild:
  `ZEPHRA_DIT_DTYPE=f32` runs the transformer in float32 (and `bf16` runs klein's in bfloat16
  on an M5, over its device gate), `ZEPHRA_PAD_PROMPT=full` pads prompts to
  the 512-token limit, `ZEPHRA_KEEP_CACHE=1` stops handing MLX's scratch back after a generation,
  and `ZEPHRA_CACHE_LIMIT_MB=N` overrides the benchmark's MLX cache ceiling.
- `ZEPHRA_VAE_TILE=<latent tile edge>` decodes the VAE in overlapping tiles and blends the seams,
  so the decode's peak is set by the tile rather than by the image. 64 gives 512-pixel tiles and
  takes the 1024-pixel peak from 23.5 GB to 17.7 GB for a mean absolute pixel difference of 1 of
  255. `ZephraBench` sets it on the running family's runtime handle, so it is the tile the
  benchmark decodes at. In the app it only decides what the Performance tab reads before the
  first run: Settings > Performance holds a three-way preference (`AppSettings.vaeTiling`),
  the store keeps it as `vaeTilingPolicy`, and `InferenceActor` sets the tile through
  `InferenceRuntime.setVAETileSize` on its own queue as each run (and each warm-up) starts, for
  that run's own model — tiling under Automatic when that model's `peakBytes` is over what
  the GPU may keep resident (`MemoryBudget`). The handle writes the family's `VAETileSetting`,
  one locked slot per backend package that the backend reads as it builds the run's request
  and the kit takes as `decode(_:tile:)`; there is no static in any kit for it. A model
  chosen mid-run therefore never changes the running run's decode.
- `ZEPHRA_WEIGHT_RESIDENCY=streamed|resident` overrides the Performance tab's streaming
  preference for one launch, and `ZEPHRA_STREAM_DEPTH=N` says how many blocks a streamed load
  reads ahead (2 unless set; the backend hands it to `QwenImageStreaming(depth:)` or
  `LTX2Streaming(depth:)` at load).
  `make bench ARGS="--model qwen-image-2512-4bit --stream"` is the same with the report saying
  what one step read and how fast; `--stream-depth N` sweeps the window. A model whose family
  cannot stream loads resident whatever either says.
- `ZEPHRA_GENERATE_ON_LAUNCH=<prompt>` presses Generate with that prompt and the saved settings
  as soon as the model is ready: one real generation in the app itself, window and all, from a
  shell on a Mac nobody is sitting at. The bench measures the model without the window; a
  failure that needs the window on screen, as the GPU reset above did, needs this instead.
  `ZEPHRA_REFERENCE_ON_LAUNCH=<path>` puts that picture in the well first, through
  `adoptReference` as a drop would, and Generate waits for it to land, so with LTX-2.5 chosen
  the pair is an image-to-video run from a shell; alone it does nothing.
  `ZEPHRA_WIRED_LIMIT_MB=N` overrides the wired limit the app sets from the working set for
  that launch (0 switches wiring off), and the bench reads the same variable together with
  `ZEPHRA_MEMORY_LIMIT_MB=N`, so a run in the app can be replayed headlessly under its limits.
  Every `_MB` here is `MemoryUnits.mebibyte`, the same 2^20 the Performance tab's preference
  is stored in.
  Launch the app from a shell (`./build/Release/Zephra.app/Contents/MacOS/Zephra`) rather
  than with `open` when the point is the error text: MLX prints the Metal error it dies of
  to stderr, and the crash report carries only `abort() called`. The kernel's side of a GPU
  restart is in `log show` under `IOGPUFamily`, and the reports under
  `/Library/Logs/DiagnosticReports/gpuEvent-*.ips` say which process the firmware blamed.

## Environment notes

- In shell tooling, use `/bin/ls` rather than the interactive `ls` — the
  shell's `ls` function can hang on this volume.

## Website deployment destinations

Website iterations and modifications go to ChatGPT Sites first. When James says
"deploy to production", deploy the website to AWS with `make deploy-production`.
The website bucket is `zephra-site-urandom-io`; notarized app releases belong in
`zephra-assets-urandom-io/releases/`. Keep both deployments on the same page source.
