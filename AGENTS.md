# Zephra

Zephra is a native macOS app that generates images locally on Apple Silicon,
via MLX/Metal. It runs four model families today, Z-Image-Turbo,
Qwen-Image-2512, FLUX.2 klein 4B, and LTX-2.5 (video), behind one backend seam.

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

What trips a first session: `swift build` and `swift test` work only in
`Packages/ZephraKit`, because everything else links mlx-swift and its Metal
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
  pinned by dumped fixtures; nothing copied from `Lightricks/LTX-2`. Video only.
- `Packages/WanKit`: ours, from Apache-2.0 `diffusers` and `transformers` and
  the release's configs, pinned by dumped fixtures; no other port of Wan read.
- Each kit's `PROVENANCE.md` lists its deliberate departures; keep it true.
- `ZephraUpscaleRealESRGAN`: the Real-ESRGAN upscaler, an `ImageUpscaler` beside
  the backends, taking `ZephraMLX` and no family kit; no backend imports it.
- Nothing in the app target may import a model package or `MLX`. Only
  `Sources/Zephra/ZephraApp.swift` may import a `ZephraBackend*` or
  `ZephraUpscale*` package, to register it.
- No backend package may import another backend package.

Code rules:

- One public type per file; file name matches the type name.
- Target ≤150 lines per file.
- No `*Manager`, `*Helper`, `*Utils`, or `*Service` type names. The one exception
  keeps AppKit's own name: `PromptLayoutManager` is an `NSLayoutManager`.
- Views hold at most 3 stored properties, or get split into subviews.
- `ModelCatalog` is the only static registry in the codebase. No other singletons.

Run `make lint-layers` before every commit. It fails on forbidden imports across
the layers above, on any repeating animation in the app target, on `hoverWash`
used anywhere but under `allowsHitTesting(false)`, on British spelling in
user-facing string literals (except `LibraryScope`'s persisted `"favourites"`),
and on the type-name ban. `make lint-size` is advisory only: it lists files over
150 lines. The three-stored-properties rule is not linted; apply it by eye.

Full detail: `docs/architecture.md`.

## First launch

A Mac that has never run Zephra opens on a model chooser, not on a download.

- `WelcomeGate` (`Support/`) is the whole decision, resolved from preferences
  **synchronously in `init`** so the chooser is up before the first frame.
  `hasAnswered(in:)` is the `hasChosenModel` flag once written, and before that
  the presence of `selectedModelID`, which the root writes on every launch, so
  its absence is what a genuinely first launch looks like; the root writes `selectedModelID` only when
  the chooser goes down, never while it is up. `settle(availability:budget:current:)`
  dismisses the chooser when the survey finds a model already here and answers
  which model to continue on; nil for a chooser already down. `dismiss()` records
  the answer (a skip is an answer); `reopen()` is the way back from
  `CanvasStateView`'s idle state.
- `WelcomeHost` (`Views/Welcome/`) shows the chooser or `RootView`. With the
  chooser up, `bootstrapFromInterface` runs only `surveyAvailability()`.
  **Nothing is fetched while the chooser is up.**
- The recommendation is `ModelCatalog.default(fitting:)`; where nothing fits, the
  entry with the smallest `ModelDescriptor.leanestPeakBytes`.
- Cards are `ModelChoice.all(for:)`, every catalog entry judged once against one
  budget. Nothing is hidden or disabled by memory. A card's size is
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
  upscaling, interaction, downloads, the two folder changes, residency. **Add a
  new concern as another extension file**, never as more lines in
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

A backend returns `GeneratedMedia`: `.image(png:)` or `.video(GeneratedVideo)`
(MP4, poster PNG, frame count and rate). One return type, because only the last
step reads the kind. `GenerationSettings.frames` is 1 for a picture, pinned by
`clamp` where `frameBounds` is `1...1`, and snapped to `frameAlignment` for a
video model.

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
`Support/`, which gives `AppSettings.store` a throwaway suite and its own
`Models` and `Images` folders; the hub cache is deliberately not redirected).

Four directories, by what a file is rather than what screen it is on:

