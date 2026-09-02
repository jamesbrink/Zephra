# Zephra

Zephra is a native macOS app that generates images locally with the
Z-Image-Turbo diffusion model on Apple Silicon, via MLX/Metal.

## Priorities

In order:

1. **Very clean code.** Small files, one type per file, compiler-enforced
   module boundaries, no god objects.
2. **Extensible for more models later.** An explicit backend/model seam
   (protocol + descriptor catalog). Z-Image-Turbo is the first
   implementation; the UI never touches ZImage types.
3. **Performance on Apple Silicon**, then a nice, fully native SwiftUI UI.

## Layering rules — non-negotiable

```
Sources/Zephra (SwiftUI app) ─→ ZephraEngine ─→ ZephraCore
                             ─→ ZephraBackend<Family> ─→ ZephraCore, <Family>Kit
                                                          [imported in ZephraApp.swift ONLY]
Sources/ZephraBench (tool)   ─→ ZephraCore, every ZephraBackend<Family>
Sources/ZephraQuantize (tool)─→ ZephraCore, ZephraQuantization, every ZephraBackend<Family>

Shared, by what a file actually touches:
  ZephraKit/ZephraSnapshot     Foundation only  — hub cache, local snapshot checks
  ZephraKit/ZephraTestSupport  Foundation only  — Scratch, the filesystem test fixture
  ZephraMLXKit/ZephraQuantization  MLX          — the streaming weight packer
```

- `ZephraCore` (in `Packages/ZephraKit`): Sendable value types + protocols.
  Zero dependencies — no model package, no MLX, no SwiftUI.
- `ZephraSnapshot` (in `Packages/ZephraKit`): finding a cached Hugging Face
  snapshot and checking a local model directory. Foundation only, which is
  the point: `make test` covers it, so these suites need no Metal.
- `ZephraQuantization` (in `Packages/ZephraMLXKit`): the streaming weight
  packer, shared by every family. It knows nothing about any model — a family
  hands it a `QuantizationPlan` saying which directories hold weights, which
  tensors to leave alone, and how finely to squeeze the rest.
- `ZephraEngine` (in `Packages/ZephraKit`): concurrency + state. Depends on
  `ZephraCore` only. Backends arrive as an injected `BackendRegistry` of
  `@Sendable` factories; this layer never names a concrete backend.
- `ZephraBackendZImage` (its own local package, `Packages/ZephraBackendZImage`):
  translates `ZephraCore` types to and from `ZImage` types. No state, no UI.
  Depends on `ZephraKit`'s `ZephraCore` product and `ZImageKit`'s `ZImage`
  product. This split keeps `Packages/ZephraKit` free of MLX dependencies, so
  `make test` (`swift test` there) stays fast and doesn't touch Metal.
- `Packages/ZImageKit`: vendored. Edit only with a `// ZEPHRA-PATCH: <reason>`
  comment and a matching entry in `VENDORED.md`.
- Nothing in the app target may import a model package or `MLX`. Only
  `Sources/Zephra/ZephraApp.swift` (the composition root) may import a
  `ZephraBackend*` package, to register the backend. Everywhere else in the
  app target goes through `ZephraEngine` and `ZephraCore`.
- No backend package may import another backend package, or a build for one
  family drags in every other family's pipeline.

Code rules:

- One public type per file; file name matches the type name.
- Target ≤150 lines per file.
- No `*Manager`, `*Helper`, `*Utils`, or `*Service` type names — name types
  for what they are.
- Views hold at most 3 stored properties, or get split into subviews.
- `ModelCatalog` is the only static registry in the codebase. No other
  singletons.
- Vendored code in `ZImageKit` is edited only under `// ZEPHRA-PATCH:`
  discipline (see `Packages/ZImageKit/VENDORED.md`).

Run `make lint-layers` before every commit. It greps for forbidden imports
across the layers above and fails the build if any are found.

## How a generation runs

Three types in `ZephraEngine`, one concern each. The split is what lets the
engine be tested in seconds without Metal.

- `GenerationStore` (`@MainActor @Observable`) is the only object the UI
  observes, and it is split across `GenerationStore+*.swift` by concern —
  loading, generation, the queue, model switching, history, availability,
  preview. Add a new concern as another extension file, not as more lines in
  `GenerationStore.swift`.
- `InferenceActor` is the only place backend code runs. It overrides
  `unownedExecutor` with a serial `DispatchQueue`: a generation is tens of
  seconds of synchronous Metal work, and on the cooperative pool that would
  starve every other task in the process. Backends are not `Sendable`, which is
  why a registry of `@Sendable` factories goes in and the backend is built here.
