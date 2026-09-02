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
- Settings holds where images are written and the seed preference under General, and the
  after-load warm-up under Performance.
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