- `Style/` — the chrome. `ZephraChrome` holds every radius, hairline and
  height; `ZephraChrome+Washes` every colour laid over things. A view reaching
  for a literal radius or a raw colour belongs here instead. Safelight amber
  means "only while the model works" and appears nowhere else. Radii step down
  by what a thing is: 16 capsule, 10 reference well, 8 card or thumbnail, 6
  field, 5 wall square.
- `Workspace/` — which pane is up, the library query, whether the inspector is
  open: `WorkspaceSelection`, one `@Observable` injected by the root and
  persisted through `AppSettings`.
- `Support/` — caches, exports, pickers, previews, and the single homes for
  cross-cutting answers listed below.
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
  appearance on `NSApp` so Settings, menus and alerts follow.
- `CommandTarget` is what the file commands are about: the canvas's picture
  while the canvas shows one with a file, else the grid's focused selection,
  else nothing — no fallback from an empty selection to the picture behind it.
- `ReferenceRole` spells every string a reference picture's role changes,
  from `ModelCapabilities` (`.firstFrame`, `.startFrom`, `.reference`, in that
  order). `ModelLoadNote` is what Generate's and Animate's tooltips say a press
  costs first. `StepProgress` is the step bar's reading, so it never counts the
  slider. `SeedEntry` is the one seed parser and `SizeEntry` the one size
  parser (two numbers with anything between, fitted to the model's grid
  through `ModelCapabilities.fit`); `SizeMenu` groups presets by `SizeTier`
  and offers Custom Size… on every model. `AppSettings.seedFormat` is how a
  seed is spelled on screen, read from the environment everywhere — nothing on
  disk follows it.
- `BackgroundNotice` is a pure function over two engine states saying what is
  worth a notification while another app is in front; `BackgroundNotices.post`
  is the one place `UNUserNotificationCenter` is touched, posts only when
  `NSApp` is inactive and the General toggle allows, and asks permission the
  first time it has something to say.

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
- `SettingsView` is three tabs. `SettingsTab` gives the opening height;
  `minimumHeight` is one number for all three and must fit a 13-inch MacBook
  Air, since AppKit can only clamp a window that fits. `SettingsWindowFrame`
  configures the window from a zero-sized `NSView` and *observes* the
  resizable flag, putting it back whenever SwiftUI strips it. Escape does not
  close Settings.
- About is two windows (`AboutScenes`): About Zephra (`AppFacts` holds the
  strings) and Acknowledgments, which lays `THIRD_PARTY_NOTICES.md` out through
  `NoticesDocument`. There is no Settings > About. `HelpCommands` replaces the
  synthesized Help menu.
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
- `ClipPlayerView` is AVKit's `AVPlayerView` over the MP4, looped and muted,
  never SwiftUI's `VideoPlayer` (its controls take the tuck click and it
  crashed resolving its superclass), which is why `project.yml` links
  `AVKit.framework` explicitly. Clips keep playing during a run.
- `DurationControl` shows only when `frameBounds` is a range; `StepsControl`
  hides when `stepBounds` is a single value, as guidance already does.
- Every picture wears the same right-click menu: `LibraryItemMenu` once
  indexed, `FreshImageMenu` before, `CanvasImageMenu` choosing for the canvas.