- `EngineEventPump` carries progress from that queue back to the main actor. Its
  `AsyncStream` buffers the newest four events and drops the rest — progress is
  a snapshot, not a log — and `run` drains before returning, so the state a
  caller sets after an operation is never clobbered by an event still in flight.

## Adding a model or a backend

This is the seam priority 2 exists for. Both cases are additive: no view, and
nothing in `ZephraEngine`, changes.

**A model an existing backend can already run** — one entry in
`Packages/ZephraKit/Sources/ZephraCore/Model/ModelCatalog.swift`, listed in
`all`. `ModelDescriptor` carries where the weights come from (`ModelSource`:
a Hugging Face repo or a local directory), the download and resident sizes,
and a `ModelCapabilities` the interface draws itself from — size presets and
bounds, step and guidance bounds, whether a negative prompt or a seed does
anything. Every number in an entry is hand-written because every number is
measured; leave a comment saying where a figure came from. `ModelMenu` lists
`ModelCatalog.all` and `GenerationStore.switchModel(to:)` does the rest.

**A new backend family** — four things:

1. A `BackendID` case in `.../ZephraCore/Model/BackendID.swift`.
2. A package under `Packages/`, alongside `ZephraBackendZImage`, whose one
   public type conforms to `ImageGenerationBackend` and whose one public
   entry point is a `BackendFactory` (see `ZImageBackendFactory`). It may
   import whatever it needs; nothing above it may.
3. Catalog entries naming that `BackendID`.
4. One line in `Sources/Zephra/ZephraApp.swift`:
   `registry.register(.yourFamily, YourBackendFactory.make)`. That file is the
   only place in the app target allowed to name a concrete backend.

`InferenceActor` keeps one backend at a time and rebuilds it whenever a
descriptor names a different family, so the old weights are always released
before the new ones are asked for. A descriptor whose family was never
registered surfaces as `EngineError.noBackend`, not as a crash.

`ImageGenerationBackend.availability(of:)` must answer from the disk alone —
never download, never disturb what is loaded. It is what lets the picker say
"13.3 GB download" without starting one.

## Build & run

The Xcode project (`Zephra.xcodeproj`) is generated by `xcodegen` from
`project.yml` and is gitignored. Never edit the generated project — edit
`project.yml` and regenerate.

mlx-swift's Metal kernels require `xcodebuild`; plain `swift build` cannot
build the app target or `ZephraBackendZImage`. `swift build` / `swift test`
only work for `Packages/ZephraKit` (`ZephraCore` + `ZephraEngine`), which has
no MLX dependency by design.

Makefile targets:

- `make gen` — regenerate `Zephra.xcodeproj` from `project.yml`.
- `make build` — generate, then `xcodebuild` the `Zephra` scheme
  (`CONFIG=Release` by default).
- `make run` — build, then open `build/Release/Zephra.app`.
- `make open` — generate, then open the project in Xcode.
- `make bench` — build and run `ZephraBench` (`ARGS=...` to pass flags).
- `make test` — `swift test` in `Packages/ZephraKit` (Core, Snapshot, and
  Engine, fast, no MLX). Anything testable without Metal belongs here.
- `make test-mlx` — `xcodebuild test` over every package that links MLX
  (`MLX_PACKAGES` in the Makefile). Slower, needs `xcodebuild`. `make
  test-backend` is kept as an alias. Keep `make test` MLX-free.
- `make icon` — re-render `AppIcon.appiconset` from `scripts/make-icon.swift`.
- `make release` — build Release, sign with a Developer ID Application identity
  (hardened runtime, secure timestamp), verify, and zip to `build/Zephra.zip`.
  Needs no network. `SIGN_IDENTITY` overrides the auto-detected certificate.
- `make notarize` — submit that zip, staple the ticket, and repackage. Needs
  `xcrun notarytool store-credentials zephra-notary` run once; `NOTARY_PROFILE`
  names the profile.
- `make prefetch` — download the default model weights via `hf download`.
- `make quantize` — download the bf16 release and build the 4-bit variant into
  `~/Library/Application Support/Zephra/Models/z-image-turbo-4bit`. `BITS`,
  `GROUP_SIZE`, and `QUANT_OUT` override the defaults (4 bits, group 64).
  `ZephraQuantize` takes a required `--family`; there is deliberately no
  default, because the wrong one silently produces the wrong artifact an hour
  later.
