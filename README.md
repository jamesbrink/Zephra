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
- About 14 GB free disk for model weights
- 32 GB RAM. The 8-bit model holds about 13 GB resident and peaks near 24 GB while
  decoding; the app hides models that need more than 60 % of physical memory.

## Quick start

```sh
make prefetch   # optional: download model weights ahead of time
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
- Size, steps, and seed sit under the prompt. The lock keeps the seed across runs; unlocked,
  every run gets a fresh one. Images save to `~/Pictures/Zephra` with the seed in the file name;
  if a write fails, a notice sits over the prompt until an image saves, and the picture stays on
  the canvas either way.
- Settings holds where images are written and the seed preference under General. Performance
  has the after-load warm-up, the ceiling on the GPU scratch the runtime keeps between
  generations — with the figure recommended for your Mac, and a reset back to it — and a live
  readout of active, cached and peak GPU memory. A changed ceiling applies immediately.
- Shortcuts: Generate ⌘↩, Stop ⌘., Save As ⌘S, Reveal in Finder ⌘⇧R, Copy Image ⌘⇧C. Cut,
  Copy, Paste and Select All in the prompt field are the standard Edit menu items.

## How it works

Zephra keeps the UI layer completely ignorant of the model that's running it.
A backend protocol and a model descriptor catalog sit between the SwiftUI
views and the Z-Image implementation, so a second model can be added later as
another backend without touching the UI or the core engine.

```
Sources/Zephra (SwiftUI app) ─→ ZephraEngine ─→ ZephraCore
                             ─→ ZephraBackendZImage ─→ ZephraCore, ZImage   [imported in ZephraApp.swift ONLY]
Sources/ZephraBench (tool)   ─→ ZephraCore, ZephraBackendZImage
```

`ZephraCore` and `ZephraEngine` have zero MLX dependencies, so they build and
test in seconds. `ZephraBackendZImage` is the only package that speaks to the
vendored Z-Image pipeline.

## Performance

| Machine | Resolution | Steps | Time |
|---|---|---|---|
| Apple M4 Max 48 GB, GPU shared with other apps (~50 % busy at idle) | 1024×1024 | 9 | ~57 s (6.3 s/step) |
| Apple M4 Max 48 GB, same conditions | 512×512 | 4 | ~7 s (1.6 s/step) |
| Apple M2 Ultra (upstream report) | 1024×1024 | 9 | ~44 s |

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
└── scripts/screenshot.sh, prefetch-model.sh, make-icon.swift,
            sign-release.sh, notarize-release.sh
```

## Development

- `make test` — `ZephraCore` and `ZephraEngine` under `swift test`. No MLX, a couple
  of seconds.
- `make test-backend` — the `ZephraBackendZImage` mapping tests. They link MLX, so
  they go through `xcodebuild` rather than `swift test` and take longer; nothing in
  them loads weights or touches the GPU.
- `make icon` — re-render `AppIcon.appiconset` from `scripts/make-icon.swift`.
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

- 4-bit quantized weights
- More models, added as new backends behind the existing protocol
- LoRA support
- Image-to-image

## License

Proprietary — all rights reserved. See `LICENSE`. Third-party components are
used under their own licenses; see `THIRD_PARTY_NOTICES.md`.
