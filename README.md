# Zephra

A native macOS app that generates images locally on Apple Silicon, via
MLX/Metal. It runs Z-Image-Turbo, Qwen-Image-2512, and FLUX.2 klein 4B.

## Why

- **Local.** Everything runs on-device; nothing leaves the machine.
- **Fast.** MLX drives the GPU directly through Metal, tuned for Apple
  Silicon.
- **Private.** No accounts, no network calls at generation time, no telemetry.
- **Native.** A real SwiftUI app, not a wrapped web view.

## Requirements

- Apple Silicon Mac
- macOS 15 (Sequoia) or later
- **Xcode 26 or later, the full Xcode.app.** The Command Line Tools are not
  enough: mlx-swift's Metal kernels are compiled by `xcodebuild`, which they do
  not ship. `xcode-select -p` must print a path inside `Xcode.app`, not
  `/Library/Developer/CommandLineTools`.
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`,
  or `nix profile install nixpkgs#xcodegen`.
- [`hf`](https://github.com/huggingface/huggingface_hub) CLI (optional, for
  `make prefetch` and `make prefetch-flux2`): `pip install -U huggingface_hub`.
- About 14 GB free disk for the 8-bit Z-Image weights, or 7 GB for the 4-bit ones.
  Building the 4-bit variant needs 33 GB more, for the full-precision release it is
  derived from; that download can be deleted afterwards. Qwen-Image is 22 GB built,
  from a 58 GB source. FLUX.2 klein is a 16 GB download plus the packed variant beside
  it, 5.4 GB for 4-bit or 8.6 GB for 8-bit, both kept: each variant packs from the
  same download, and the hub cache is `hf`'s to prune (`hf cache delete`), not Zephra's.
