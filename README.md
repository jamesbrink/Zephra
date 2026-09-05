# Zephra

A native macOS app that generates images locally on Apple Silicon, via
MLX/Metal. It runs Z-Image-Turbo, Qwen-Image-2512, and FLUX.2 klein 4B, edits a
picture with any of them, and upscales with Real-ESRGAN.

## Why

- **Local.** Everything runs on-device; nothing leaves the machine.
- **Fast.** MLX drives the GPU directly through Metal, tuned for Apple
  Silicon.
- **Private.** No accounts, no image uploads, no telemetry. Model downloads may continue while an image generates.
- **Native.** A real SwiftUI app, not a wrapped web view.

## Model downloads

Choosing a different model keeps earlier downloads running. Up to two repositories
transfer at once; variants that use the same source share one transfer. Only the
model needed for the next generation is built and loaded, with one set of weights
resident at a time.

Settings > Models lists downloads separately from stored files. Pause keeps partial
files for Resume; Cancel download removes unfinished files once no other model needs
them. A shared transfer continues for its remaining consumers. Downloads required by
queued generations cannot be paused from their row: remove the queued work first,
or use Stop on the canvas. A background failure stays on its own row and can be retried.

Changing the models folder pauses all downloads before moving files. Quit also keeps
partials and waits for file handles and inference to settle. After relaunch, selecting
a model resumes its partial download; background jobs do not restart automatically.

## Requirements

- Apple Silicon Mac
- macOS 15 (Sequoia) or later
- **Xcode 26 or later, the full Xcode.app.** The Command Line Tools are not
  enough: mlx-swift's Metal kernels are compiled by `xcodebuild`, which they do
  not ship. `xcode-select -p` must print a path inside `Xcode.app`, not
  `/Library/Developer/CommandLineTools`.
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`,
  or `nix profile install nixpkgs#xcodegen`.
- [`hf`](https://github.com/huggingface/huggingface_hub) CLI (optional, for the
  `make prefetch*` targets): `pip install -U huggingface_hub`.
