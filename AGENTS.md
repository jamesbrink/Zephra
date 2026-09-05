# Zephra

Zephra is a native macOS app that generates images locally on Apple Silicon,
via MLX/Metal. It runs three model families today, Z-Image-Turbo,
Qwen-Image-2512, and FLUX.2 klein 4B, behind one backend seam.

## Priorities

In order:

1. **Very clean code.** Small files, one type per file, compiler-enforced
   module boundaries, no god objects.
2. **Extensible for more models later.** An explicit backend/model seam
   (protocol + descriptor catalog). Z-Image-Turbo, Qwen-Image, and FLUX.2
   klein are the implementations; the UI never touches any family's types.
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
Sources/ZephraQuantize (tool)─→ ZephraCore, ZephraQuantization, every ZephraBackend<Family>

Shared, by what a file actually touches:
  ZephraKit/ZephraSnapshot     Foundation only  — the model downloader, local snapshot
                                                  checks, the hub cache read as a fallback,
                                                  what the models occupy on disk
  ZephraKit/ZephraTestSupport  Foundation only  — Scratch, the filesystem test fixture
  ZephraMLXKit/ZephraQuantization  MLX          — the streaming weight packer
  ZephraMLXKit/ZephraMLX           MLX, ZephraCore — the tiled decode and the allocator's
                                                  knobs; <Family>Kit may take it
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
    The canvas offers Cancel download during initial loading and model switches. **No
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
  to run that from the app: a `.partial` directory renamed on success, removed
  on failure, and a free-space refusal before anything is read.
- `ZephraMLX` (in `Packages/ZephraMLXKit`): MLX work that is the same job for
  every family. Three things are there. `TiledDecode`: an autoencoder's decode
  allocates in proportion to the image, so decoding overlapping latent tiles
  bounds the peak by the tile. `MLXRuntime`: the process-wide allocator's
  limits and readings, which each family's `InferenceRuntime` forwards to,
  adding only its own VAE tile. `LatentPreview`: how far to pool a latent for a
  preview frame, and how to turn the decoded pixels into RGBA8 bytes — the two
  halves of a frame that are not a family's own decoder. A model package may
  depend on this; nothing in it may depend on a model package. The vendored
  `ZImageKit` keeps its own copy of the first and the third as a
  `ZEPHRA-PATCH`, because pointing vendored code at ours would complicate every
  re-sync.
- `ZephraEngine` (in `Packages/ZephraKit`): concurrency + state. Depends on
  `ZephraCore` and `ZephraSnapshot`, nothing else. Backends arrive as an
  injected `BackendRegistry` of `@Sendable` factories; this layer never names
  a concrete backend. `ModelInventory` is the one thing it takes
  `ZephraSnapshot` for: the list Settings > Models observes, measured off the
  main actor and re-read after every deletion.
- `ZephraBackendZImage`, `ZephraBackendQwenImage`, and `ZephraBackendFlux2`
  (their own local packages): translate `ZephraCore` types to and from one
  family's types. No state, no UI. Each depends on `ZephraKit`'s `ZephraCore`
  and `ZephraSnapshot` products, on `ZephraQuantization` for its packing plan,
  and on its own family's kit. All three also pack a download into the variant
  they load, on first load, through the protocol's `build` step — every model in
  the catalog but the 8-bit Z-Image is built here. This split keeps `Packages/ZephraKit` free of MLX
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
  for what they are.
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
so acquisition completion never opens a deletion gap. Failed/canceled loads unload
before releasing their claim. Foreground events carry an operation identity; superseded
progress and completion cannot change the selected model's state.

All UI storage deletion goes through `GenerationStore.deleteModelStorage`, which
checks active requests/residency/queued work and closes new admission while deleting.
Folder changes close download admission, pause every request and await file closure.
`AppTermination` defers normal Quit while `GenerationStore.shutdown` settles tasks,
then the runtime seam synchronizes Metal before allowing process teardown.

## How a generation runs

Three types in `ZephraEngine`, one concern each. The split is what lets the
engine be tested in seconds without Metal.