- 16 GB RAM for FLUX.2 klein 4B, the small, fast model: 4.9 GB resident and a 12.1 GB
  peak at 1024², which fits a 16 GB Mac without tiling; its 8-bit variant holds 8.1 GB
  and peaks at 15.3 GB, or 10.9 GB tiled. 32 GB for the 8-bit Z-Image model, which holds 12.2 GB resident and
  peaks at 23.5 GB while decoding a 1024² image. The 4-bit variant brings that to 6.6 GB
  resident and a 17.8 GB peak at 1024², or 10.7 GB at 512². Peak, not resident, is
  what decides whether a Mac pages, and the tiled VAE decode below takes about 6 GB
  off it, so a 24 GB Mac runs both Z-Image variants at 1024² and a 16 GB Mac runs
  the 4-bit one there. Qwen-Image is the large one: 21.5 GB resident and a 30.4 GB
  peak at 1024², so a 36 GB Mac decodes it exactly and a 32 GB one needs the tiled decode.

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
make prefetch        # optional: download Z-Image weights ahead of time
make quantize        # optional: build the smaller 4-bit Z-Image variant (see below)
make prefetch-qwen   # optional: download Qwen-Image-2512 and its 4-step adapter
make quantize-qwen   # optional: build the 4-bit Qwen-Image variant
make build
make run
```

If you skip `make prefetch`, the first run downloads the model (about 13 GB)
before it can generate anything — the window stays responsive with a progress
readout while that happens.

## Using it

- The window is a sidebar and one of two panes, and the sidebar changes with the pane. On
  Canvas (⌘1) it is the session: the search field (⌘F) over today's runs — what is waiting,
  what is being rendered, and the images as they come out. On Library (⌘2) it is the search
  field, chips for everything and favourites, and the collections to look in — every image,
  favourites, the last seven days, one row per model with a count, the tags in use, albums,
  and Recently deleted pinned at the foot. Canvas is the picture with the prompt floating over
  it; Library is everything made so far, in day-grouped grids with a filter bar over them and
  an inspector beside them (⌥⌘I). Typing in the search while the canvas is up takes you to the
  Library showing the hits, and clearing the field puts you back where you were.
- The Library's filter bar says what is being shown and how much of it is selected, carries a
  removable token per filter, and has a slider for the thumbnail size (⌘+ and ⌘− step it).
  Click to select, shift-click for a range, ⌘-click to add one, ⌘A for all of them, arrow keys
  to walk the grid, space for Quick Look. The inspector shows the image, its prompt, and the
  Model, Size, Steps, Seed, Took and File rows read out of the PNG, with its tags and albums,
  and offers Open in canvas, Queue a variation, and Reveal in Finder. Select several and it
  says what they have in common and acts on all of them.
- Type a prompt and press Generate (or ⌘↩). The window subtitle shows what the engine is doing.
- The control beside Generate says how many seeds one press queues — 1, 2, 4, or 8 of the same
  prompt, the first of them on the seed in the field, so a run of four is a superset of the one
  image the same press would have made.
- Press Generate again while an image is running to queue the next prompt; prompts run one
  after another and the subtitle counts what is still waiting. The sidebar's timeline shows
  the same work as one list: the run being rendered as an amber card with its steps filling in,
  the runs still waiting above it, each with a cross that takes the whole run back out, and
  under every run a square per seed — dashed until the image lands, then the picture, which a
  press puts back on the canvas. Stop ends the current image and drops
  the queue; during the first-run download or the load it abandons that instead, and the canvas
  offers to pick it up again — a stopped download resumes from what it already fetched.
- The model menu in the toolbar names the model that is running and lists the rest, each with
  what choosing it would cost: "Downloaded", "13.3 GB download", "16 GB download, then built"
  for FLUX.2 klein on a Mac that has never fetched it, "Builds on first load" once the
  release is cached, "Not built yet" for a local variant that has not been quantized, "Tiles
  the decode" for one this Mac reaches only with the tiled VAE decode, or "Needs N GB" for
  one whose peak is over this Mac's budget even tiled. Picking a model that has not been
  downloaded starts the download; klein then packs the release into the variant this Mac
  runs, once, showing "Building" while it does. Memory never
  disables a row — a model that would page at 1024² still runs at 768², and the tooltip says
  so; only "Not built yet" is out of reach. Switching releases the old weights before it asks
  for the new ones. Choosing a model while an image is running interrupts nothing: the running
  image finishes on its model, anything already queued keeps the model it was queued for, and
  the new choice applies to whatever you queue next, with the engine swapping weights between
  queue entries as it goes. Your choice is remembered.
- Size, steps, and seed sit under the prompt. A model that reads a negative prompt gets a
  second field for it, and one that responds to guidance gets a guidance slider; no model
  shipped today does either, so neither shows. Every model can start from a picture, so each
  gets a well beside the prompt: drop a picture on it or on the canvas, click it to choose one,
  or use the image on the canvas as the reference (⌥⌘R; ⇧⌥⌘R clears it). What a picture means
  differs by model. FLUX.2 klein attends to it as extra tokens and still renders the whole
  schedule, so the picture guides the image without a strength to set. Z-Image and Qwen-Image
  start from a noised copy of it instead, so a strength decides how much of it survives: a
  strength buys that share of the model's steps, and less strength keeps more of the picture. The
  prompt then says what to change. An edited image carries its reference inside its PNG, so
  selecting it later puts the picture back, and an exported edit can reproduce itself. Steps and size stay as you set them when
  you switch between variants of one model, and steps go back to the new model's own default
  when you switch to a different model — nine steps of Z-Image's schedule and nine of
  Qwen-Image's four-step distillation are not the same request. The lock keeps the seed across
  runs; unlocked,
  every run gets a fresh one. Images save to `~/Pictures/Zephra` with the seed in the file name;
  if a write fails, a notice sits over the prompt until an image saves, and the picture stays on
  the canvas either way.
- The strip under the prompt is the run in progress: the seeds one press of Generate queued,
  with a dashed square for each one still to come (⌥⌘T hides it). Everything ever made is in
  `~/Pictures/Zephra`, and the Library reads that folder rather than the app keeping a list of
  its own. The record of what made an image — prompt, size, steps, seed, model, and how long it
  took — lives inside the PNG itself, so moving, renaming, or copying a file to another Mac
  keeps it, and opening an image again shows what it was made from, ready to vary. Favourites,
  tags and album membership go into the same file, under a second keyword, so they travel with
  the picture too. A PNG that Zephra did not make carries no record and is ignored. Right-click a
  thumbnail for Save as, Copy, Reveal in Finder, and Delete; Delete (⌘⌫ for the image on the
  canvas) moves the file to `~/Pictures/Zephra/Recently Deleted`, where it waits thirty days
  before it is thrown away for good, so it can be put back.
- Settings holds where images are written and the seed preference under General. Performance
  has the after-load warm-up, the ceiling on the GPU scratch the runtime keeps between
  generations — with the figure recommended for your Mac, and a reset back to it — whether the
  VAE decode is tiled (Automatic, Always, Never), and a live readout of active, cached and peak
  GPU memory plus which way the decode is currently set. Both changes apply immediately. About
  shows the version and the third-party license notices.
- Shortcuts: Generate ⌘↩, Stop ⌘., Canvas ⌘1, Library ⌘2, Find ⌘F, Show
  Inspector ⌥⌘I, Select All Images ⌘A, Favourite ⌘⇧D, thumbnail size ⌘+ and ⌘−, Save As ⌘S,
  Reveal in Finder ⌘⇧R, Copy Image ⌘⇧C, Use as Reference ⌥⌘R, Clear Reference ⇧⌥⌘R, Delete
  Image ⌘⌫. Return in the prompt field breaks the line, which is why Generate is ⌘↩; Cut,
  Copy, Paste and Select All there are the standard Edit menu items.

## How it works

Zephra keeps the UI layer completely ignorant of the model that's running it.
A backend protocol and a model descriptor catalog sit between the SwiftUI views
and each model's implementation. Adding Qwen-Image exercised that: it reached
the interface as one catalog entry and one registration line, and no view or engine
file had to learn the model's name. Adding FLUX.2 klein added two things every family
may now use: a build step between download and load, for a model whose release is
not what gets loaded, and a reference picture on the request, for a model that edits.

```
Sources/Zephra (SwiftUI app) ─→ ZephraEngine ─→ ZephraCore
                             ─→ ZephraBackend<Family> ─→ ZephraCore, <Family>Kit
                                                        [imported in ZephraApp.swift ONLY]