- Disk and memory depend on the model. Peak, not resident, is what decides whether
  a Mac pages, and the tiled VAE decode (see Performance) takes a few gigabytes off
  it, so the last column is the smallest Mac each model runs 1024² on:

  | Model | Download | Built on this Mac | Resident | Peak at 1024² (tiled) | Runs 1024² on |
  |---|---|---|---|---|---|
  | FLUX.2 klein 4B, 4-bit | 16 GB | 5.4 GB | 4.9 GB | 12.1 GB (7.7 GB) | 16 GB |
  | FLUX.2 klein 4B, 8-bit | same 16 GB | 8.6 GB | 8.1 GB | 15.3 GB (10.9 GB) | 16 GB, tiled |
  | Z-Image-Turbo, 8-bit | 13.3 GB | — | 12.2 GB | 23.5 GB (17.7 GB) | 24 GB, tiled |
  | Z-Image-Turbo, 4-bit | 32.9 GB source | 6.7 GB | 6.6 GB | 17.8 GB (12.0 GB) | 16 GB, tiled |
  | Qwen-Image-2512, 4-bit | 59.4 GB source | 21.6 GB | 21.5 GB | 30.4 GB (26.1 GB) | 32 GB, tiled; 16 GB, streamed |

  A "source" download is not what gets loaded: the app packs it into the variant
  this Mac runs, on first load, and the picker says so ("32.9 GB download, then
  built"). Qwen-Image's figure is its 57.7 GB release plus the 1.7 GB four-step
  adapter merged into it. The download is kept afterwards, because the variant is
  packed from it. Everything lives in one
  folder — `~/Library/Application Support/Zephra/Models` unless you change it in
  Settings > Models — and Settings lists every directory with its size and a
  Delete that permanently removes its files after confirmation. `make quantize*` does the same builds from
  the command line, which is worth doing only to keep a source that large off the
  boot volume.

## Quick start

One-time setup on a fresh Mac, after installing Xcode.app. `make doctor` checks
all of it and prints the fix for whatever is missing:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain   # about 700 MB; the only step that needs the network
make doctor
```

The first Release build compiles MLX's Metal kernels from scratch and takes
several minutes with no output; it has not hung.

```sh
make prefetch-flux2  # optional: download the FLUX.2 klein release ahead of time
make prefetch        # optional: download the 8-bit Z-Image weights
                     #           both land in the folder the app downloads into
make build
make run
```

The first launch opens on the first model in the catalog that fits this Mac:
FLUX.2 klein 4B on 16 GB, 8-bit Z-Image-Turbo on 32 GB and up. If nothing was
prefetched, the first run downloads it (16 GB for klein, then a one-minute build;
13 GB for Z-Image) before it can generate anything. The window stays responsive
with a progress readout while that happens.

## Using it

- Zephra is one window (⌘W closes it; the Dock icon brings it back), plus Settings. The
  window is a sidebar and one of two panes, and the sidebar changes with the pane. On
  Canvas (⌘1) it is the session: the search field (⌘F) over today's runs — what is waiting,
  what is being rendered, and the images as they come out. On Library (⌘2) it is the search
  field, chips for everything and favourites, and the collections to look in — every image,
  favourites, the last seven days, one row per model with a count, the tags in use, albums,
  and Recently deleted and New Album pinned at the foot. Canvas is the picture with the
  prompt floating over it and, in the sidebar, today's run as a wall of small squares that
  fill in as the seeds land; an empty canvas offers the last three prompts as chips. Library
  is everything made so far, in day-grouped grids with a filter bar over them. The inspector
  (⌥⌘I) sits beside either pane, under the toolbar: in the Library it describes whatever is
  selected, on the canvas the picture showing, and it stays away until there is one. Typing
  in the search while the canvas is up takes you to the Library showing the hits, and
  clearing the field puts you back where you were.
- New Album (⌘N, or the bar at the foot of the sidebar) makes one called "Untitled Album"
  and puts the cursor in its name, in the row itself: Return keeps what you typed, Escape
  keeps "Untitled Album", and clicking away keeps what you typed, as the Finder does. Rename
  in a row's menu edits the same way. Drag images from the grid onto an album row to file
  them — the row rings in the accent colour as you come over it, and dragging one of several
  selected images files all of them.
- The Library's filter bar says what is being shown and how much of it is selected, carries
  a removable token per filter, and has a slider for the thumbnail size (⌘+ and ⌘− step it).
  Click to select, shift-click for a range, ⌘-click to add one, ⌘A for all of them, arrow
  keys to walk the grid, space for Quick Look. The inspector shows the image, its prompt,
  and the Model, Size, Steps, Seed and Took rows read out of the PNG (the filename is the
  tooltip on Reveal in Finder), with its tags and albums, and offers Open in canvas, Queue a
  variation, Reveal in Finder, and Upscale 2× or 4×. Select several and it says what they
  have in common and acts on all of them.
- Upscale runs Real-ESRGAN's compact network over the picture in tiles, on any Mac, in a few
  seconds, and writes the result into the library as `<name>-x2.png` or `<name>-x4.png` with
  the original's prompt, seed and steps inside it, a row in the inspector saying what it was
  made from, and a small ×2 or ×4 badge on its thumbnail. It needs no model loaded and works
  on the canvas's picture, a library selection, and the right-click menu; it is 4× by
  nature, and 2× is that pass averaged back down. Generate waits while it runs.
- Type a prompt and press Generate (or ⌘↩); Return breaks the line, and a selection is
  painted only as far as the text. The window subtitle shows what the engine is doing.
- The control beside Generate says how many seeds one press queues — 1, 2, 4, or 8 of the
  same prompt, the first of them on the seed in the field, so a run of four is a superset of
  the one image the same press would have made.
- Press Generate again while an image is running to queue the next prompt; prompts run one
  after another and the subtitle counts what is still waiting. The sidebar's timeline shows
  the same work as one list: the runs still waiting as cards, each with a cross that takes
  the whole run back out, the run being rendered as an amber card with its steps filling in,
  and under those one wall of today's pictures with a dashed square at its head for each
  seed still to come — the image lands in its square, and a press puts it back on the
  canvas. Stop ends the current image and drops the queue; during the first-run download or
  the load it abandons that instead, and the canvas offers to pick it up again — a stopped
  download resumes from what it already fetched.
- The model menu in the toolbar names the model that is running and lists the rest, each
  with what choosing it would cost: "Downloaded", "13.3 GB download", "16 GB download, then
  built" for a variant packed on this Mac from a release it has never fetched, "Builds on
  first load" once that release is there,
  "Tiles the decode" for one this Mac reaches only with the tiled VAE decode, or "Needs N
  GB" for one whose peak is over this Mac's budget even tiled. Picking a model that has not
  been downloaded starts the download; if what was downloaded is not what gets loaded — both
  klein variants, the 4-bit Z-Image and the 4-bit Qwen-Image — the release is then packed
  into the variant this Mac runs, once, showing "Building" while it does. Memory never
  disables a row: a model
  that would page at 1024² still runs at 768², and the tooltip says so. Switching releases
  the old weights before it asks for the new ones.
  Choosing a model while an image is running interrupts nothing: the running image finishes
  on its model, anything already queued keeps the model it was queued for, and the new
  choice applies to whatever you queue next, with the engine swapping weights between queue
  entries as it goes. Your choice is remembered.
- Size, steps, and seed sit under the prompt. A model that reads a negative prompt gets a
  second field for it, and one that responds to guidance gets a guidance slider; no model
  shipped today does either, so neither shows. Every model can start from a picture, so each
  gets a well beside the prompt: drop a picture on it, on the canvas, or from the library
  grid or the sidebar's wall; click it to open a picker over the whole library; choose a
  file from a menu beside that; or use the image on the canvas as the reference (⌥⌘R;
  ⇧⌥⌘R clears it). A picture already in the well offers the same two choices, plus Clear,
  from its own right-click menu. What a picture
  means differs by model. FLUX.2 klein attends to it as extra tokens and still renders the
  whole schedule, so the picture guides the image without a strength to set. Z-Image and
  Qwen-Image start from a noised copy of it instead, so a strength decides how much of it
  survives: a strength buys that share of the model's steps, truncated and never fewer than
  one, so every strength on the slider keeps some of the picture (0.9 of Qwen-Image's four
  steps runs three of them, not all four), and less strength keeps more of the picture. The
  prompt then says what to change. An edited image carries its reference
  inside its PNG, so selecting it later puts the picture back, and an exported edit can
  reproduce itself. Steps and size stay as you set them when you switch between variants of
  one model, and steps go back to the new model's own default when you switch to a different
  model — nine steps of Z-Image's schedule and nine of Qwen-Image's four-step distillation
  are not the same request. The lock keeps the seed across runs; unlocked, every run gets a
  fresh one. Images save to `~/Pictures/Zephra` by default, with the seed in the file name; if a write
  fails, a notice sits over the prompt until an image saves, and the picture stays on the
  canvas either way.
- The sidebar's wall is today's work in one flow, newest run first: a batch's seeds sit
  together, a dashed square stands for each seed still to come, and "Today in Library" at
  the foot counts them. Images are in the library folder (`~/Pictures/Zephra` by default), and the
  Library reads that folder rather than the app keeping a list of its own. The record of
  what made an image — prompt, size, steps, seed, model, and how long it took — lives inside
  the PNG itself, so moving, renaming, or copying a file to another Mac keeps it, and
  opening an image again shows what it was made from, ready to vary. Favourites, tags and
  album membership go into the same file, under a second keyword, so they travel with the
  picture too. Each of those edits, and making, renaming or deleting an album, can be undone
  with ⌘Z from the Edit menu and redone with ⇧⌘Z, as far back as the session goes; deleting a
  picture is not on that stack, because Recently Deleted keeps it for thirty days instead. A
  PNG that Zephra did not make carries no record and is ignored. Right-click
  a thumbnail for Export, Copy, Reveal in Finder, Upscale, and Delete. Export copies the
  file itself, so what the library has written to it since goes along; exporting a file onto
  itself does nothing, and exporting several into a folder that already holds some of the names
  asks whether to keep both (numbered), replace, or cancel. Delete (⌘⌫ for the
  image on the canvas) moves the file to `Recently Deleted` inside the selected library folder, where it
  waits thirty days before it is thrown away for good. In that collection the menu offers
  Put Back — to the folder the picture came from, Sources or the library root — and Delete
  Immediately, which moves the file to the Finder's Trash and says so.
- Settings holds the appearance — System, Light, or Dark, applied to every window as the
  segment moves — with where images are written and the seed preference under General.
  Performance has the after-load warm-up, the ceiling on the GPU scratch the runtime keeps
  between generations — with the figure recommended for your Mac, and a reset back to it —
  whether the VAE decode is tiled (Automatic, Always, Never), and a live readout of active,
  cached and peak GPU memory plus which way the decode is currently set. Every change
  applies immediately. Models is the folder models are kept in — with Open, Change… and
  Use Default — and then every directory the catalog's models have on this Mac: where it is,
  what it occupies, and a Delete that permanently removes its files after confirmation. A release both klein variants
  pack from is one row, an adapter is a row named for the model it serves, a download that
  stopped part-way says so, and the model that is
  loaded cannot be deleted from under itself. Changing the folder asks whether to Move
  Models (copy, verify, publish, then remove the originals; a collision refuses rather than
  overwrites), Keep in Place (the old folder stays a read-only fallback, still listed with its
  whole path, and the next download and build go to the new folder), or Cancel. Move Models
  Here brings models from a previous folder later.
  About shows the version and the third-party license notices.
- Downloads need no Hugging Face account, and Zephra never sends a token: every model comes
  from a public, ungated repository, and no `Authorization` header goes out whatever is in
  `HF_TOKEN`, so a stale token cannot turn a public model into a login wall. Weights land in
  `<models folder>/Downloads/<org>--<repo>`, flat, exactly as the repository names them —
  nothing depends on a Hugging Face cache layout or on the `hf` tool, though a release
  already in that cache is read rather than fetched again. A transfer that breaks is tried
  again, five times with a growing pause, and resumes from the bytes already on disk; so
  does Try again after the tries run out. Pause keeps the bytes for the next attempt; Cancel
  download, offered while a model is loading or switching, discards an unfinished repository
  once nothing else is using it, and never a finished one. The message says why a transfer
  stopped rather than only that it did.
- Shortcuts: Generate ⌘↩, Stop Generating ⌘. (the item says what it stops: Cancel Download,
  Stop Building, Stop Loading, Stop Upscaling), New Album ⌘N, Undo ⌘Z, Redo ⇧⌘Z, Canvas ⌘1,
  Library ⌘2, Find ⌘F, Show Inspector ⌥⌘I, Hide Prompt ⌥⌘P, Select All Images ⌘A, Favourite
  ⌘⇧D, thumbnail size ⌘+ and ⌘−, Export ⇧⌘E, Reveal in Finder ⌘⇧R, Copy Image ⌘⇧C, Use as
  Reference ⌥⌘R, Clear Reference ⇧⌥⌘R, Upscale 2× ⌥⌘U, Upscale 4× ⌥⇧⌘U, Delete Image ⌘⌫,
  Return on a selected library image opens it full size in the viewer, Back to Grid ⌘↑ (from
  the library viewer). Export, Copy, Reveal, Delete, Use as Reference and Upscale act on the
  grid's selection while the grid has the keyboard, on the canvas's picture while the canvas
  is showing one, and are greyed out otherwise — never on a picture hidden behind the
  library. Return in the prompt field breaks the line, which is why Generate is ⌘↩; Cut,
  Copy, Paste, Select All and — while the cursor is in a field — Undo and Redo there are the
  standard Edit menu items.

### Image library location

Settings > General > Images offers **Open**, **Change…**, and **Use Default** for the
library folder. The default is `~/Pictures/Zephra`. After choosing a folder, select
**Move Images** to migrate existing images, albums, sources, and Recently Deleted,
or **Keep in Place** to leave them untouched and display the selected folder’s
library. Choose the old folder again to return to its images. New generations and
upscales save to the selected folder, which is remembered across launches.

Folder changes wait for image writes and pause library edits; finish generation,
queued work, and upscaling first. Migration verifies copied files before removing
originals, preserves embedded metadata and deletion dates, and leaves unrelated
files alone. When moving data, choose a folder without existing images or library
metadata; merging existing libraries is not supported and nothing is overwritten.
A failed move keeps the old location selected; if only removal of an original fails, the complete destination is selected and the
retained original is reported.

## How it works

Zephra keeps the UI layer completely ignorant of the model that's running it.
A backend protocol and a model descriptor catalog sit between the SwiftUI views
and each model's implementation. Adding Qwen-Image exercised that: it reached
the interface as one catalog entry and one registration line, and no view or engine
file had to learn the model's name. Adding FLUX.2 klein added two things every family
may now use: a build step between download and load, for a model whose release is
not what gets loaded, and a reference picture on the request, for a model that edits.

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
```

`ZephraCore`, `ZephraSnapshot`, and `ZephraEngine` have zero MLX dependencies,
so they build and test in seconds. A backend package is the only thing that
speaks to its family's pipeline, and no backend package may import another — a
build for one family must not drag in every other family's weights-loading
code. The MLX work no family owns — the streaming weight packer and the tiled
decode — lives in `ZephraMLXKit`, which a family may depend on and which
depends on no family. The upscaler sits beside the backends behind its own
`ImageUpscaler` protocol rather than pretending to be a model family: it needs
no model loaded and holds five megabytes.

History needs no database: every image is saved with its `GenerationRecord` as
JSON in a `zephra:generation` PNG text chunk, spliced in ahead of the pixel data
so the bytes a seed produces never change. Favourite, tags, and albums go in a
second chunk, `zephra:library`, so nothing ever rewrites the record. The
library is the folder read back as an index, from each file's header rather
than its pixels, and a watch on the folder keeps it current.

Adding a model that an existing backend can run is one entry in `ModelCatalog`:
the picker lists the catalog, and the interface draws itself from the entry's
`ModelCapabilities`. Adding a new backend is that entry plus a `BackendID`, a
package implementing `ImageGenerationBackend`, and one `registry.register(...)`
line in `ZephraApp.swift` — no view and nothing in `ZephraEngine` changes. A
family whose download is not what it loads also implements `build`, which the
engine shows as its own state; the others take the default and never build.

Every number in a catalog entry is measured by hand, on a named machine, with a
comment saying where it came from. That is deliberate: those numbers decide what
the picker offers a given Mac and when the decode is tiled, so a guessed one is
a wrong promise rather than an approximation.

## Performance

### FLUX.2 klein 4B

The small, fast model, and the one a 16 GB Mac opens on: a 3.9-billion-parameter
rectified-flow transformer conditioned on Qwen3-4B, distilled to four steps with
no guidance, and the same checkpoint edits a picture handed in beside the prompt.
The app builds it on first load from the 16 GB bfloat16 release, packing the
transformer at four or eight bits and the first 27 of the encoder's 36 layers the
same way — the transformer conditions on the hidden states after the 9th, 18th and
27th layers laid side by side, so nothing past the 27th is loaded — and copying the
168 MB autoencoder whole. `make
quantize-flux2` is the same build by hand, for benchmarking or for a copy of the
release kept elsewhere (`FLUX2_SOURCE`).

Measured on an M4 Max at seed 42, four steps, Release, idle:

| | 4-bit | 8-bit |
|---|---|---|
| resident after a generation | 4941 MB | 8144 MB |
| peak at 1024² | 12087 MB | 15289 MB |
| peak at 1024², tiled decode | 7660 MB | 10861 MB |
| peak at 768² | 9037 MB | — |
| peak at 512² | 7651 MB | 10854 MB |
| s/step at 1024² | 6.9 s | 7.0 s |
| s/step at 768² / 512² | 4.5 s / 2.1 s | — / 2.4 s |
| a 1024² image, four steps | 29 s | 29 s |
| on disk | 5.4 GB | 8.6 GB |

Twice as fast as Z-Image Turbo per image at 1024 (four steps of 6.9 s against nine of
6.3 s) at a third of the resident memory, and the first model in the catalog that runs
1024² on a 16 GB Mac with the exact, untiled decode. As with Z-Image, eight bits buys
quality rather than costing time. Editing is dearer: a 1024² image made from a 512²
reference took 66 s and peaked at 19.2 GB, because the reference's tokens ride through
every attention layer beside the image's, so on a 16 GB Mac edit at 768² or below.
Those two figures were taken while the reference's tokens were still float32, which
widened the whole edit to float32; the tokens are cast to the stream's dtype now, and
the edit is due a rerun on an idle machine.

The port in `Packages/Flux2Kit` is Zephra's own, translated from two MIT-licensed
Swift ports and pinned against `diffusers` — see `PROVENANCE.md` for the four places
it departs from those ports on purpose. The transformer runs in bfloat16;
`ZEPHRA_DIT_DTYPE=f32` runs it in float32, which is the workaround should mlx-swift's
bfloat16 split-K bug on M5-class GPUs reach it, at about three times the step time.

### Z-Image-Turbo

The model a 32 GB Mac opens on: a six-billion-parameter transformer distilled to
nine steps, downloaded as `mzbac/Z-Image-Turbo-8bit` and run through the vendored
`ZImageKit`. The 8-bit model, measured on an M4 Max:

| Machine | Resolution | Steps | Time |
|---|---|---|---|
| Apple M4 Max 48 GB, GPU shared with other apps (~50 % busy at idle) | 1024×1024 | 9 | ~57 s (6.3 s/step) |
| Apple M4 Max 48 GB, same conditions | 512×512 | 4 | ~7 s (1.6 s/step) |
| Apple M2 Ultra (upstream report) | 1024×1024 | 9 | ~44 s |

These figures are due a rerun on an idle machine; see "Where the time goes".

### Qwen-Image-2512

The large one: a twenty-billion-parameter transformer conditioned on
Qwen2.5-VL-7B, 4-bit and distilled to four steps, on the same M4 Max:

| Resolution | Steps | Time | Resident | Peak | Peak tiled |
|---|---|---|---|---|---|
| 512×512 | 4 | 6.9 s (1.6 s/step) | 21.5 GB | 26.1 GB | — |
| 1024×1024 | 4 | 33.6 s (8.2 s/step) | 21.5 GB | 30.4 GB | 26.1 GB |
| 1328×1328 (native) | 4 | 66.7 s (16.3 s/step) | 21.5 GB | 32.5 GB | 26.1 GB |

Twenty billion parameters against Z-Image Turbo's six, yet a step costs only
about a third more — 8.2 s against 6.3 s at 1024 — and four steps against nine
make the image quicker overall, with text rendering in a different class.
Resident does not move with resolution because the weights are all of it. The
tiled peak barely moves either: the tile, not the image, sets the decode's
transient, and what is left is the transformer.

The app builds the four-bit copy on first load, because nothing publishes one in a
form Zephra can load. It downloads the 57.7 GB bfloat16 release and, beside it, the
1.7 GB Apache-2.0
[four-step Lightning adapter](https://huggingface.co/lightx2v/Qwen-Image-2512-Lightning)
— one named file out of a repository that also ships whole merged checkpoints of
twenty gigabytes each — merges the adapter into the transformer as it packs, holds
the modulation layers at eight bits while everything else goes to four, and takes
about a minute. The result is 21.6 GB. `make quantize-qwen` is the same build by
hand, from `QWEN_SOURCE` and `QWEN_LORA`, which is how a 58 GB source is kept off
the boot volume.

The adapter is not optional. The base model wants fifty steps and real
classifier-free guidance — two passes through twenty billion parameters per step —
which is not a thing to do on a Mac. Merging the distillation at build time rather
than loading it at run time means the runtime never sees an adapter: what lands in
the models directory is simply the four-step model.

The stream runs in bfloat16, resident or streamed from disk, and `ZEPHRA_DIT_DTYPE=f32`
runs it in float32, the same switch klein reads. The figures above were measured
before that was true: the noise was drawn float32 and the packer's float32 scales were
never cast, so every block ran in float32 by accident. They are due a rerun on an idle
machine.

Holding modulation at eight bits is the one judgement call in the recipe. Those
layers are 6.8 of the transformer's 20.4 billion parameters and they decide how
strongly every other layer responds; four-bit builds that pack them with everything
else are reported to lose coherent structure. It costs about 3.4 GB: four more bits
for each of those 6.8 billion weights, which is the difference between the 12.8 GB
transformer a pure four-bit build would write and the 16.2 GB this one does.

The port in `Packages/QwenImageKit` is Zephra's own, written from the model's config
files and checked against `diffusers` — see `PROVENANCE.md` for why it could not be
derived from the existing Swift port.

### The 4-bit Z-Image variant

The app builds a four-bit copy of the weights on the machine itself, on first load, because no
repository publishes Z-Image-Turbo in four bits in the format the loader reads. It downloads
the 32.9 GB bfloat16 release once, packs the transformer's 270 and the text encoder's 252 linear
weights at four bits with a group size of 64, leaves the VAE alone, and takes about a minute
after the download. The result is 6.7 GB on disk against 13.3 GB for the 8-bit model.
`make quantize` is the same build by hand.

Measured on an M4 Max at seed 42, 9 steps, arms interleaved within each repetition because the
machine was busy. Memory was identical to the megabyte across repetitions; the times were not,
so they are minimums:

| | 8-bit | 4-bit |
|---|---|---|
| resident after a generation | 12236 MB | 6575 MB |
| peak at 1024² | 23501 MB | 17839 MB |
| peak at 768² | 19712 MB | 14599 MB |
| peak at 512² | 17657 MB | 10693 MB |
| s/step at 1024², machine under heavy load | 13.8 s | 14.0 s |
| on disk | 13.3 GB | 6.7 GB |

**Four bits buys memory, not speed.** MLX's quantized matmul takes the same 2.7 ms at
[T,3840]×[3840,3840] whether the weights are 8-bit or 4-bit (`make bench ARGS=--micro`): at
these shapes the kernel is compute-bound, not weight-bandwidth-bound, so halving the bits buys
nothing in time. The end-to-end step times above agree. Peak drops by exactly as much as
resident does, because the difference between them is the VAE decode's scratch, which is
unquantized in both.

**What a 16 GB Mac gets.** The 4-bit variant, and it reaches 1024² there. The bar is peak
against what the GPU may keep resident (12.1 GB on a 16 GB Mac; see the memory budget
below) — peak is what a Mac has to find, and it is resident plus the VAE decode's transient
— so 512² at 10.7 GB fits outright, 768² at 14.6 GB and 1024² at 17.8 GB untiled fit once
the decode is tiled, which Automatic does for them. The 8-bit model's
17.7 GB tiled peak is still over the bar on such a machine, so its row says "Needs 23 GB"; it
stays selectable, because a smaller size still runs. A 24 GB Mac is offered both, the 8-bit one
with its decode tiled; a 32 GB Mac runs both untiled and exact.

**Quality.** At a fixed seed the 4-bit image is not a slightly degraded 8-bit image — it is a
different image, because the perturbed weights send the 9-step trajectory somewhere else. Mean
absolute difference is 26.4 of 255 at 1024², yet both are sharp and both follow the prompt.
Group size 32 was built and compared: it costs 825 MB more resident and 1.1 GB more on disk,
is no closer to the 8-bit output (29.9 of 255, further away than group 64), and is not visibly
better, so 64 is the default. Output is reproducible — two runs of the same variant at seed 42
are identical to the byte.

### Upscaling

Real-ESRGAN's compact network (`realesr-general-x4v3`, 1.2M parameters, 2.4 MB
of float16 weights bundled with the app) runs in 512-pixel tiles through the
same tiler the VAE decode uses. A 1024² input measured 2466 MB peak and 3.75 s
at 4× on an M4 Max; 2× is the 4× pass averaged down and costs the same peak. It
needs no model loaded, so it runs on any Mac the app does.

### Where the time goes

Where a 1024² step goes: the denoiser is compute-bound. A step is 4,160 tokens (4,096 image
patches plus a 64-token caption) through 32 transformer layers and two refiner layers. Counting
four attention projections of [4160,3840]×[3840,3840] and three feed-forward projections per
layer — w1 and w3 are [3840,10240], w2 is [10240,3840] — plus attention itself, that is
**59 TFLOP per step**, of which 50 TFLOP is quantized matmul. Timing those same shapes on their
own (`make bench ARGS="--micro --size 1024"`) and summing 32 × (4 projections + 3 feed-forward +
1 attention + 2 rope) gives **4.4 s**, or 4.7 s with the refiners: an effective **12.6 TFLOPS**
of 8-bit matmul. Against the 6.3 s step in the table the kernels are about three quarters of it,
and the rest is most likely weight residency — the microbench reuses one weight matrix where a
real step streams 7 GB of distinct ones. CPU-side graph building is not a factor: under
`ZEPHRA_PROFILE_STEP=1` a whole step is built in 2–9 ms against seconds of evaluation.

An earlier note here put the kernel sum at 1.2 s against the same 6.3 s step and could not
explain the 5× gap. The microbench was applying the VAE's divisor twice and so ran at 1,088
tokens rather than 4,160; at the true length the projections cost about 3.8× and attention about
14× more, which is where the gap went.

**To do: rerun the Z-Image benchmarks on an idle machine.** Every Z-Image number
in this section was taken on a machine running other builds (load average 10 to
70), where a re-measured 1024² step came out at 10 s rather than 6.3 s and
individual microbench rows varied by 2× between two runs an hour apart. The
table is the last set taken under lighter load; treat it as provisional. The
steps: pick a quiet hour, run `make bench ARGS="--size 1024 --steps 9 --runs 3"`
and `make bench ARGS="--micro --size 1024"` from a Release build, and replace the
table, the kernel sum, and the catalog comments with what they say. Text encoding
is ~40 ms and the VAE decode ~4 s at 1024².

Two experiments, both measured at a fixed seed. **Step caching does not work here**: reusing the
transformer's residual on steps whose input barely moved, TeaCache-style, needs consecutive steps
to be close, and over Z-Image-Turbo's 9 steps they are 12 % to 41 % apart. A threshold low enough
to be safe skips nothing; one that skips a single step of nine already redraws the robot's head
and hands (mean absolute difference 11.7 of 255), and one that skips three gives a different
picture entirely (26.9 of 255). The patch was removed rather than left switched off. **Tiled VAE
decode does work**, and is shipped for every model: decoding in overlapping 512-pixel tiles
takes peak memory at 1024² from 23.5 GB to 17.7 GB on the 8-bit Z-Image model, for a mean
absolute difference of 1.0 of 255 and no visible seam, and from 30.4 GB to 26.1 GB on
Qwen-Image for 0.19 of 255. Settings > Performance controls it, and Automatic — the default —
turns it on only for a model whose untiled peak is over what this Mac's GPU may keep resident.
So a 32 GB Mac decodes both Z-Image variants exactly and tiles for Qwen-Image, a 24 GB Mac
tiles for the 8-bit Z-Image model and not for the 4-bit one, and a 16 GB Mac tiles for both
and thereby reaches 1024² on the 4-bit one. Always and Never override the judgement, and
`ZEPHRA_VAE_TILE=64` still sets the tile for `ZephraBench`, which has no settings to read.

**Streamed weights** are the lever after tiling. A Mac whose GPU cannot hold Qwen-Image's
21.5 GB of weights runs it anyway by reading the transformer from the disk on every step, a
few of its sixty blocks at a time, and the text encoder's layers the same way once per
picture; the embeddings, the projections and the autoencoder stay resident. Measured on an
M4 Max at 1024², four steps, the peak falls from 30.5 GB resident to 10.2 GB streamed, 1.4 GB
stays live between pictures, each step reads 16.1 GB, and the image is byte for byte the
resident one. On a 16 GB M4 mini, the Mac this is for, a 1024² picture takes 123 s (29.7 s a
step, peak 7.9 GB, swap untouched) and a 512² one 28 s (7.1 s a step), the latter read-bound
at 2.3 GB/s from the SSD. The price is that read: it hides under a base GPU's own step time at
1024² and does not at 512².
The picker says "Streams from disk" where it applies; Settings > Performance has the three-way
control, Automatic streaming only a model that would otherwise page; and
`make bench ARGS="--model qwen-image-2512-4bit --stream"` reports the bytes read per step and
the disk's rate, which is what tells a read-bound step from a slow GPU.

**The memory every verdict is measured against** is what the GPU may keep resident — Metal's
recommended working set, about three quarters of RAM by default (12.1 GB on a 16 GB Mac) — not
a fraction of RAM. `sudo sysctl -w iogpu.wired_limit_mb=N` raises it, and Zephra follows:
the picker's wording, the tiled decode, the fallback model and MLX's own memory and wired
limits all read the raised figure at the next launch. Settings > Performance shows what the
GPU may keep and, when raising it would let the chosen model run, the exact command with a
Copy button. It needs an administrator password, lasts until the next restart, and leaves
macOS less to work with; `/etc/sysctl.conf` makes it permanent.

## Project layout

```
Zephra/
├── AGENTS.md (CLAUDE.md symlinks to it)  README.md  ROADMAP.md  LICENSE
├── THIRD_PARTY_NOTICES.md  PROVENANCE.md  Makefile  project.yml
├── Packages/
│   ├── ZImageKit/                 # vendored (MIT). LICENSE, VENDORED.md, Sources/ZImage/**
│   ├── QwenImageKit/              # ours, clean-room — the Qwen-Image pipeline. See PROVENANCE.md
│   ├── Flux2Kit/                  # ours, translated from MIT ports — FLUX.2 klein. See PROVENANCE.md
│   ├── ZephraKit/                 # ours — no MLX dependency
│   │   ├── Sources/ZephraCore/          # value types + protocols
│   │   ├── Sources/ZephraEngine/        # actor + store, depends on ZephraCore and ZephraSnapshot
│   │   │   ├── Library/                 # the image folder as an index: scan, query, annotate
│   │   │   ├── Timeline/                # the canvas sidebar: queue cards, then today's pictures as one wall
│   │   │   ├── Upscale/                 # the record an upscale carries and where it is filed
│   │   │   └── Downloads/               # what the app keeps alive per model request
│   │   ├── Sources/ZephraSnapshot/      # the model downloader, snapshot checks, what is on disk
│   │   └── Tests/ZephraCoreTests, ZephraEngineTests, ZephraSnapshotTests
│   ├── ZephraMLXKit/              # ours — MLX work no family owns
│   │   ├── Sources/ZephraQuantization/  # the streaming weight packer every family drives
│   │   └── Sources/ZephraMLX/           # the tiled decode, the allocator's knobs, the preview
│   │       └── Streaming/               # pooling, and the streamed layer stack
│   ├── ZephraBackendZImage/       # ours — the only package that imports ZImage
│   ├── ZephraBackendQwenImage/    # ours — the only package that imports QwenImage
│   ├── ZephraBackendFlux2/        # ours — the only package that imports Flux2; builds on first load
│   └── ZephraUpscaleRealESRGAN/   # ours — the upscaler, weights bundled. See its PROVENANCE.md
├── Sources/Zephra/                # app target: SwiftUI only, composition root is ZephraApp.swift
│   ├── ZephraApp.swift  Resources/{Info.plist, Assets.xcassets}
│   ├── Style/                     # the chrome every view draws itself from
│   ├── Workspace/                 # which pane, which query, whether the inspector is up
│   ├── Support/                   # caches, exports, previews, settings
│   └── Views/                     # the prompt capsule, its controls, Settings, and the commands;
│                                  # Canvas/ Library/ Library/Inspector/ Sidebar/ Sidebar/Timeline/ Toolbar/
├── Sources/ZephraBench/           # headless benchmark tool
├── Sources/ZephraQuantize/        # builds a 4-bit variant from a bf16 release
├── design/mock/                   # the UI the app was built against
├── Tests/ZephraTests/             # the app target's own suites (make test-app)
└── scripts/doctor.sh, screenshot.sh, window-id.swift, ax-press.swift, make-icon.swift,
            compare-safetensors.py, download-fixture.py, sign-release.sh, create-dmg.sh,
            notarize-release.sh, submit-notarization.sh, test-notarization.sh, verify-dmg.sh
```

## Development

- `make doctor` — check that Xcode.app, `xcodegen`, and the Metal toolchain are in
  place, and print the fix for whichever is not.
- `make gen` / `make build` / `make run` — regenerate `Zephra.xcodeproj` from
  `project.yml` (the project is generated and gitignored; never edit it), build the
  `Zephra` scheme (`CONFIG=Release` by default), and open the result.
- `make test` — `ZephraCore`, `ZephraSnapshot` and `ZephraEngine` under `swift test`.
  No MLX, a couple of seconds. One suite:
  `cd Packages/ZephraKit && swift test --filter ModelSwap` (the filter is a regex
  over type names).
- `make test-app` — the app target's own suites (`Tests/ZephraTests`: export
  planning, display strings, layout arithmetic), hosted in the Debug app through
  `xcodebuild`. The first run builds the app and takes minutes.