- `GenerationStore` (`@MainActor @Observable`) is the only object the UI
  observes, and it is split across `GenerationStore+*.swift` by concern —
  loading, generation, the queue, batches (several seeds of one prompt from
  one press of Generate), model switching, history, availability, preview,
  the reference picture, the library, following the run, upscaling and filing
  the upscaled result. Add a new concern as another extension file, not as more
  lines in `GenerationStore.swift`.
- `InferenceActor` is the only place backend code runs. It overrides
  `unownedExecutor` with a serial `DispatchQueue`: a generation is tens of
  seconds of synchronous Metal work, and on the cooperative pool that would
  starve every other task in the process. Backends are not `Sendable`, which is
  why a registry of `@Sendable` factories goes in and the backend is built here.
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
`watchRun()` follows again, `isShowingRun` is "following, and something is
running", and `hasPicture` in the app target is `current != nil || isShowingRun`,
so the inspector has something to describe from the moment a run starts. The
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
most 32 cells, and decodes that through the family's own autoencoder with the
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
  file that failed. `LibraryQuery` holds the scope, the text, and the sort, and
  `sections` are recomputed when it changes — the view never filters.
- Deleting moves the file to `Recently Deleted/` with a `deletedAt` in that
  folder's own manifest, and a scan purges anything older than thirty days.
  Nothing is unlinked on the user's behalf before then.
- `LibrarySelection` holds what is chosen; `LibraryCursor` is the pure
  arithmetic of moving through a grid, so keyboard navigation is tested without
  a window. `ImageFacts` formats the seven rows the inspector shows.

## The app target's shape

Four directories, by what a file is rather than what screen it is on:

- `Style/` — the chrome: `ZephraChrome`'s radii and hairlines, `ChromePanel`,
  `Chip`, `SectionHeader`, `CountBadge`, `KeyValueRow`, `WrappingHStack`,
  `ModelDot`. A view that reaches for a literal radius or a raw colour belongs
  here instead. Safelight amber means "only while the model works" and appears
  nowhere else. The radii step down by what a thing is: 16 for the capsule,
  8 for a card or a thumbnail, 5 for a square on the sidebar's wall, so a card
  reads as a thing to act on and a square as a thing to look at.
- `Workspace/` — which pane is up, which query the library is showing, whether
  the inspector is open, and the labels those enums draw themselves with.
  `WorkspaceSelection` is one `@Observable`, injected by the composition root
  and persisted through `AppSettings`.
- `Support/` — caches, exports, pickers, previews. The thumbnail pipeline lives
  here: `ThumbnailKey` names a baked file by path, mtime, size and edge,
  `ThumbnailFolder` is an actor that bakes off the main thread, and
  `ThumbnailCache` coalesces the in-flight requests. Nothing decodes an image
  on the main actor. `AppSettings` is the one list of preference keys and
  starting values; a preference is bound with `@AppStorage` at its picker and
  read outside a view through `AppSettings`'s helpers. `DirectoryRow` is the
  labelled path with an Open button that General and Models both show, plus
  whatever else that folder can be done to — which in Models is `Change…` and
  `Use Default`, in `ModelsDirectoryRow`. The appearance
  preference is applied by `AppearanceApplier`, set on `NSApp` from the
  composition root rather than as a colour scheme on a scene, so the Settings
  window, the menus, and the alerts change with the main window.