- Animate sits beside Use as Reference everywhere and both show disabled
  rather than hidden. Animate goes through `ReferenceAdoption.animate`, never
  `adopt` (which hands back an edit's source); a clip's last frame comes from
  `ClipFrames.lastFrame(of:)`.
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

## Adding a model or a backend

Both cases are additive: no view and nothing in `ZephraEngine` learns the
model's name.

**A model an existing backend can already run** — one entry in that family's
`Packages/ZephraKit/Sources/ZephraCore/Model/ModelCatalog+<Family>.swift`
(Z-Image's two are in `ModelCatalog.swift`), listed in `all`. `ModelDescriptor`
carries the `ModelSource`, the download and resident sizes, and a
`ModelCapabilities` the interface draws itself from — size presets and bounds,
step and guidance bounds, negative prompt and seed, and for a clip model
`frameBounds`, `defaultFrames`, `frameAlignment` and `frameRate` (a range in
`frameBounds` draws the length control and says the backend answers
`GeneratedMedia.video`). Every number in an entry is measured; leave a comment
saying where it came from.

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

- `bootstrap` reads availability first; `fallBackIfUnobtainable()` steps a
  saved choice no longer on disk onto the first model this Mac can run and has.
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
  wear an `UpscaleBadge` (`Style/`).
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
work only in `Packages/ZephraKit`. The first Release build compiles the kernels
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
- `lint-layers` — the gate, before every commit. `lint-size` — advisory list
  of files over 150 lines.
- `icon` — resize the approved masters in `design/branding/zephyr/`; never
  replace the artwork with a procedural glyph.
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
  — that, then `scripts/deploy-website.sh` to `zephra-site-urandom-io`; only
  when James says "deploy to production".
- `release-upload` — `scripts/publish-download.sh`: upload the DMG, copy the
  alias, verify the public download, write `product-mockups/app/release.json`.
- `prefetch`, `prefetch-flux2`, `prefetch-qwen`, `prefetch-ltx2`,
  `prefetch-wan` — `hf download` a release to where the app would have written
  it (`MODELS_DIR`, `QWEN_MODELS`, `LTX2_MODELS`, `WAN_MODELS`); the Qwen, LTX
  and Wan ones name files explicitly because those repositories ship more than
  the build reads.
- `quantize`, `quantize-qwen`, `quantize-flux2`, `quantize-ltx2`,
  `quantize-wan` — the build the app does on first load, by hand, into the
  app's models folder (`QUANT_OUT`, `QWEN_OUT`, `FLUX2_OUT`, `LTX2_OUT`,
  `WAN_OUT`; `BITS`, `GROUP_SIZE`).
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

## Tests

Swift Testing (`@Suite`/`@Test`), never XCTest. Name suites and tests as
sentences about behaviour.

- `make test` — `ZephraCoreTests`, `ZephraSnapshotTests`, `ZephraEngineTests`,
  `ZephraMediaTests`; seconds, no Metal. Anything testable without Metal
  belongs here.
- `make test-app` — `Tests/ZephraTests`, hosted in the Debug app
  (`@testable import Zephra`; Release turns testability off). Pure interface
  logic, nothing that needs a window. The scheme sets
  `ZEPHRA_PREVIEW_STATE=ready`. A test needing a media file reads one under
  `Tests/ZephraTests/Fixtures`; never write one with `AVAssetWriter` inside the
  host, which leaves the host unable to exit.
- `make test-mlx` — the MLX packages, through `xcodebuild`.
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
  `castFloatParameters` patch makes them bfloat16 at load.

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

`LayerWeightStream` (`ZephraMLX`) runs Qwen-Image and LTX-2.5 on a GPU that
cannot hold them by reading the model from disk every step. MLX reads a shard's
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
byte the resident one.

What decides it: `ModelDescriptor.streamedPeakBytes` (zero for a family that
cannot stream); `MemoryFit` tries it after `fitsTiled` and answers
`fitsStreamed`; `WeightResidencyPolicy` turns the Performance preference and
the budget into a `WeightResidency` for the load, streamed under Automatic
exactly when the verdict is `fitsStreamed`. `InferenceActor` pins the residency
beside `loadedPath`, so asking for the same model the other way is a reload.
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

### LTX-2.5: `ltx-2.5-distilled-4bit`

- **Video only**: the audio stream is a seam (`ROADMAP.md`), and its absence
  changes the pictures, since `audio=None` drops the audio-to-video term.
- Lightricks' repositories are gated and Zephra sends no token, so the catalog
  names the ungated `mlx-community/ltx-2.5-mlx` pack: five files (distilled
  transformer, connector, Gemma 4 encoder with tokenizer, video decoder, video
  encoder), the audio and dev files omitted by pattern. The mirror is the path
  users take.
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
  `audioOmitted`, which `WeightKeyCoverageTests` keeps in step with
  `LTX2TransformerWeights.audioMarkers`. The aggregate projection's scales stay
  float32: 188160 products summed in bfloat16 lose the prompt.
- `LTX2Tokenizer` is Zephra's own byte-pair encoder keyed by UTF-8 bytes,
  pinned against Hugging Face's ids; it prepends BOS (id 2), truncates keeping
  the front, and left-pads to 1024 with id 0.
- Both 48-layer stacks stream under `WeightResidency.streamed`; resident, the
  transformer evaluates every eight blocks (`blocksPerEval`) to stay under the
  watchdog. The decoder has no tiled path, so `tiledPeakBytes` is the plain
  peak. The warm-up run costs a full eight-step, nine-frame clip plus an MP4
  encode.
- **Two stages** (`LTX2StagePlan`, in the backend): a frame whose short edge is
  512 or more and whose edges halve onto the 32 grid runs the eight-step ladder
  at half the size, doubles the latent through the pack's spatial upsampler
  (`LTX2LatentUpsampler`, the `upsampler` component, copied whole), noises it to
  the second ladder's top and walks `LTX2DistilledSchedule.secondStage` (three
  steps) at the full size; the run reports eleven steps as one count. A held
  first frame is encoded at each size. `ZEPHRA_VIDEO_STAGES=1|2` forces either
  for one launch. A variant packed without `upsampler` reads as unbuilt.

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
- Both stacks stream under `WeightResidency.streamed`; the autoencoder decodes
  one latent frame at a time and has no tiled path.

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
- Every package pins the same exact `mlx-swift` and `swift-transformers`
  versions, `ZImageKit`'s manifest included. A swift-transformers bump is
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