- `make test-mlx` — every package that links MLX: the packer, the backends' mapping
  tests, and `QwenImageKit`'s and `Flux2Kit`'s parity suites against tensors dumped
  from `diffusers`.
  They go through `xcodebuild` rather than `swift test` and take longer; nothing in
  them loads model weights, though the tensors they run do go through Metal.
  `make test-backend` is an alias.
- `make icon` — re-render `AppIcon.appiconset` from `scripts/make-icon.swift`.
- `make prefetch` / `make prefetch-flux2` — download a release ahead of a first
  launch, with `hf`, into `$(MODELS_DIR)/Downloads/<org>--<repo>`, which is what
  the app itself would have written; set `MODELS_DIR` if Settings names another
  folder. `make prefetch-qwen` goes to `QWEN_MODELS` instead, because 58 GB does
  not belong on a boot volume and that release is a build source rather than
  something the app loads.
- `make quantize` / `make quantize-qwen` / `make quantize-flux2` — the builds the app
  does on first load, by hand. `BITS` and `GROUP_SIZE` override the 4-bit, group-64
  default; `QUANT_OUT`, `QWEN_OUT` and `FLUX2_OUT` override where it lands, and
  `QWEN_SOURCE` / `QWEN_LORA` / `FLUX2_SOURCE` say what it is built from. `ARGS` passes
  anything else to the tool, such as `--text-encoder-bits 8` to hold the text encoder at
  a different precision from the transformer. Worth using for benchmarking, or to build
  from a source kept off the boot volume. The tool refuses an output that is the source
  or inside it, builds into a sibling `.partial` that is renamed into place only when it
  finishes (^C stops it and removes the partial), and requires `--lora` for Qwen-Image,
  whose four-step distillation is the adapter: `--no-lora` with an `--out` other than
  the catalog's directory builds the undistilled model on purpose. A build named for a
  catalog entry is stamped with the provenance the app checks, so it is loaded as the
  app's own.
