# Zephra

A native macOS app for local image generation on Apple Silicon, powered by
MLX and Metal. Generate and edit with **Z-Image-Turbo**, **Qwen-Image-2512**,
and **FLUX.2 klein 4B**, then upscale with **Real-ESRGAN**.

- **Local and private:** inference stays on your Mac, with no image uploads,
  accounts, or telemetry. Model downloads require an internet connection.
- **Native:** SwiftUI interface with a canvas, live previews, a generation queue,
  and a searchable image library.
- **Portable images:** prompts, seeds, favorites, tags, and album membership
  travel with the PNG.

## Requirements

- Apple Silicon Mac running **macOS 15 (Sequoia) or later**.
- Enough memory and disk space for your chosen [model](#models-and-memory).
- To build: **Xcode 26 or later**, including the Metal toolchain, and
  **XcodeGen 2.45 or later**. The standalone Command Line Tools are insufficient.
- Optional: the Hugging Face `hf` CLI for command-line downloads and the
  quantization targets that fetch their own source weights.

## Quick start

Install Xcode.app and XcodeGen (`brew install xcodegen` or
`nix profile install nixpkgs#xcodegen`), then complete the one-time Xcode setup:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain
make doctor
```

From the repository root:

```sh
make run
```

This generates the Xcode project, builds Release, and opens the app. The first
build compiles MLX's Metal kernels and can take several minutes with little output.
Use `make build` to build without launching, or `make open` to work in Xcode.

On a fresh launch, Zephra chooses the first catalog model that fits the GPU's
memory budget. Selecting a model downloads any missing weights and, for most
variants, builds a quantized copy before loading. The window shows progress
throughout; later loads reuse the files.

Optional downloads ahead of launch:

```sh
make prefetch-flux2  # FLUX.2 klein source, shared by its 4-bit and 8-bit variants
make prefetch       # Z-Image-Turbo 8-bit, ready to load
```

These targets need `hf` and use the default models folder. Set `MODELS_DIR` if
you chose another folder in Settings.

## Models and memory

Sizes below are approximate decimal GB from the current catalog. Peak figures
are recorded measurements at **1024×1024**, not total system memory requirements
or guarantees for every Mac. Reference-image editing can use more memory.

| Model | Download | Built copy | Resident weights | Peak / tiled peak |
| --- | ---: | ---: | ---: | ---: |
| FLUX.2 klein 4B, 4-bit | 16 GB | 5.4 GB | 4.9 GB | 12.1 / 7.7 GB |
| FLUX.2 klein 4B, 8-bit | Same source | 8.6 GB | 8.1 GB | 15.3 / 10.9 GB |
| Z-Image-Turbo, 8-bit | 13.3 GB | — | 12.2 GB | 23.5 / 17.7 GB |
| Z-Image-Turbo, 4-bit | 32.9 GB | 6.7 GB | 6.6 GB | 17.8 / 12.0 GB |
| Qwen-Image-2512, 4-bit | 59.4 GB | 21.6 GB | 21.5 GB | 30.4 / 26.1 GB |

The source download is retained alongside the built copy, so allow space for
both. Qwen-Image's download includes its four-step Lightning adapter, merged
during the build. Only Z-Image-Turbo 8-bit loads its download directly.

**Settings > Performance** controls tiled VAE decoding and weight residency.
Automatic tiling reduces decode memory when the model exceeds the GPU's budget.
Qwen-Image also supports streaming weights from disk, enabling generation on
16 GB Macs at the cost of disk reads each step. The picker reports these tradeoffs;
models remain selectable even when a smaller image size may be needed.

Historical timings at 1024×1024 include about 29 seconds for FLUX.2 klein
(four steps, M4 Max) and 123 seconds for streamed Qwen-Image (four steps, 16 GB
M4 mini). These are reference measurements, not current performance claims:
some recorded results predate dtype corrections, and Z-Image timings were taken
on a busy machine. Re-measure on an idle Mac with the [benchmark tool](#development).
Catalog source comments retain the measurement context.

### Downloads and storage

Models default to `~/Library/Application Support/Zephra/Models`.
**Settings > Models** lists download requests and stored files separately.

- Up to two repositories download at once. Compatible variants share a transfer;
  switching models leaves earlier downloads running. One model's weights are
  loaded at a time.
- **Pause** keeps partial files for Resume. **Cancel Download** discards unfinished
  files after their final consumer releases them; completed repositories remain.
- Downloads needed by queued generations cannot be paused from their row.
  Remove the queued work first, or use Stop on the canvas.
- Failed transfers remain resumable. Quit preserves partials and waits for work
  to settle; selecting the model after relaunch resumes its download. Background
  requests do not restart automatically.
- **Change…** offers **Move Models** or **Keep in Place**. Keeping files in place
  leaves the old folder available as a read-only fallback; new downloads and
  builds use the selected folder. Deletion requires confirmation and is blocked
  while storage is in use.

The app downloads public Hugging Face repositories without sending an
`Authorization` header. Existing Hugging Face cache snapshots are a read-only
fallback; the app does not require `hf`.

## Using Zephra

### Generate and edit

Type a prompt on **Canvas** and press **Generate**. Choose a batch of 1, 2, 4, or
8 seeds; pressing Generate again queues more work. The sidebar shows queued runs,
progress, and today's results. Stop cancels the current work and clears the queue.
Looking at another picture leaves the canvas there while the new result saves.

Choose a model in the toolbar and set the size, steps, and seed below the prompt.
A model change during generation applies to newly queued work; existing jobs keep
their model. Lock the seed to reuse it across runs.

Drop a reference picture onto the canvas or reference well, pick one from the
library, or use the current image as a reference:

- **FLUX.2 klein** conditions on reference tokens and runs its full schedule,
  with no strength slider.
- **Z-Image and Qwen-Image** start from a noised reference. Lower strength preserves
  more of the picture and runs fewer steps.

All current models support a reference image. None exposes a negative prompt or
guidance slider. **Upscale 2× / 4×** uses bundled Real-ESRGAN weights without
loading a generation model and saves a new image with its parent's provenance.

### Organize and export

**Library** shows day-grouped images with search, favorites, tags, albums, and
model filters. Select an image to inspect its prompt and generation settings,
open it on Canvas, queue a variation, or upscale it. Drag images onto an album
to file them; annotation and album edits support Undo and Redo.

Images save automatically to `~/Pictures/Zephra`. Generation metadata and library
annotations live in separate PNG text chunks, so renaming or copying a file keeps
both. The library indexes Zephra images from the folder without a database.

Export copies the saved file with its metadata and offers Keep Both, Replace,
or Cancel for name collisions. Copy supports the Finder and image-aware apps;
Share uses macOS sharing services. Delete moves images to **Recently Deleted**
for 30 days. **Put Back** restores them; **Delete Immediately** moves them to
the Finder's Trash.

Change the library under **Settings > General > Images**. **Move Images** migrates
images, sources, albums, and Recently Deleted; **Keep in Place** leaves the old
library untouched and displays the selected folder. Finish generation, queued
work, and upscaling first. Migration verifies copies, preserves metadata, and
refuses collisions; merging existing libraries is not supported.

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Generate / Stop | ⌘Return / ⌘. |
| Canvas / Library | ⌘1 / ⌘2 |
| Find | ⌘F |
| Show inspector / Hide prompt | ⌥⌘I / ⌥⌘P |
| New album | ⌘N |
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Export / Copy image | ⇧⌘E / ⇧⌘C |
| Reveal in Finder | ⇧⌘R |
| Use / Clear reference | ⌥⌘R / ⇧⌥⌘R |
| Upscale 2× / 4× | ⌥⌘U / ⇧⌥⌘U |
| Delete image | ⌘Delete |

The library grid also supports range selection, arrow-key navigation, ⌘A, ⌘C,
and Space for Quick Look. Image commands act on the focused grid selection or
visible canvas picture. Return in the prompt inserts a newline.

## Architecture

| Module | Responsibility |
| --- | --- |
| `ZephraCore` | Dependency-free value types, model descriptors, and protocols |
| `ZephraSnapshot` | Foundation-only downloads, snapshot validation, and disk inventory |
| `ZephraEngine` | Generation state, inference scheduling, downloads, queue, and library |
| `ZephraBackend<Family>` | Adapts one model kit to the shared backend protocol |
| `ZephraMLXKit` | Shared MLX loading, quantization, streaming, and decoding |
| `ZephraUpscaleRealESRGAN` | Independent image upscaler |
| `Sources/Zephra` | SwiftUI app; concrete backends are registered in `ZephraApp.swift` |

Core, Snapshot, and Engine have no MLX dependency. The UI uses shared protocols
and capabilities; only the composition root imports concrete backends and the
upscaler. Backends never import one another.

`ZImageKit` is vendored; QwenImageKit and Flux2Kit are maintained here with their
origins documented in [PROVENANCE.md](PROVENANCE.md). See
[AGENTS.md](AGENTS.md) for module boundaries, lifecycle details, and how to add
models. [ROADMAP.md](ROADMAP.md) tracks planned work and deferred decisions.

## Development

The Xcode project is generated from [project.yml](project.yml); edit that file
rather than `Zephra.xcodeproj`. Use Conventional Commits and run
`make lint-layers` before every commit.

| Command | Purpose |
| --- | --- |
| `make doctor` | Check Xcode, XcodeGen, and the Metal toolchain |
| `make build` / `make run` | Build / build and launch (`CONFIG=Release` by default) |
| `make test` | Core, Snapshot, and Engine tests without Metal |
| `make test-app` | App tests hosted in the Debug app |
| `make test-mlx` | MLX package and backend tests through Xcode |
| `make lint-layers` | Enforce import boundaries and animation rules |
| `make vendored-diff` | Check vendored changes for `ZEPHRA-PATCH` markers |
| `make logs` / `make screenshot` | Stream logs / capture the app window |
| `make open` / `make clean` | Open the generated Xcode project / remove build output |

Benchmark on an idle machine in Release:

```sh
make bench ARGS="--size 1024 --steps 9 --runs 3 --json"
make bench ARGS="--model qwen-image-2512-4bit --stream"
make bench ARGS="--model flux2-klein-4b-4bit --preview"
```

`make quantize`, `make quantize-qwen`, and `make quantize-flux2` expose the builds
the app performs on first load. The [Makefile](Makefile) documents source and
output overrides. For Qwen, set `QWEN_MODELS` (or `QWEN_SOURCE` and `QWEN_LORA`)
explicitly: its default is a project-specific external volume.
`make mirror` builds all four packed variants into one directory laid out for a
bucket, with an `index.json` of sizes and checksums; `make mirror-sync
MIRROR_BUCKET=s3://...` pushes it.

See [Debugging hooks](AGENTS.md#debugging-hooks) for preview states, benchmark
options, and launch-time `ZEPHRA_*` overrides.

### Signing and releases

Ordinary builds are ad-hoc signed and need no distribution certificate.
`make signed-build` builds Release and signs with a Developer ID Application
certificate; `make release` also packages a DMG and ZIP. To build, package,
notarize, and staple in order:

```sh
make notarized-release VERSION=0.2.0 BUILD_NUMBER=42
```

The outputs are `build/Zephra.dmg` and `build/Zephra.zip`. Both contain the
notarized app; the DMG also has its own stapled ticket and an Applications
shortcut. The app uses the hardened runtime and is not sandboxed.

Signing and notarization read `~/Documents/Zephra Signing/signing.env` when
present, or the file named by `SIGNING_CONFIG`. `SIGN_IDENTITY` selects the
certificate. Notarization accepts `NOTARY_KEY`, `NOTARY_KEY_ID`, and
`NOTARY_ISSUER_ID`, with `NOTARY_PROFILE` as the keychain-profile fallback.
Keep credentials outside the repository. See [Build & run](AGENTS.md#build--run)
for the full setup.

The manual [Notarized Release workflow](.github/workflows/notarized-release.yml)
runs prerequisite, layer, and test checks before signing. It takes a version
input, uses the workflow run number as the build number, and uploads DMG and ZIP
artifacts. It does not run on pushes or publish a GitHub release.

## License

Proprietary; all rights reserved. See [LICENSE](LICENSE). Third-party components
are covered by their own licenses in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
