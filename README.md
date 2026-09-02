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
- 16 GB RAM recommended

## Quick start

```sh
make prefetch   # optional: download model weights ahead of time
make build
make run
```

If you skip `make prefetch`, the first run downloads the model (about 13 GB)
before it can generate anything — the window stays responsive with a progress
readout while that happens.

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
| Apple M4 Max 48 GB | 1024×1024 | 9 | TBD |
| Apple M2 Ultra (upstream report) | 1024×1024 | 9 | ~44 s |

## Project layout

```
Zephra/
├── .gitignore  CLAUDE.md  LICENSE  THIRD_PARTY_NOTICES.md  Makefile  README.md  project.yml
├── Packages/
│   ├── ZImageKit/                 # vendored (MIT). LICENSE, VENDORED.md, Package.swift, Sources/ZImage/**
│   ├── ZephraKit/                 # ours — no MLX dependency
│   │   ├── Sources/ZephraCore/          # value types + protocols
│   │   ├── Sources/ZephraEngine/        # actor + store, depends on ZephraCore only
│   │   └── Tests/ZephraCoreTests, ZephraEngineTests
│   └── ZephraBackendZImage/       # ours — the only package that imports ZImage
├── Sources/Zephra/                # app target: SwiftUI only, composition root is ZephraApp.swift
│   └── ZephraApp.swift  Views/**  Support/**  Resources/{Info.plist, Assets.xcassets, Colors}
├── Sources/ZephraBench/main.swift # headless benchmark tool
└── scripts/screenshot.sh, prefetch-model.sh
```

## Roadmap

- 4-bit quantized weights
- More models, added as new backends behind the existing protocol
- LoRA support
- Image-to-image

## License

Proprietary — all rights reserved. See `LICENSE`. Third-party components are
used under their own licenses; see `THIRD_PARTY_NOTICES.md`.