- `make lint-layers` — check the module boundaries above. Run it before every commit.
- `make bench ARGS="..."` — headless timing (`--size`, `--steps`, `--runs`, `--model`,
  `--prompt`, `--json`, `--out`, `--micro` for the DiT's kernels alone, `--reference`
  to time the editing path, `--strength`, `--preview` to turn the live frames on and
  time them, `--stream` and `--stream-depth N` to measure the weights read from disk,
  `--backend` and `--snapshot` to time a snapshot the catalog does not list). Benchmark
  on an idle machine, Release only.
- `make logs` streams the app's log; `make screenshot` captures the window
  (`WINDOW=General` captures a Settings tab by its title instead), and
  `swift scripts/ax-press.swift "<title>"` presses a control in the running app
  through accessibility without activating it; `make open` opens the generated
  project in Xcode; `make clean` removes build output.
- `ZEPHRA_PREVIEW_STATE=ready|image|editing|tucked|generating|starting|queued|watching|batch|library|viewer|picker|downloading|building|failed|settings`
  launches a Debug build frozen in that state with no model, for screenshots; `tucked` is
  `image` with the floating prompt slid down to its lip, `viewer` is the library with a
  picture open full size, `picker` is `editing` with the reference picker sheet open,
  `generating`, `queued` and `watching` show a run in flight with a frame from it
  (`watching` is the one where the canvas has been left on an earlier picture), `starting`
  is the same run before its first frame, `downloading` and `failed` sit over a picture,
  since that is where they must stay legible, and `settings` freezes the engine but keeps
  the real library, for trying the folder-change flow with throwaway fixtures.