Sources/ZephraBench (tool)   ─→ ZephraCore, every ZephraBackend<Family>
Sources/ZephraQuantize (tool)─→ ZephraCore, ZephraQuantization, every ZephraBackend<Family>
```

`ZephraCore` and `ZephraEngine` have zero MLX dependencies, so they build and
test in seconds. A backend package is the only thing that speaks to its
family's pipeline, and no backend package may import another — a build for one
family must not drag in every other family's weights-loading code.

History needs no database: every image is saved with its `GenerationRecord` as
JSON in a `zephra:generation` PNG text chunk, spliced in ahead of the pixel data
so the bytes a seed produces never change, and the library folder is read back
at launch.

Adding a model that an existing backend can run is one entry in `ModelCatalog`:
the picker lists the catalog, and the interface draws itself from the entry's
`ModelCapabilities`. Adding a new backend is that entry plus a `BackendID` case,
a package implementing `ImageGenerationBackend`, and one `registry.register(...)`
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
same way — the transformer conditions on the hidden state after the 27th layer, so
nothing past it is loaded — and copying the 168 MB autoencoder whole. `make
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

The port in `Packages/Flux2Kit` is Zephra's own, translated from two MIT-licensed
Swift ports and pinned against `diffusers` — see `PROVENANCE.md` for the four places
it departs from those ports on purpose. The transformer runs in bfloat16;
`ZEPHRA_DIT_DTYPE=f32` runs it in float32, which is the workaround should mlx-swift's
bfloat16 split-K bug on M5-class GPUs reach it, at about three times the step time.

| Machine | Resolution | Steps | Time |
|---|---|---|---|
| Apple M4 Max 48 GB, GPU shared with other apps (~50 % busy at idle) | 1024×1024 | 9 | ~57 s (6.3 s/step) |
| Apple M4 Max 48 GB, same conditions | 512×512 | 4 | ~7 s (1.6 s/step) |
| Apple M2 Ultra (upstream report) | 1024×1024 | 9 | ~44 s |

Qwen-Image-2512, 4-bit and distilled to four steps, on the same M4 Max:

| Resolution | Steps | Time | Resident | Peak | Peak tiled |
|---|---|---|---|---|---|
| 512×512 | 4 | 6.9 s (1.6 s/step) | 21.5 GB | 26.1 GB | — |
| 1024×1024 | 4 | 33.6 s (8.2 s/step) | 21.5 GB | 30.4 GB | 26.1 GB |
| 1328×1328 (native) | 4 | 66.7 s (16.3 s/step) | 21.5 GB | 32.5 GB | 26.1 GB |