- `make lint-layers` — enforce the layering rules above.
- `make logs` — stream app logs (`log stream`, subsystem `io.zephra`).
- `make screenshot` — capture the app window (see debugging hooks).
- `make clean` — remove build output and the generated project.

The first Release build compiles MLX's Metal kernels from scratch and takes
several minutes. Always benchmark and make performance claims against
Release, never Debug — Debug has Metal validation and full debug info on.

## Tests

Swift Testing (`import Testing`, `@Suite`/`@Test`), never XCTest. Suites and
tests are named as sentences about behaviour ("the revision's refs file picks
the snapshot, not whichever is listed first"); match that when adding one.

- `make test` — `ZephraCoreTests` + `ZephraEngineTests`, seconds, no Metal.
- One suite or test:
  `cd Packages/ZephraKit && swift test --filter ModelSwap`. The filter is a
  regex over the *type* names, not the `@Suite` display names, so `ModelSwap`
  takes both swap suites and `--filter 'model swap'` matches nothing.
- The backend's suites need `xcodebuild`, and its filter is likewise the type
  name: `cd Packages/ZephraBackendZImage && xcodebuild test -scheme
  ZephraBackendZImage -destination 'platform=macOS'
  -skipPackagePluginValidation
  -only-testing:ZephraBackendZImageTests/QuantizableWeightTests`.

No test loads weights or touches the GPU. The engine tests drive `MockBackend`
through `MockBackendControl`, a lock-protected dial a `@Sendable` factory can
close over — it fails a load, delays one so cancellation lands mid-flight, and
tallies loads and unloads — while `EngineTestBed` gives each test a throwaway
output folder. `ZephraCoreTests` uses the smaller `StubBackend`.

## Model weights

Default model: `mzbac/Z-Image-Turbo-8bit` — 13.3 GB download (excluding
`assets/`), 12236 MB resident once loaded and peaking at 23501 MB during the VAE
decode at 1024 pixels, so 32 GB of RAM is the practical floor. Weights are cached in
`~/.cache/huggingface/hub`, honoring `HF_HOME` / `HF_HUB_CACHE` if set.
`make prefetch` seeds the cache ahead of first run.

Always pass the model explicitly when calling into the vendored pipeline —
its own default is the 33 GB bf16 repo, not the 8-bit one Zephra uses.

Second model: `z-image-turbo-4bit`, built on the user's own Mac by `make quantize`,
because no repository publishes four-bit Z-Image-Turbo in the manifest format the
vendored loader reads. It is a `.localDirectory` source under
`~/Library/Application Support/Zephra/Models`, so it downloads nothing and the
backend reports a clear error when it is missing rather than trying to fetch it.
6.7 GB on disk and 6575 MB resident, against 13.3 GB and 12236 MB for the 8-bit
model. Peak follows the image size — 10693 MB at 512 pixels, 14599 MB at 768,
17839 MB at 1024 — because peak is resident plus the unquantized VAE decode's
scratch. So a 16 GB Mac is offered this variant and can run it at 512 and 768, but
1024 will page. Four bits is not faster: MLX's quantized matmul costs the same at
these shapes whichever bit width it packs, which `make bench ARGS=--micro` shows
directly and the end-to-end step times agree with. Group size 64 rather than 32,
measured: 32 costs 825 MB more resident and 1.1 GB more on disk for no visible
quality gain.

Second family, in progress: **Qwen-Image-2512** (`Qwen/Qwen-Image-2512`, Apache 2.0)
— a 60-layer dual-stream MMDiT of about 20B parameters, conditioned on
Qwen2.5-VL-7B and decoded by a 3-D causal VAE. 57.7 GB in bf16, which is too
large for the boot volume here, so the full-precision source lives at
`/Volumes/ExternalStorage/Models/Qwen-Image-2512` and only its configuration
files stay in the Hugging Face cache. Point `--source` there when quantizing,
and `QWEN_IMAGE_SNAPSHOT` there for any test that wants real weights.

Text-to-image never runs Qwen2.5-VL's vision tower: the pipeline supplies token
ids and an attention mask and no pixels. So the ViT is not ported and its
weights are not loaded, along with `lm_head` — together 391 of the checkpoint's
729 text-encoder tensors. `WeightKeyCoverageTests` asserts that rather than
leaving it to be assumed.

The Z-Image quantization plan lives in `ZephraBackendZImage/Quantization`; the
packer it drives is shared, in `ZephraQuantization`. Three things about it are
load-bearing and easy to break:

- The set of packed tensors must match the reference eight-bit export exactly. The
  loader decides what is quantized by looking for a `.scales` key, so packing a
  tensor the reference left alone stops the module tree matching the weights.
  `QuantizableWeight` is that rule, and `QuantizableWeightTests` pins it.
- Manifest layer names are the bare module paths the loader looks them up by
  (`layers.0.attention.to_q`, `model.layers.0.mlp.down_proj`), not prefixed with the
  component the way `mzbac/Z-Image-Turbo-8bit` writes them. The reference names never
  match, so its per-layer `bits` and `group_size` are dead and everything falls back
  to the top level. Bare names make mixed precision — a four-bit transformer with an
  eight-bit text encoder — actually work.
- Scales and biases are written float32, as the reference does, because the source is
  cast to float32 before packing. The transformer's `castFloatParameters` patch turns
  them into bfloat16 at load.

Weights stream one tensor at a time out of the memory-mapped source shard and spill
once four gigabytes have accumulated, so a 24 GB float32 transformer converts at
about 8 GB resident. The whole build takes about a minute once the source is local.

## Vendored code

`Packages/ZImageKit` is a vendored copy of `mzbac/zimage.swift` at commit
`970f83e4`. See `Packages/ZImageKit/VENDORED.md` for the license situation,
the re-sync procedure, and the running patch log. Any change inside
`ZImageKit` needs a `// ZEPHRA-PATCH:` comment and a `VENDORED.md` entry.

## Conventions

- Conventional Commits for all git messages.
- Swift 6 strict concurrency in our code. The vendored `ZImageKit` package
  stays in Swift 5 language mode so its 49 files compile untouched.
- No emojis in code or docs.
- Keep files small; split before a file grows past its target size.
- Zephra may ship commercially. Every new dependency, vendored file, or model
  gets an entry in `THIRD_PARTY_NOTICES.md` (copyright line, license, and any
  NOTICE file) in the same commit. That file is bundled and shown in
  Settings > About; it is the disclosure, so keep it exact.

## Debugging hooks

- `ZEPHRA_PREVIEW_STATE=ready|image|generating|downloading|failed` launches a Debug build
  frozen in that state with no model, for screenshots (`make screenshot`).
- `make logs` streams `os.Logger` output for subsystem `io.zephra`.
- `make bench ARGS="--size 1024 --steps 9 --runs 3 --json"` measures load, s/step, and peak memory
  headlessly; benchmark on an idle machine, Release only.
- `make bench ARGS="--micro --size 1024"` times the DiT's individual MLX kernels at that size's
  token count without loading any weights, so a slow generation can be attributed to a primitive
  rather than guessed at.
- `ZEPHRA_PROFILE_STEP=1` prints per-phase timings (text encode, per-step graph build, per-step
  eval, VAE decode) and MLX's active and peak allocation to stderr.
- Precision and padding switches, for bisecting a suspected regression without a rebuild:
  `ZEPHRA_DIT_DTYPE=f32` runs the transformer in float32, `ZEPHRA_PAD_PROMPT=full` pads prompts to
  the 512-token limit, `ZEPHRA_KEEP_CACHE=1` stops handing MLX's scratch back after a generation,
  and `ZEPHRA_CACHE_LIMIT_MB=N` overrides the benchmark's MLX cache ceiling.
- `ZEPHRA_VAE_TILE=<latent tile edge>` decodes the VAE in overlapping tiles and blends the seams,
  so the decode's peak is set by the tile rather than by the image. 64 gives 512-pixel tiles and
  takes the 1024-pixel peak from 23.5 GB to 17.7 GB for a mean absolute pixel difference of 1 of
  255. It is the starting value of `VAETiledDecode.latentTile` and so is what `ZephraBench` and
  the command line use. The app overrides it as soon as its window appears: Settings >
  Performance holds a three-way preference (`AppSettings.vaeTiling`) and `VAETilingPolicy`
  applies it for the model about to run, tiling under Automatic when that model's `peakBytes`
  is over four fifths of physical memory.
- Xcode 26 needs the Metal toolchain once: `xcodebuild -downloadComponent MetalToolchain`.

## Environment notes

- `xcodegen` lives at `/opt/homebrew/bin/xcodegen`.
- In shell tooling, use `/bin/ls` rather than the interactive `ls` — the
  shell's `ls` function can hang on this volume.