- `Views/` — one subfolder per surface (`Canvas/`, `Library/`,
  `Library/Inspector/`, `Library/Viewer/`, `ReferencePicker/`, `Sidebar/`,
  `Sidebar/Timeline/`, `Toolbar/`); the prompt capsule, its controls, the
  commands, and Settings
  sit at the top of `Views/` because they belong to no one surface. The
  three-stored-property rule is what keeps them small; a view that needs a
  fourth wants a subview. `Sidebar/CanvasSidebar` is the canvas sidebar,
  which builds today's runs once and hands them to `Sidebar/Timeline/` — a
  card per run still waiting, the running run's card in amber, and under those
  the wall of today's pictures in small squares — and to the "Today in
  Library" bar pinned at its foot. `SessionTimeline` in `ZephraEngine` works
  out the runs and lays the wall as one flow, newest run first with the
  running run's dashed places at its head (a block per run ended every batch's
  row early and made the wall ragged); nothing here filters, groups, or sorts. The inspector is `WorkspaceInspector`, a
  fixed column `WorkspaceDetail` puts beside whichever pane is up, under the
  toolbar rather than splitting it, and only when it has something to
  describe: always in the library, on the canvas only while a picture is
  showing (`GenerationStore.hasPicture`, which the toolbar toggle and the menu
  read too). `Library/Inspector/` describes the grid's selection and
  `Canvas/CanvasInspector` the picture on the canvas, which is the library's
  own inspector once the file is indexed and `FreshImageInspector` until then.
  An empty canvas shows `CanvasEmptyState`, with the last three prompts from
  the index (`RecentPrompts`, nothing persisted) as chips. On Liquid Glass
  the window toolbar floats over content by default, so `RootView` forces
  its background visible (`.toolbarBackgroundVisibility(.visible, for:
  .windowToolbar)`), making it an opaque full-width strip with a hairline
  under it; `CanvasView` no longer ignores the vertical safe areas, and
  `WorkspaceDetail`'s `HStack` (the pane, its `Divider`, and the inspector)
  stays inside the top one too, so the sidebar, the pane, and the inspector
  all start below the strip rather than the divider cutting through it.

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

  A double-click in the grid, or Return on the selection, no longer opens the
  canvas — it opens `Library/Viewer/LibraryViewer`, the picture full size in
  the library pane itself, with `LibraryViewerBar` over the top ("Library"
  back, "n of N", previous/next) and `LibraryViewerNavigation` underneath
  (Escape or a second double-click closes it; the arrow keys step, crossing
  day headings the way the grid's own do, through the pure arithmetic in
  `ZephraEngine`'s `LibraryViewerStep`). `WorkspaceSelection.viewing` names
  the one item shown, cleared whenever the pane changes; `LibraryPane` is the
  one place that keeps the grid's selection in step with it, so the inspector
  beside the viewer always describes what is on screen and closing scrolls
  the grid back to it. "Open in canvas" — the `\.openLibraryItem` action, on
  the cell's menu, the sidebar wall, and the inspector's own button — is
  unchanged; the viewer answers to the twin `\.viewLibraryItem` instead.

  What the canvas shows while the model works is decided by one question,
  `GenerationStore.isShowingRun`. While it is following, `CanvasView` draws
  `Canvas/LivePreviewView` — the run's own frames, a `CGImage` over the RGBA8
  bytes, `.medium` interpolation because a frame is an estimate, letterboxed
  into the run's own aspect so the finished picture lands in the rectangle its
  frames were filling. Before the first frame that rectangle is empty and the
  step segments ride across it. There is no context menu and nothing to drag,
  because there is no file yet; a click still tucks the prompt away.
  `Canvas/RunningRunInspector` is the column beside it: prompt, model, size,
  the step of how many, seed, elapsed and left — the last two from the pace
  `store.state` already measures rather than a clock of the view's own — and
  Stop. When it is *not* following, the picture is on the canvas at full
  strength even with the model running; the dim to 60 % went with the frames,
  which say "this is not the new one" properly.
  `Sidebar/Timeline/RunningRunCard` is the way back: a button calling
  `watchRun()`, still amber, wearing the accent ring the wall's squares wear
  when the canvas is showing the run — and no square wears it meanwhile —
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
anything. Every number in an entry is hand-written because every number is
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
   `registry.register(.yourFamily, YourBackendFactory.make)` and the family's
   `InferenceRuntime` in the `CombinedInferenceRuntime` list beside it. That
   file is the only place in the app target allowed to name a concrete backend.

Then the places that are not the app, each a one-line switch case or list entry:
the package and target dependencies in `project.yml`, `MLX_PACKAGES` in the
`Makefile` so `make test-mlx` runs its suites, `QuantizeFamily` in
`Sources/ZephraQuantize` if the family has a packing plan, and `BenchBackends`
in `Sources/ZephraBench` so `--model` can name it.

A saved choice that is no longer on the disk — a local build deleted from
Settings > Models, or a preference carried to a Mac that never made it — is not
loaded into a failure: `bootstrap` reads availability first and
`GenerationStore.fallBackIfUnobtainable()` steps onto the first model this Mac
can run and does have. A model that merely needs a download is kept, since
choosing it chose the download. The chosen model is persisted from the
composition root's `onChange` of `store.descriptor`, not by the menu, so the
model the engine stepped onto is the one the next launch opens on.

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
three families now have one: FLUX.2 klein's two variants, the 4-bit Z-Image
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
reads one, in one of the two ways the next section describes.

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
beside Clear. Both states also take a drop of a `LibraryItemReference`, the
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
- `make test` — `swift test` in `Packages/ZephraKit` (Core, Snapshot, and
  Engine, fast, no MLX). Anything testable without Metal belongs here.
- `make test-mlx` — `xcodebuild test` over every package that links MLX
  (`MLX_PACKAGES` in the Makefile, written `directory:scheme`). Slower, needs
  `xcodebuild`. `make test-backend` is kept as an alias. Keep `make test`
  MLX-free.
- `make icon` — re-render `AppIcon.appiconset` from `scripts/make-icon.swift`.
- `make signed-build` — build Release and sign the app with a Developer ID
  Application identity. Sources `~/Documents/Zephra Signing/signing.env` when present.
- `make release` — build Release, sign with a Developer ID Application identity
  (hardened runtime, secure timestamp), verify, and package `build/Zephra.zip` plus
  signed `build/Zephra.dmg` with an Applications shortcut. Secure timestamping
  needs Apple's server. `SIGN_IDENTITY` overrides the auto-detected certificate.
- `make notarize` — submit the ZIP, require Accepted, staple and verify the app,
  then rebuild both packages. Submit the signed DMG separately, staple it, and
  verify its ticket, image checksum, signature, and Gatekeeper assessment. It reads
  App Store Connect API-key variables from the signing config, or falls back to
  the keychain profile named by `NOTARY_PROFILE`.
- `make notarized-release` — produce the notarized DMG and ZIP; packaging and
  notarization run sequentially even with `make -j`.
- `make prefetch` — download the default model weights with `hf download`
  into `$(MODELS_DIR)/Downloads/mzbac--Z-Image-Turbo-8bit`, which is where the
  app itself would have written them, so a first launch finds them. Set
  `MODELS_DIR` when Settings names another folder.
- `make prefetch-flux2` — the same for the FLUX.2 klein 4B release, without the
  7.75 GB single-file checkpoint the loader never reads, so a first launch skips
  the download and goes straight to the build.
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
- `make quantize-qwen` — likewise for Qwen-Image, from `QWEN_SOURCE` with
  `QWEN_LORA` merged into its transformer, into
  `~/Library/Application Support/Zephra/Models/qwen-image-2512-4bit`
  (`QWEN_OUT` overrides). About a minute with the source local. The app fetches
  the same two things itself and does the same build; this is for keeping the
  57.7 GB source off the boot volume.
- `make quantize-flux2` — the build the app does on first load, by hand: pack
  the klein release from the app's own folder (or `FLUX2_SOURCE`) into
  `~/Library/Application Support/Zephra/Models/flux2-klein-4b-4bit`
  (`FLUX2_OUT` overrides; `BITS=8` needs one, as above). About a minute.
- `make lint-layers` — enforce the layering rules above.
- `make logs` — stream app logs (`log stream`, subsystem `io.zephra`).
- `make screenshot` — capture the app window (see debugging hooks).
- `make clean` — remove build output and the generated project.

The first Release build compiles MLX's Metal kernels from scratch and takes
several minutes. Always benchmark and make performance claims against
Release, never Debug — Debug has Metal validation and full debug info on.

## Starting from a picture

Every model Zephra ships can take a reference picture, and they take it in two
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

`referenceStrength` is a plain `Double`, not an optional, because every
generation has one whether or not its model reads it, and 1 is the value that
changes nothing. `ModelCapabilities.referenceStrengthBounds` says whether it
applies at all: a degenerate `1...1` means it does not, the way `guidanceBounds`
of `0...0` means guidance does not, and `clamp` pins it there. klein declares
`1...1`; Z-Image and Qwen-Image declare `0.1...0.9` with a default of `0.6`. So
the interface can decide whether to draw a slider by reading the range, without
knowing which family it is looking at.

For the models where it does apply:

- Strength reads as "how much of the picture to throw away". 1 discards it
  entirely and is the ordinary text-to-image path; 0 would return it unchanged.
  Neither end is offered, which is why the bounds stop at 0.1 and 0.9.
- **Strength buys a share of the steps, not a noise level.** `steps * strength`
  of them run, rounded and never fewer than one, and the loop enters that far
  from the end, starting from the encoded picture mixed with that step's share
  of the run's own seeded noise. So 0.6 of Z-Image's nine steps enters at 4 and
  runs 5; 0.6 of Qwen-Image's four enters at 2 and runs 2. This is diffusers'
  `get_timesteps` mapping, and following it rather than entering at the first
  sigma at or below the strength is load-bearing: a distilled ladder is not
  evenly spaced. Qwen-Image's four sigmas are 1.0, 0.767, 0.456 and 0.02, so the
  noise-level reading sent every strength from 0.1 to 0.4 to that 0.02 and handed
  the picture back untouched.
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

- `make test` — `ZephraCoreTests`, `ZephraSnapshotTests` and `ZephraEngineTests`,
  seconds, no Metal.
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
- `QwenImageKit`'s suites check the port against tensors dumped from
  `diffusers` by `Packages/QwenImageKit/Tools/dump_reference.py`. Adding a
  component means adding its fixture in the same commit; that is what the
  clean-room claim in `PROVENANCE.md` rests on.

No test loads model weights. The `ZephraKit` suites never touch Metal; the MLX
packages' suites run doll's-house tensors through it, and a few of `QwenImageKit`'s
and `Flux2Kit`'s read a real snapshot's config, tokenizer, and safetensors header
files when `QWEN_IMAGE_SNAPSHOT` or `FLUX2_KLEIN_SNAPSHOT` names one (or the hub
cache holds exactly one snapshot). The engine tests drive `MockBackend`
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
`.incomplete` bytes, so a retry and a later Try again both continue rather than
start over. Only a missing repository, a missing file, or a 4xx that is not a
timeout or a rate limit stops the retrying early.

Settings > Models lists every directory the catalog's models have on this Mac —
the app's own folder first, then either hub layout — with where it is, its size,
and a Delete that permanently removes its files after confirmation. `ModelStorage` in `ZephraSnapshot` is
the listing and the measuring; `ModelInventory` in `ZephraEngine` is what the
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
`make quantize` is the same build by hand. 6.7 GB on disk (`builtBytes`) and
6575 MB resident, against 13.3 GB and 12236 MB for the 8-bit model. Peak follows
the image size — 10693 MB at 512 pixels, 14599 MB at 768,
17839 MB at 1024 — because peak is resident plus the unquantized VAE decode's
scratch. So a 16 GB Mac is offered this variant and can run it at 512 and 768, but
1024 will page. Four bits is not faster: MLX's quantized matmul costs the same at
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
and the entry's `peakBytes` is measured there.

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
took 66 s, the reference's 1024 tokens riding through every attention layer. The
stream runs in bfloat16; `ZEPHRA_DIT_DTYPE=f32` is the escape hatch for the
mlx-swift split-K bug on M5-class GPUs, at three times the step time, and the
packer's float32 scales are cast to the stream's dtype at load, without which MLX's
quantized matmul widens every activation to float32.

Two of this port's choices are load-bearing and easy to undo by accident. The
schedule uses the pipeline's empirical shift, not the scheduler config's
`base_shift` and `max_shift`, which klein's pipeline never reads. And the
query-key norm epsilon is the config's 1e-6, where both MIT ports use 1e-5;
`PROVENANCE.md` lists these with the other two departures.

The same checkpoint edits: a reference picture is fitted to at most a megapixel
keeping its shape, trimmed to multiples of 16, encoded, and its tokens placed
after the image being made on image index 10 of the rotary embedding's first
axis. The schedule's shift counts only the image being made.

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
that looks exactly like a build that worked.

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

Weights stream one tensor at a time out of the memory-mapped source shard and spill
once four gigabytes have accumulated, so a 24 GB float32 transformer converts at
about 8 GB resident. The whole build takes about a minute once the source is local.

## Vendored code

`Packages/ZImageKit` is a vendored copy of `mzbac/zimage.swift` at commit
`970f83e4`. See `Packages/ZImageKit/VENDORED.md` for the license situation,
the re-sync procedure, and the running patch log. Any change inside
`ZImageKit` needs a `// ZEPHRA-PATCH:` comment and a `VENDORED.md` entry.

## Conventions

- Conventional Commits for all git messages.
- Swift 6 strict concurrency in our code. The vendored `ZImageKit` package
  stays in Swift 5 language mode so its 49 upstream files compile untouched.
- Every package pins the same exact `mlx-swift` version. When bumping it, re-run
  `Flux2Kit`'s bf16 matmul probe test: mlx-swift up to 0.31.6 miscompiles a
  bf16 split-K matmul on M5-class GPUs at the single block's output shape, and
  the port relies on its conditioning stream being float32 to stay clear of it.
- No emojis in code or docs.
- Keep files small; split before a file grows past its target size.
- `ROADMAP.md` is where deferred work lives: an option considered and left out
  goes there in the same change, not only in a session note.
- Zephra may ship commercially. Every new dependency, vendored file, or model
  gets an entry in `THIRD_PARTY_NOTICES.md` (copyright line, license, and any
  NOTICE file) in the same commit. That file is bundled and shown in
  Settings > About; it is the disclosure, so keep it exact.

## Debugging hooks

- `ZEPHRA_PREVIEW_STATE=ready|image|editing|tucked|generating|queued|watching|batch|library|viewer|picker|downloading|building|failed`
  launches a Debug build frozen in that state with no model, for screenshots (`make screenshot`).
  `tucked` is `image` with the canvas's floating prompt slid down to its lip.
  `viewer` opens the library pane on its first image full size; `picker` runs the
  `editing` build with the reference picker sheet forced open, through
  `InterfacePreview.wantsReferencePicker` — the one flag the well reads on its own,
  since a `@State` local to a view cannot be set from the composition root the way
  `workspace.viewing` can.
  `generating`, `queued` and `watching` all stand a run up with a made-up frame from it, so
  the live preview is on screen without a model: the first two are following the run, and
  `watching` is the one that is not — the model working while an earlier picture stays on the
  canvas, which is what the running card's ring being off says.
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
  which on a shared machine means somebody else's windows end up in `out/`.
- `make bench ARGS="--size 1024 --steps 9 --runs 3 --json"` measures load, s/step, and peak memory
  headlessly; benchmark on an idle machine, Release only. `--reference IMAGE` measures the
  editing path on a model that has one.
- `make bench ARGS="--reference design/mock/img/a2.png --strength 0.6"` adds the strength, on a
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
  sets. Measured at 1024 pixels on an M4 Max, mean over the frames of one run: 43 ms for klein
  4-bit, 130 ms for Qwen-Image 4-bit, 192 ms for Z-Image 8-bit, against 0.5 to 8 s for the same
  models' full decodes. The machine was not idle for the last two, so those are ceilings.
- `ZEPHRA_PROFILE_STEP=1` prints per-phase timings (text encode, per-step graph build, per-step
  eval, VAE decode, and Z-Image's preview decode) and MLX's active and peak allocation to stderr.
- Precision and padding switches, for bisecting a suspected regression without a rebuild:
  `ZEPHRA_DIT_DTYPE=f32` runs the transformer in float32, `ZEPHRA_PAD_PROMPT=full` pads prompts to
  the 512-token limit, `ZEPHRA_KEEP_CACHE=1` stops handing MLX's scratch back after a generation,
  and `ZEPHRA_CACHE_LIMIT_MB=N` overrides the benchmark's MLX cache ceiling.
- `ZEPHRA_VAE_TILE=<latent tile edge>` decodes the VAE in overlapping tiles and blends the seams,
  so the decode's peak is set by the tile rather than by the image. 64 gives 512-pixel tiles and
  takes the 1024-pixel peak from 23.5 GB to 17.7 GB for a mean absolute pixel difference of 1 of
  255. It is the starting value of each family's tile — `VAETiledDecode.latentTile` for
  Z-Image, `QwenImageAutoencoder.latentTile` for Qwen-Image — and so is what `ZephraBench` and
  the command line use. The app overrides it as soon as its window appears: Settings >
  Performance holds a three-way preference (`AppSettings.vaeTiling`) and `VAETilingPolicy`
  applies it for the model about to run, tiling under Automatic when that model's `peakBytes`
  is over four fifths of physical memory.

## Environment notes

- In shell tooling, use `/bin/ls` rather than the interactive `ls` — the
  shell's `ls` function can hang on this volume.