Twenty billion parameters against Z-Image Turbo's six, yet a step costs only
about a third more — 8.2 s against 6.3 s at 1024 — and four steps against nine
make the image quicker overall, with text rendering in a different class. Resident does not move with resolution because the weights are
all of it. The tiled peak barely moves either: the tile, not the image, sets the
decode's transient, and what is left is the transformer.

### Qwen-Image-2512

`make quantize-qwen` builds the four-bit copy, because nothing publishes one in a
form Zephra can load. It reads the 57.7 GB bfloat16 release, merges the Apache-2.0
[four-step Lightning adapter](https://huggingface.co/lightx2v/Qwen-Image-2512-Lightning)
into the transformer as it packs, holds the modulation layers at eight bits while
everything else goes to four, and takes about a minute. The result is 21.6 GB.

The adapter is not optional. The base model wants fifty steps and real
classifier-free guidance — two passes through twenty billion parameters per step —
which is not a thing to do on a Mac. Merging the distillation at build time rather
than loading it at run time means the runtime never sees an adapter: what lands in
the models directory is simply the four-step model.

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

`make quantize` builds a four-bit copy of the weights on the machine itself, because no
repository publishes Z-Image-Turbo in four bits in the format the loader reads. It downloads
the 33 GB bfloat16 release once, packs the transformer's 270 and the text encoder's 252 linear
weights at four bits with a group size of 64, leaves the VAE alone, and takes about a minute
after the download. The result is 6.7 GB on disk against 13.3 GB for the 8-bit model.

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
against four fifths of physical memory — peak is what a Mac has to find, and it is resident
plus the VAE decode's transient — so 512² at 10.7 GB and 768² at 14.6 GB fit outright, and
1024², 17.8 GB untiled, fits at about 12 GB once the decode is tiled. The 8-bit model's
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

**To do: rerun the Z-Image benchmarks on an idle machine.** Every number in this section was taken on a machine running
other builds (load average 10 to 70), where a re-measured 1024² step came out at 10 s rather than
6.3 s and individual microbench rows varied by 2× between two runs an hour apart. The table is
the last set taken under lighter load; treat it as provisional. The steps: pick a quiet hour, run `make bench ARGS="--size 1024 --steps 9 --runs 3"` and `make bench ARGS="--micro --size 1024"` from a Release build, and replace the table, the kernel sum, and the catalog comments with what they say. Text encoding is ~40 ms and the
VAE decode ~4 s at 1024².

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
turns it on only for a model whose untiled peak is over four fifths of this Mac's memory. So a
32 GB Mac decodes both Z-Image variants exactly and tiles for Qwen-Image, a 24 GB Mac tiles for
the 8-bit Z-Image model and not for the 4-bit one, and a 16 GB Mac tiles for both and thereby
reaches 1024² on the 4-bit one. Always and Never override the judgement, and
`ZEPHRA_VAE_TILE=64` still sets the tile for `ZephraBench`, which has no settings to read.

## Project layout

```
Zephra/
├── .gitignore  AGENTS.md (CLAUDE.md symlinks to it)  LICENSE  THIRD_PARTY_NOTICES.md
├── PROVENANCE.md  Makefile  README.md  project.yml
├── Packages/
│   ├── ZImageKit/                 # vendored (MIT). LICENSE, VENDORED.md, Package.swift, Sources/ZImage/**
│   ├── QwenImageKit/              # ours, clean-room — the Qwen-Image pipeline. See PROVENANCE.md
│   ├── Flux2Kit/                  # ours, translated from MIT ports — FLUX.2 klein. See PROVENANCE.md
│   ├── ZephraKit/                 # ours — no MLX dependency
│   │   ├── Sources/ZephraCore/          # value types + protocols
│   │   ├── Sources/ZephraEngine/        # actor + store, depends on ZephraCore only
│   │   │   └── Library/                 # the image folder as an index: scan, query, annotate
│   │   ├── Sources/ZephraSnapshot/      # hub cache and local snapshot checks, Foundation only
│   │   └── Tests/ZephraCoreTests, ZephraEngineTests, ZephraSnapshotTests
│   ├── ZephraMLXKit/              # ours — MLX work no family owns: the packer, the tiled decode
│   ├── ZephraBackendZImage/       # ours — the only package that imports ZImage
│   ├── ZephraBackendQwenImage/    # ours — the only package that imports QwenImage
│   └── ZephraBackendFlux2/        # ours — the only package that imports Flux2; builds on first load
├── Sources/Zephra/                # app target: SwiftUI only, composition root is ZephraApp.swift
│   ├── ZephraApp.swift  Resources/{Info.plist, Assets.xcassets}
│   ├── Style/                     # the chrome every view draws itself from
│   ├── Workspace/                 # which pane, which query, whether the inspector is up
│   ├── Support/                   # caches, exports, previews, settings
│   └── Views/                     # Canvas/ Library/ Sidebar/ Sidebar/Timeline/ Toolbar/
├── Sources/ZephraBench/           # headless benchmark tool
├── Sources/ZephraQuantize/        # builds a 4-bit variant from a bf16 release
├── design/mock/                   # the UI the app was built against
└── scripts/doctor.sh, screenshot.sh, window-id.swift, make-icon.swift,
            compare-safetensors.py, sign-release.sh, notarize-release.sh
```

## Development

- `make doctor` — check that Xcode.app, `xcodegen`, and the Metal toolchain are in
  place, and print the fix for whichever is not.
- `make test` — `ZephraCore`, `ZephraSnapshot` and `ZephraEngine` under `swift test`.
  No MLX, a couple of seconds.
- `make test-mlx` — every package that links MLX: the packer, the backends' mapping
  tests, and `QwenImageKit`'s and `Flux2Kit`'s parity suites against tensors dumped
  from `diffusers`.
  They go through `xcodebuild` rather than `swift test` and take longer; nothing in
  them loads model weights, though the tensors they run do go through Metal.
  `make test-backend` is an alias.
- `make icon` — re-render `AppIcon.appiconset` from `scripts/make-icon.swift`.
- `make quantize` / `make quantize-qwen` / `make quantize-flux2` — build a 4-bit
  variant. `BITS` and `GROUP_SIZE` override the 4-bit, group-64 default; `QUANT_OUT`,
  `QWEN_OUT` and `FLUX2_OUT` override where it lands, and `QWEN_SOURCE` / `QWEN_LORA`
  / `FLUX2_SOURCE` say what it is built from. `make prefetch-flux2` seeds the hub
  cache with the klein release ahead of a first launch.
- `make lint-layers` — check the module boundaries above.
- `make bench ARGS="..."` — headless timing (`--size`, `--steps`, `--runs`, `--model`, `--json`,
  `--out`, `--micro`, `--reference` to time the editing path, `--strength`); `make logs` streams the app's log; `make screenshot` captures the window;
  `make open` opens the generated project in Xcode; `make clean` removes build output.
- `ZEPHRA_PREVIEW_STATE=ready|image|editing|generating|queued|batch|library|downloading|building|failed`
  launches a Debug build frozen in that state with no model, for screenshots.

### Releasing

`make release` regenerates the project, builds Release, signs the app and the
resource bundles inside it with a Developer ID Application certificate (hardened
runtime, secure timestamp), verifies with `codesign --verify --deep --strict` and
`spctl -a -t exec -vv`, and packages `build/Zephra.zip` with `ditto`. It needs no
network. Ordinary `make build` is unaffected and still signs ad-hoc, so a machine
with no certificate can build and run the app.

`SIGN_IDENTITY` picks the certificate; left empty, the first "Developer ID
Application" identity in the keychain is used.

Notarization is a separate step, because it is the only one that talks to Apple.
Store the credentials once — the password is an app-specific password from
[appleid.apple.com](https://appleid.apple.com), not the Apple account password:

```sh
xcrun notarytool store-credentials zephra-notary \
    --apple-id you@example.com \
    --team-id ABCDE12345 \
    --password abcd-efgh-ijkl-mnop
```

Then:

```sh
make release
make notarize
```

`make notarize` submits the zip, waits for the verdict, staples the ticket to the
app, rebuilds the zip from the stapled bundle so it passes Gatekeeper offline, and
re-checks with `spctl`. `NOTARY_PROFILE=...` selects a differently named profile.

## Roadmap

- More models, added as new backends behind the existing protocol
- Runtime LoRA (adapters are merged at build time today)
- Editing on more than one reference picture at once

## License

Proprietary — all rights reserved. See `LICENSE`. Third-party components are
used under their own licenses; see `THIRD_PARTY_NOTICES.md`.