### Releasing

`make signed-build` regenerates the project, builds Release, and signs the app and
the resource bundles inside it with a Developer ID Application certificate (hardened
runtime, secure timestamp), verifies with `codesign --verify --deep --strict` and
`spctl -a -t exec -vv`. `make release` also packages `build/Zephra.zip` and a signed
`build/Zephra.dmg`. The read-only DMG contains `Zephra.app` and an Applications
shortcut: open the disk image and drag the app into Applications. Distribution
signing uses Apple's secure timestamp server; notarization is a separate step.
Ordinary `make build` is unaffected and still signs ad-hoc, so a machine with no
certificate can build and run the app.

`SIGN_IDENTITY` picks the certificate; left empty, the first "Developer ID
Application" identity in the keychain is used. Both signing and notarization source
`~/Documents/Zephra Signing/signing.env` when it exists; override its location with
`SIGNING_CONFIG=/path/to/signing.env`.

Notarization is a separate step from signing and packaging. A
team App Store Connect API key is the same credential locally and in CI:

```sh
NOTARY_KEY="$HOME/Documents/Zephra Signing/AuthKey_XXXXXXXXXX.p8"
NOTARY_KEY_ID=XXXXXXXXXX
NOTARY_ISSUER_ID=00000000-0000-0000-0000-000000000000
```

