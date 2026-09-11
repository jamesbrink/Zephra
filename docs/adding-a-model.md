# Adding a model or a backend

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

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
   the five factories build theirs; no family writes a runtime type of its
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
"Starting from a picture" in `docs/reference-pictures.md`. `DeferredModelTests` and `DeferredModelEdgeTests` pin
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
five families now have one: FLUX.2 klein's two variants, LTX-2.5's two, the
4-bit Z-Image Turbo, the 4-bit Qwen-Image, and the 4-bit Wan 2.2. In each the
release is bfloat16 and the loader
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
