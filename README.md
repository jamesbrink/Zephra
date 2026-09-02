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
  the queue.
- Size, steps, and seed sit under the prompt. The lock keeps the seed across runs; unlocked,
  every run gets a fresh one. Images save to `~/Pictures/Zephra` with the seed in the file name.
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
Sources/ZephraQuantize (tool)─→ ZephraCore, ZephraBackendZImage
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
at 14.6 GB, both of which fit; 1024² peaks at 17.8 GB and will page.

**Quality.** At a fixed seed the 4-bit image is not a slightly degraded 8-bit image — it is a
different image, because the perturbed weights send the 9-step trajectory somewhere else. Mean
absolute difference is 26.4 of 255 at 1024², yet both are sharp and both follow the prompt.
Group size 32 was built and compared: it costs 825 MB more resident and 1.1 GB more on disk,
is no closer to the 8-bit output (29.9 of 255, further away than group 64), and is not visibly
better, so 64 is the default. Output is reproducible — two runs of the same variant at seed 42
are identical to the byte.

### Where the time goes

Where a 1024² step goes: the denoiser is compute-bound. MLX quantized matmuls reach about
12.5 TFLOPS on an M4 Max (`make bench ARGS=--micro`), and the 32 transformer layers sum to
roughly 5 s of matmul and attention per step at 4,160 tokens, so the measured 6.3 s is within
25 % of the kernel ceiling. The GPU is at 100 % for the whole step; paging and CPU-side graph
building were measured and ruled out. Anything else using the GPU slows Zephra proportionally.
Text encoding is ~40 ms and the VAE decode ~4 s at 1024².

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
