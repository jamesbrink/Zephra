# Zephra

A native macOS app that generates images locally with Z-Image-Turbo on Apple
Silicon, via MLX/Metal.

## Why

- **Local.** Everything runs on-device; nothing leaves the machine.
- **Fast.** MLX drives the GPU directly through Metal, tuned for Apple
  Silicon.
- **Private.** No accounts, no network calls at generation time, no telemetry.
- **Native.** A real SwiftUI app, not a wrapped web view.

## Requirements

- Apple Silicon Mac
- macOS 15 (Sequoia) or later
- Xcode 26 or later
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen)
- [`hf`](https://github.com/huggingface/huggingface_hub) CLI (optional, for
  `make prefetch`)
- About 14 GB free disk for the 8-bit weights, or 7 GB for the 4-bit ones. Building
  the 4-bit variant needs 33 GB more, for the full-precision release it is derived
  from; that download can be deleted afterwards.
- 32 GB RAM for the 8-bit model, which holds 12.2 GB resident and peaks at 23.5 GB
  while decoding a 1024² image. The 4-bit variant brings that to 6.6 GB resident and
  a 17.8 GB peak at 1024², or 10.7 GB at 512², so a 16 GB Mac can run it at the
  smaller sizes. The app hides models that need more than 60 % of physical memory.

## Quick start

```sh
make prefetch   # optional: download model weights ahead of time
make quantize   # optional: build the smaller 4-bit variant (see below)
make build
make run
```

If you skip `make prefetch`, the first run downloads the model (about 13 GB)
before it can generate anything — the window stays responsive with a progress
readout while that happens.

## Using it

- Type a prompt and press Generate (or ⌘↩). The window subtitle shows what the engine is doing.
- Press Generate again while an image is running to queue the next prompt; prompts run one
  after another and the subtitle counts what is waiting. Stop ends the current image and drops
  the queue; during the first-run download or the load it abandons that instead, and the canvas
  offers to pick it up again — a stopped download resumes from what it already fetched.
- The model menu in the toolbar names the model that is running and lists the rest, each with
  what choosing it would cost: "Downloaded", "13.3 GB download", "Not built yet" for a local
  variant that has not been quantized, or "Needs N GB" for one this Mac has too little memory
  for. Picking a model that has not been downloaded starts the download; the last two are
  disabled, with the reason in the tooltip. Switching releases the old weights before it asks
  for the new ones. Choosing a model while an image is running interrupts nothing: the running
  image finishes on its model, anything already queued keeps the model it was queued for, and
  the new choice applies to whatever you queue next, with the engine swapping weights between
  queue entries as it goes. Your choice is remembered.
- Size, steps, and seed sit under the prompt. A model that reads a negative prompt gets a
  second field for it, and one that responds to guidance gets a guidance slider; Z-Image Turbo
  does neither, so it shows neither. The lock keeps the seed across runs; unlocked,
  every run gets a fresh one. Images save to `~/Pictures/Zephra` with the seed in the file name;
  if a write fails, a notice sits over the prompt until an image saves, and the picture stays on
  the canvas either way.
- The filmstrip under the prompt keeps its images across launches: Zephra reads the newest
  two dozen back out of `~/Pictures/Zephra` at startup, in the background, so it is filled in
  before the model has finished loading. The record of what made an image — prompt, size,
  steps, seed, model, and how long it took — lives inside the PNG itself, so moving, renaming,
  or copying a file to another Mac keeps it, and clicking a restored image loads its settings
  ready to vary. A PNG that Zephra did not make carries no record and is ignored. Right-click a
  thumbnail for Save as, Copy, Reveal in Finder, and Delete; Delete (⌘⌫ for the image on the
  canvas) moves the file to the Trash, so it is recoverable from the Finder.
- Settings holds where images are written and the seed preference under General. Performance
  has the after-load warm-up, the ceiling on the GPU scratch the runtime keeps between
  generations — with the figure recommended for your Mac, and a reset back to it — and a live
  readout of active, cached and peak GPU memory. A changed ceiling applies immediately.
- Shortcuts: Generate ⌘↩, Stop ⌘., Save As ⌘S, Reveal in Finder ⌘⇧R, Copy Image ⌘⇧C,
  Delete Image ⌘⌫. Cut, Copy, Paste and Select All in the prompt field are the standard Edit
  menu items.

## How it works

Zephra keeps the UI layer completely ignorant of the model that's running it.
A backend protocol and a model descriptor catalog sit between the SwiftUI
views and the Z-Image implementation, so a second model can be added later as
another backend without touching the UI or the core engine.

```
Sources/Zephra (SwiftUI app) ─→ ZephraEngine ─→ ZephraCore
                             ─→ ZephraBackendZImage ─→ ZephraCore, ZImage   [imported in ZephraApp.swift ONLY]
Sources/ZephraBench (tool)   ─→ ZephraCore, ZephraBackendZImage
Sources/ZephraQuantize (tool)─→ ZephraCore, ZephraBackendZImage
```

`ZephraCore` and `ZephraEngine` have zero MLX dependencies, so they build and
test in seconds. `ZephraBackendZImage` is the only package that speaks to the
vendored Z-Image pipeline.

History needs no database: every image is saved with its `GenerationRecord` as
JSON in a `zephra:generation` PNG text chunk, spliced in ahead of the pixel data
so the bytes a seed produces never change, and the library folder is read back
at launch.