- `ZEPHRA_PREVIEW_STATE=ready|image|editing|tucked|clip|generating|starting|queued|watching|finishing|batch|library|viewer|picker|welcome|downloading|building|failed|settings`
  launches a Debug build frozen in that state with no model, for `make
  screenshot`. `tucked` is `image` with the prompt slid to its lip; `welcome`
  opens the chooser whatever the preferences say; `viewer` opens the library on
  its first image full size; `picker` is `editing` with the reference sheet
  open (`InterfacePreview.wantsReferencePicker`); `clip` stands the store on
  the invented `PreviewModel.video` with a poster stamped as
  `ModelCatalog.ltx2Distilled4bit`, since the inspector reads the record's
  model; `generating` and `queued` follow a made-up run, `watching` does not,
  `starting` has no frame yet, `finishing` is a clip after its last step;
  `downloading` and `failed` sit over a picture. `settings` freezes the engine
  but uses a live library index at the configured `imagesDirectory`, for
  folder-change UAT with temporary fixtures.
- `ZEPHRA_FRESH_START=<directory>` launches as a Mac that has never run Zephra:
  its own preferences suite, `<directory>/Models` and `<directory>/Images`, and
  the single-instance guard lets it run beside a real Zephra. `make run-fresh`.
- Debug only: `ZEPHRA_DOWNLOAD_TEST_HUB=http://127.0.0.1:<port>` runs the real
  downloader and UI against disposable HTTP fixtures with an unloaded exercise
  backend; use a separate preferences domain and models folder. No such hook
  exists in Release.
- `make logs` streams `os.Logger` output for subsystem `io.zephra`.
- `make screenshot` photographs the window by its CoreGraphics id and fails
  rather than grabbing the screen when there is no window; `WINDOW=<title>`
  takes the window with that title (a Settings window is titled after its tab).
- `swift scripts/ax-press.swift "<title>" [role]` presses a control by
  `AXTitle` or `AXDescription` through the accessibility tree without
  activating the app or moving the mouse; `--dump [depth]` prints the tree and
  `ZEPHRA_PID` picks the copy to drive. `swift scripts/ax-type.swift "<label>"
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
  as `.mp4` with its poster beside it; `--stream` and `--stream-depth N`
  report gigabytes read per step and the disk's rate.
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
  (2 unless set). A family that cannot stream loads resident regardless.
- `ZEPHRA_GENERATE_ON_LAUNCH=<prompt>` (Debug only; inert in Release, like
  `ZEPHRA_PREVIEW_STATE`) presses Generate once the model is ready, for a real
  in-app run from a shell. `ZEPHRA_REFERENCE_ON_LAUNCH=<path>` fills the well
  first through `adoptReference`, and Generate waits for it. `ZEPHRA_WIRED_LIMIT_MB=N`
  (0 off) and `ZEPHRA_MEMORY_LIMIT_MB=N` replay the app's limits in the bench;
  every `_MB` is `MemoryUnits.mebibyte`.
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

Website iterations and modifications go to ChatGPT Sites first. When James says
"deploy to production", deploy the website to AWS with `make deploy-production`.
The website bucket is `zephra-site-urandom-io`; notarized app releases belong in
`zephra-assets-urandom-io/releases/`. Keep both deployments on the same page source.