Then:

```sh
make notarized-release
```

The final installer is **`build/Zephra.dmg`**; `build/Zephra.zip` remains available
as an alternative. `make notarize` first submits the ZIP and requires Apple's
Accepted verdict, staples and verifies the app, and rebuilds both packages from
that stapled app. It then submits the signed DMG separately, staples its ticket,
and validates the image, signature, and Gatekeeper assessment. It mounts the final
DMG read-only to verify the contained app and Applications shortcut, then detaches
it. Both the disk image
and the app inside it carry tickets for offline use. As a fallback it uses the
keychain profile selected by `NOTARY_PROFILE` when the three API-key variables are
unset. `make -j notarized-release` still waits for packaging to finish before
notarization starts. `scripts/test-notarization.sh` checks accepted and rejected
verdict handling without credentials or network access.

`.github/workflows/notarized-release.yml` provides the same flow on an Apple Silicon
GitHub-hosted runner. It has only a manual trigger and uploads the notarized DMG and
ZIP as a workflow artifact; it never publishes a GitHub release. The repository needs these
Actions secrets: `DEVELOPER_ID_APPLICATION_P12_BASE64`,
`DEVELOPER_ID_APPLICATION_P12_PASSWORD`, `APPLE_API_KEY_P8_BASE64`,
`APPLE_API_KEY_ID`, and `APPLE_API_ISSUER_ID`.

## Roadmap

`ROADMAP.md` holds what comes next, in order, and what each finished feature
deliberately left out: several reference pictures at once, Qwen-Image-Edit,
Z-Image base, runtime LoRA, and the upscaler's follow-ups.

## License

Proprietary — all rights reserved. See `LICENSE`. Third-party components are
used under their own licenses; see `THIRD_PARTY_NOTICES.md`.