Adding a model that an existing backend can run is one entry in `ModelCatalog`:
the picker lists the catalog, and the interface draws itself from the entry's
`ModelCapabilities`. Adding a new backend is that entry plus a `BackendID` case,
a package implementing `ImageGenerationBackend`, and one `registry.register(...)`
line in `ZephraApp.swift` — no view and nothing in `ZephraEngine` changes.

## Performance

| Machine | Resolution | Steps | Time |
|---|---|---|---|
| Apple M4 Max 48 GB, GPU shared with other apps (~50 % busy at idle) | 1024×1024 | 9 | ~57 s (6.3 s/step) |
| Apple M4 Max 48 GB, same conditions | 512×512 | 4 | ~7 s (1.6 s/step) |
| Apple M2 Ultra (upstream report) | 1024×1024 | 9 | ~44 s |

### The 4-bit variant

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
| s/step at 1024² | 13.8 s | 14.0 s |
| on disk | 13.3 GB | 6.7 GB |

**Four bits buys memory, not speed.** MLX's quantized matmul takes the same 2.7 ms at
[T,3840]×[3840,3840] whether the weights are 8-bit or 4-bit (`make bench ARGS=--micro`): at
these shapes the kernel is compute-bound, not weight-bandwidth-bound, so halving the bits buys
nothing in time. The end-to-end step times above agree. Peak drops by exactly as much as
resident does, because the difference between them is the VAE decode's scratch, which is
unquantized in both.

**What a 16 GB Mac gets.** The 4-bit variant is the only one such a machine is offered, since
the 8-bit model's 12.2 GB resident exceeds the 60 %-of-RAM bar. 512² peaks at 10.7 GB and 768²
at 14.6 GB, both of which fit; 1024² peaks at 17.8 GB untiled and will page, and near 12 GB with
the tiled VAE decode described below.

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

Both figures above want redoing. Every number in this section was taken on a machine running
other builds (load average 10 to 70), where a re-measured 1024² step came out at 10 s rather than
6.3 s and individual microbench rows varied by 2× between two runs an hour apart. The table is
the last set taken under lighter load; treat it as provisional. Text encoding is ~40 ms and the
VAE decode ~4 s at 1024².

Two experiments, both measured at a fixed seed. **Step caching does not work here**: reusing the
transformer's residual on steps whose input barely moved, TeaCache-style, needs consecutive steps
to be close, and over Z-Image-Turbo's 9 steps they are 12 % to 41 % apart. A threshold low enough
to be safe skips nothing; one that skips a single step of nine already redraws the robot's head
and hands (mean absolute difference 11.7 of 255), and one that skips three gives a different
picture entirely (26.9 of 255). The patch was removed rather than left switched off. **Tiled VAE
decode does work**, and is kept behind `ZEPHRA_VAE_TILE=64`: decoding in overlapping 512-pixel
tiles takes peak memory at 1024² from 23.5 GB to 17.7 GB for a mean absolute difference of 1.0 of
255 and no visible seam. It is off by default because the untiled decode is exact and a 32 GB Mac
does not need it; it is what would let a 16 GB Mac reach 1024² on a 4-bit model.

## Project layout

```
Zephra/
├── .gitignore  AGENTS.md (CLAUDE.md symlinks to it)  LICENSE  THIRD_PARTY_NOTICES.md  Makefile  README.md  project.yml
├── Packages/
│   ├── ZImageKit/                 # vendored (MIT). LICENSE, VENDORED.md, Package.swift, Sources/ZImage/**
│   ├── ZephraKit/                 # ours — no MLX dependency
│   │   ├── Sources/ZephraCore/          # value types + protocols
│   │   ├── Sources/ZephraEngine/        # actor + store, depends on ZephraCore only
│   │   └── Tests/ZephraCoreTests, ZephraEngineTests
│   └── ZephraBackendZImage/       # ours — the only package that imports ZImage
│       └── Sources/, Tests/ZephraBackendZImageTests
├── Sources/Zephra/                # app target: SwiftUI only, composition root is ZephraApp.swift
│   └── ZephraApp.swift  Views/**  Support/**  Resources/{Info.plist, Assets.xcassets, Colors}
├── Sources/ZephraBench/main.swift # headless benchmark tool
├── Sources/ZephraQuantize/         # builds the 4-bit variant from the bf16 release
└── scripts/screenshot.sh, make-icon.swift,
            sign-release.sh, notarize-release.sh
```

## Development

- `make test` — `ZephraCore` and `ZephraEngine` under `swift test`. No MLX, a couple
  of seconds.
- `make test-backend` — the `ZephraBackendZImage` mapping tests. They link MLX, so
  they go through `xcodebuild` rather than `swift test` and take longer; nothing in
  them loads weights or touches the GPU.
- `make icon` — re-render `AppIcon.appiconset` from `scripts/make-icon.swift`.
- `make quantize` — build the 4-bit variant. `BITS` and `GROUP_SIZE` override the
  4-bit, group-64 default; `QUANT_OUT` overrides where it lands.
- `make lint-layers` — check the module boundaries above.

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
- LoRA support
- Image-to-image

## License

Proprietary — all rights reserved. See `LICENSE`. Third-party components are
used under their own licenses; see `THIRD_PARTY_NOTICES.md`.
