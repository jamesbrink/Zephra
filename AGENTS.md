# Zephra

Zephra is a native macOS app that generates images locally on Apple Silicon,
via MLX/Metal. It runs three model families today, Z-Image-Turbo,
Qwen-Image-2512, and FLUX.2 klein 4B, behind one backend seam.

## Priorities

In order:

1. **Very clean code.** Small files, one type per file, compiler-enforced
   module boundaries, no god objects.
2. **Extensible for more models later.** An explicit backend/model seam
   (protocol + descriptor catalog). Z-Image-Turbo, Qwen-Image, and FLUX.2
   klein are the implementations; the UI never touches any family's types.
3. **Performance on Apple Silicon**, then a nice, fully native SwiftUI UI.

## Layering rules — non-negotiable

```
Sources/Zephra (SwiftUI app) ─→ ZephraEngine ─→ ZephraCore
                             ─→ ZephraBackend<Family> ─→ ZephraCore, ZephraSnapshot,
                                                          ZephraQuantization, <Family>Kit
                                                          [imported in ZephraApp.swift ONLY]
Sources/ZephraBench (tool)   ─→ ZephraCore, every ZephraBackend<Family>
Sources/ZephraQuantize (tool)─→ ZephraCore, ZephraQuantization, every ZephraBackend<Family>

Shared, by what a file actually touches:
  ZephraKit/ZephraSnapshot     Foundation only  — hub cache, local snapshot checks
  ZephraKit/ZephraTestSupport  Foundation only  — Scratch, the filesystem test fixture
  ZephraMLXKit/ZephraQuantization  MLX          — the streaming weight packer
  ZephraMLXKit/ZephraMLX           MLX, ZephraCore — the tiled decode and the allocator's
                                                  knobs; <Family>Kit may take it
```

- `ZephraCore` (in `Packages/ZephraKit`): Sendable value types + protocols.
  Zero dependencies — no model package, no MLX, no SwiftUI.
- `ZephraSnapshot` (in `Packages/ZephraKit`): finding a cached Hugging Face
  snapshot and checking a local model directory. Foundation only, which is
  the point: `make test` covers it, so these suites need no Metal.
- `ZephraQuantization` (in `Packages/ZephraMLXKit`): the streaming weight
  packer, shared by every family. It knows nothing about any model — a family
  hands it a `QuantizationPlan` saying which directories hold weights, which
  tensors to leave alone, how finely to squeeze the rest, and which low-rank
  adapters to merge on the way past.
- `ZephraMLX` (in `Packages/ZephraMLXKit`): MLX work that is the same job for
  every family. Two things are there. `TiledDecode`: an autoencoder's decode
  allocates in proportion to the image, so decoding overlapping latent tiles
  bounds the peak by the tile. `MLXRuntime`: the process-wide allocator's
  limits and readings, which each family's `InferenceRuntime` forwards to,
  adding only its own VAE tile. A model package may depend on this; nothing in
  it may depend on a model package. The vendored `ZImageKit` keeps its own
  copy as a `ZEPHRA-PATCH`, because pointing vendored code at ours would
  complicate every re-sync.
- `ZephraEngine` (in `Packages/ZephraKit`): concurrency + state. Depends on
  `ZephraCore` only. Backends arrive as an injected `BackendRegistry` of
  `@Sendable` factories; this layer never names a concrete backend.
- `ZephraBackendZImage`, `ZephraBackendQwenImage`, and `ZephraBackendFlux2`
  (their own local packages): translate `ZephraCore` types to and from one
  family's types. No state, no UI. Each depends on `ZephraKit`'s `ZephraCore`
  and `ZephraSnapshot` products, on `ZephraQuantization` for its packing plan,
  and on its own family's kit. `ZephraBackendFlux2` is also the one that packs
  its download into the variant it loads, on first load, through the
  protocol's `build` step. This split keeps `Packages/ZephraKit` free of MLX
  dependencies, so `make test` (`swift test` there) stays fast and doesn't
  touch Metal.
- `Packages/ZImageKit`: vendored. Edit only with a `// ZEPHRA-PATCH: <reason>`
  comment and a matching entry in `VENDORED.md`.
- `Packages/QwenImageKit`: ours, clean-room. Written from Qwen-Image-2512's own
  config files and from `diffusers`, never from the GPL-3.0
  `mzbac/qwen.image.swift`. `PROVENANCE.md` records why and how; keep it true.
- `Packages/Flux2Kit`: ours, a translation with attribution from two MIT Swift
  ports (`xocialize/flux2-klein-swift`, `VincentGourbin/flux-2-swift-mlx`) and
  `diffusers`, pinned against `diffusers` and departing from the ports where
  the reference says so. Never from GPL code, and never from
  `xocialize/flux2-vae-mlx-swift`, which has no license. `PROVENANCE.md` lists
  the deliberate departures; keep it true.
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

This is the seam priority 2 exists for. Both cases are additive: no view and
nothing in `ZephraEngine` has to learn the model's name. (Adding Qwen-Image did
touch both, once each, for behaviour that turned out to be family-generic: a
cross-family switch takes the new family's schedule, and the tiling caption
reads the model's own peak.)

**A model an existing backend can already run** — one entry in
`Packages/ZephraKit/Sources/ZephraCore/Model/ModelCatalog.swift`, listed in
`all`. `ModelDescriptor` carries where the weights come from (`ModelSource`:
a Hugging Face repo or a local directory), the download and resident sizes,
and a `ModelCapabilities` the interface draws itself from — size presets and
bounds, step and guidance bounds, whether a negative prompt or a seed does
anything. Every number in an entry is hand-written because every number is
measured; leave a comment saying where a figure came from. `ModelMenu` lists
`ModelCatalog.all` and `GenerationStore.switchModel(to:)` does the rest.

**A new backend family** — four things in the app, then the tooling:

1. A `BackendID` case in `.../ZephraCore/Model/BackendID.swift`.
2. A package under `Packages/`, alongside `ZephraBackendZImage`, whose one
   public type conforms to `ImageGenerationBackend` and whose one public
   entry point is a `BackendFactory` (see `ZImageBackendFactory`). It may
   import whatever it needs; nothing above it may.
3. Catalog entries naming that `BackendID`.
4. One line in `Sources/Zephra/ZephraApp.swift`:
   `registry.register(.yourFamily, YourBackendFactory.make)` and the family's
   `InferenceRuntime` in the `CombinedInferenceRuntime` list beside it. That
   file is the only place in the app target allowed to name a concrete backend.

Then the places that are not the app, each a one-line switch case or list entry:
the package and target dependencies in `project.yml`, `MLX_PACKAGES` in the
`Makefile` so `make test-mlx` runs its suites, `QuantizeFamily` in
`Sources/ZephraQuantize` if the family has a packing plan, and `BenchBackends`
in `Sources/ZephraBench` so `--model` can name it.

`InferenceActor` keeps one backend at a time and rebuilds it whenever a
descriptor names a different family, so the old weights are always released
before the new ones are asked for. A descriptor whose family was never
registered surfaces as `EngineError.noBackend`, not as a crash.

`ImageGenerationBackend.availability(of:)` must answer from the disk alone —
never download, never disturb what is loaded. It is what lets the picker say
"13.3 GB download" without starting one.

**A model whose download is not what gets loaded** is the third case, and
FLUX.2 klein is the one that has it: the release is 16 GB of bfloat16 and the
loader reads a packed variant. Such a family implements
`ImageGenerationBackend.build(_:at:onProgress:)`, which the engine calls
between `ensureAvailable` and `load` and shows as `EngineState.building`; every
other family takes the protocol's default, which returns the download
untouched. `ModelDescriptor.builtBytes` says what the packed variant costs on
disk, and non-zero is what tells the engine a build is involved. Availability
then has two more answers, `.needsDownloadAndBuild(bytes:)` and `.needsBuild`,
so the picker says what choosing the model will cost. The packed variant lives
at `ModelCatalog.localModelsDirectory/<descriptor.id>`, which is the naming
every locally built variant already follows. The packer's `shouldContinue`
hook is what makes a build stoppable between tensors.

**A model that edits** reads `GenerationSettings.referenceImage`, PNG bytes the
interface caps at 1024 pixels an edge before they land there.
`ModelCapabilities.supportsReferenceImage` is the gate: `clamp` drops the
picture for any model without it, so the Z-Image and Qwen-Image mappers never
see one, and the well beside the prompt shows only for a model that has it.
The picture is persisted in a second PNG chunk beside the record and comes back
when the image is selected.

## Build & run

Prerequisites, on a fresh Mac: the full Xcode 26 `Xcode.app` selected with
`xcode-select` (the Command Line Tools cannot compile Metal), its license
accepted and `-runFirstLaunch` done, the Metal toolchain downloaded once with
`xcodebuild -downloadComponent MetalToolchain`, and `xcodegen` on `PATH`
(`brew install xcodegen` or `nix profile install nixpkgs#xcodegen`).
`make doctor` checks each and prints the fix.

The Xcode project (`Zephra.xcodeproj`) is generated by `xcodegen` from
`project.yml` and is gitignored. Never edit the generated project — edit
`project.yml` and regenerate.

mlx-swift's Metal kernels require `xcodebuild`; plain `swift build` cannot
build the app target or `ZephraBackendZImage`. `swift build` / `swift test`
only work for `Packages/ZephraKit` (`ZephraCore`, `ZephraSnapshot`,
`ZephraEngine`), which has no MLX dependency by design.

Makefile targets:

- `make doctor` — check the prerequisites above and print the fix for any
  that is missing. Exit status is the number of failures.
- `make gen` — regenerate `Zephra.xcodeproj` from `project.yml`.
- `make build` — generate, then `xcodebuild` the `Zephra` scheme
  (`CONFIG=Release` by default).
- `make run` — build, then open `build/Release/Zephra.app`.
- `make open` — generate, then open the project in Xcode.
- `make bench` — build and run `ZephraBench` (`ARGS=...` to pass flags).
- `make test` — `swift test` in `Packages/ZephraKit` (Core, Snapshot, and
  Engine, fast, no MLX). Anything testable without Metal belongs here.
- `make test-mlx` — `xcodebuild test` over every package that links MLX
  (`MLX_PACKAGES` in the Makefile, written `directory:scheme`). Slower, needs
  `xcodebuild`. `make test-backend` is kept as an alias. Keep `make test`
  MLX-free.
- `make icon` — re-render `AppIcon.appiconset` from `scripts/make-icon.swift`.
- `make release` — build Release, sign with a Developer ID Application identity
  (hardened runtime, secure timestamp), verify, and zip to `build/Zephra.zip`.
  Needs no network. `SIGN_IDENTITY` overrides the auto-detected certificate.
- `make notarize` — submit that zip, staple the ticket, and repackage. Needs
  `xcrun notarytool store-credentials zephra-notary` run once; `NOTARY_PROFILE`
  names the profile.
- `make prefetch` — download the default model weights via `hf download`.
- `make prefetch-flux2` — download the FLUX.2 klein 4B release into the hub
  cache, without the 7.75 GB single-file checkpoint the loader never reads, so
  a first launch skips the download and goes straight to the build.
- `make prefetch-qwen` — download Qwen-Image-2512 and its four-step Lightning
  adapter into `QWEN_MODELS` (external storage by default; 57.7 GB does not
  belong on a boot volume). Name the adapter file explicitly: the repository
  also ships whole merged checkpoints of twenty gigabytes each, and pulling it
  whole costs 101 GB.
- `make quantize` — download the bf16 release and build the 4-bit variant into
  `~/Library/Application Support/Zephra/Models/z-image-turbo-4bit`. `BITS`,
  `GROUP_SIZE`, and `QUANT_OUT` override the defaults (4 bits, group 64).
  `ZephraQuantize` takes a required `--family`; there is deliberately no
  default, because the wrong one silently produces the wrong artifact an hour
  later.
- `make quantize-qwen` — build the 4-bit Qwen-Image variant from `QWEN_SOURCE`
  with `QWEN_LORA` merged into its transformer, into
  `~/Library/Application Support/Zephra/Models/qwen-image-2512-4bit`
  (`QWEN_OUT` overrides). About a minute with the source local.
- `make quantize-flux2` — the build the app does on first load, by hand: pack
  the klein release from the hub cache (or `FLUX2_SOURCE`) into
  `~/Library/Application Support/Zephra/Models/flux2-klein-4b-4bit`
  (`FLUX2_OUT` overrides; `BITS=8` needs a different `FLUX2_OUT`, and the tool
  refuses otherwise). About a minute.
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

- `make test` — `ZephraCoreTests`, `ZephraSnapshotTests` and `ZephraEngineTests`,
  seconds, no Metal.
- One suite or test:
  `cd Packages/ZephraKit && swift test --filter ModelSwap`. The filter is a
  regex over the *type* names, not the `@Suite` display names, so `ModelSwap`
  takes both swap suites and `--filter 'model swap'` matches nothing.
- The MLX packages' suites need `xcodebuild`, and their filter is likewise the
  type name: `cd Packages/ZephraMLXKit && xcodebuild test -scheme
  ZephraMLXKit-Package -destination 'platform=macOS'
  -skipPackagePluginValidation
  -only-testing:ZephraQuantizationTests/QuantizableWeightTests`. A package's
  scheme is its own name, except `ZephraMLXKit`, which ships two library
  products and so is tested through `ZephraMLXKit-Package`.
- `QwenImageKit`'s suites check the port against tensors dumped from
  `diffusers` by `Packages/QwenImageKit/Tools/dump_reference.py`. Adding a
  component means adding its fixture in the same commit; that is what the
  clean-room claim in `PROVENANCE.md` rests on.

No test loads model weights. The `ZephraKit` suites never touch Metal; the MLX
packages' suites run doll's-house tensors through it, and a few of `QwenImageKit`'s
and `Flux2Kit`'s read a real snapshot's config, tokenizer, and safetensors header
files when `QWEN_IMAGE_SNAPSHOT` or `FLUX2_KLEIN_SNAPSHOT` names one (or the hub
cache holds exactly one snapshot). The engine tests drive `MockBackend`
through `MockBackendControl`, a lock-protected dial a `@Sendable` factory can
close over — it fails a load, delays one so cancellation lands mid-flight,
pretends to build, tallies loads, unloads and builds, and records the last
settings a generation was asked for — while `EngineTestBed` gives each test a
throwaway output folder. `ZephraCoreTests` uses the smaller `StubBackend`.

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

Third model: `qwen-image-2512-4bit` — **Qwen-Image-2512**
(`Qwen/Qwen-Image-2512`, Apache 2.0), a 60-layer dual-stream MMDiT of about 20B
parameters, conditioned on Qwen2.5-VL-7B and decoded by a 3-D causal VAE. Built
on the user's own Mac by `make quantize-qwen`, because the release is 57.7 GB of
bf16 and the four-step distillation ships separately as an adapter, so the local
build is where the two are put together. 21.6 GB on disk.

The full-precision source is too large for the boot volume here, so it lives at
`/Volumes/ExternalStorage/Models/Qwen-Image-2512` with the adapter beside it in
`Qwen-Image-2512-Lightning/`; only the configuration files stay in the Hugging
Face cache. Point `QWEN_SOURCE` and `QWEN_LORA` there, and `QWEN_IMAGE_SNAPSHOT`
there for any test that wants real weights.

Measured on an M4 Max, four steps, seed 42: 21532 MB resident at every size,
because the weights are the whole of it. 512 pixels takes 6.9 s (1.57 s/step)
and peaks at 26053 MB; 1024 takes 33.6 s (8.15 s/step) and peaks at 30364 MB;
1328, the model's native resolution, takes 66.7 s (16.25 s/step) and peaks at
32520 MB. Tiled at a 64-cell latent tile the peak barely moves with the image —
26068 MB at 1024, 26088 MB at 1328 — because the tile, not the image, sets the
decode's transient and what is left is the transformer. So 1024 is the default
size: half the seconds of native for an image that still renders legible text,
and the entry's `peakBytes` is measured there.

**The Lightning adapter is not optional.** The base model wants fifty steps and
real classifier-free guidance, which is two forward passes through twenty
billion parameters per step. `lightx2v/Qwen-Image-2512-Lightning` (Apache 2.0)
distils that to four steps and no guidance, and `make quantize-qwen` merges it
into the transformer as it packs, so the runtime never sees an adapter. Run the
same seed and prompt against a build without it and the difference is not
subtle: soft, hazy, mesh-textured surfaces against sharp ones. That is also why
the catalog entry reads `guidanceBounds: 0...0` and
`supportsNegativePrompt: false` — the merged weights were distilled without
either. An entry built from the undistilled release would be the opposite, which
is what `ModelCapabilities` being per-descriptor is for.

Text-to-image never runs Qwen2.5-VL's vision tower: the pipeline supplies token
ids and an attention mask and no pixels. So the ViT is not ported and its
weights are not loaded, along with `lm_head` — together 391 of the checkpoint's
729 text-encoder tensors. `WeightKeyCoverageTests` asserts that rather than
leaving it to be assumed.

Fourth model: `flux2-klein-4b-4bit` and `flux2-klein-4b-8bit` — **FLUX.2 klein
4B** (`black-forest-labs/FLUX.2-klein-4B`, Apache 2.0, ungated), a 3.9-billion
parameter rectified-flow transformer of 5 dual-stream and 20 single-stream blocks,
conditioned on Qwen3-4B and decoded by a plain 2-D KL autoencoder, distilled to
four steps with no guidance. The one download is the bf16 release without the
root single-file checkpoint, 16 GB; the app packs it into the chosen variant on
first load (`builtBytes` says what that writes), and `make quantize-flux2` is the
same build by hand. Both variants share the download. The release is kept
afterwards: the other variant packs from it, and the hub cache is `hf`'s to
prune, not Zephra's.

The text encoder is Qwen3-4B, bit for bit, and the transformer conditions on
the hidden state after its 9th, 18th and 27th layers laid side by side, padded
to 512 tokens with every position kept. So only the first 27 layers are built,
loaded, or packed; layers 27 to 35 and the final norm are omitted by the plan,
`Qwen3Model` builds `layersNeeded` layers rather than what the config says, and
`WeightKeyCoverageTests` pins the leftover set. The three modulation linears are
shared by every block of their kind and held whole: 142 million parameters is
not worth a knob. The autoencoder normalises its packed 128-channel latent with
batch-norm running statistics rather than a scaling factor, and its config
names FLUX.2-dev as its origin; only the copy inside the klein-4B repository is
ever read. Its memory figures in the catalog are estimates marked
`TODO(measure)` until the benchmark run replaces them.

Two of this port's choices are load-bearing and easy to undo by accident. The
schedule uses the pipeline's empirical shift, not the scheduler config's
`base_shift` and `max_shift`, which klein's pipeline never reads. And the
query-key norm epsilon is the config's 1e-6, where both MIT ports use 1e-5;
`PROVENANCE.md` lists these with the other two departures.

The same checkpoint edits: a reference picture is fitted to at most a megapixel
keeping its shape, trimmed to multiples of 16, encoded, and its tokens placed
after the image being made on image index 10 of the rotary embedding's first
axis. The schedule's shift counts only the image being made.

Each family's quantization plan lives in its own backend package's
`Quantization` directory; the packer they drive is shared, in
`ZephraQuantization`. Precision there is a function of the tensor name: an
ordered list of rules per component, first match wins, and a rule resolving to
no precision leaves the tensor alone. `QuantizableWeight` answers only whether
MLX *can* pack a tensor; `QuantizedComponent.precision(for:)` answers whether we
*want* it packed, and it is asked first, because the group size it names is what
divisibility is tested against.

Qwen-Image holds its modulation layers at eight bits while the rest goes to
four. They are 6.8 of the transformer's 20.4 billion parameters and they decide
how strongly every other layer responds; published four-bit builds that pack
them with everything else lose coherent structure. It costs about 3.4 GB — four
more bits for each of 6.8 billion weights — which is why the transformer is 16.2 GB
on disk rather than the 12.8 GB a pure four-bit build would write.

An adapter naming weights the component has not got stops the build. That is the
one check worth keeping: an adapter written against a different port of the same
model matches nothing, merges nothing, and hands back the base model — a failure
that looks exactly like a build that worked.

Three more things about the Z-Image plan are load-bearing and easy to break:

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
  stays in Swift 5 language mode so its 49 upstream files compile untouched.
- Every package pins the same exact `mlx-swift` version. When bumping it, re-run
  `Flux2Kit`'s bf16 matmul probe test: mlx-swift up to 0.31.6 miscompiles a
  bf16 split-K matmul on M5-class GPUs at the single block's output shape, and
  the port relies on its conditioning stream being float32 to stay clear of it.
- No emojis in code or docs.
- Keep files small; split before a file grows past its target size.
- Zephra may ship commercially. Every new dependency, vendored file, or model
  gets an entry in `THIRD_PARTY_NOTICES.md` (copyright line, license, and any
  NOTICE file) in the same commit. That file is bundled and shown in
  Settings > About; it is the disclosure, so keep it exact.

## Debugging hooks

- `ZEPHRA_PREVIEW_STATE=ready|image|editing|generating|downloading|building|failed` launches a
  Debug build frozen in that state with no model, for screenshots (`make screenshot`).
- `make logs` streams `os.Logger` output for subsystem `io.zephra`.
- `make bench ARGS="--size 1024 --steps 9 --runs 3 --json"` measures load, s/step, and peak memory
  headlessly; benchmark on an idle machine, Release only. `--reference IMAGE` measures the
  editing path on a model that has one.
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
  255. It is the starting value of each family's tile — `VAETiledDecode.latentTile` for
  Z-Image, `QwenImageAutoencoder.latentTile` for Qwen-Image — and so is what `ZephraBench` and
  the command line use. The app overrides it as soon as its window appears: Settings >
  Performance holds a three-way preference (`AppSettings.vaeTiling`) and `VAETilingPolicy`
  applies it for the model about to run, tiling under Automatic when that model's `peakBytes`
  is over four fifths of physical memory.

## Environment notes

- In shell tooling, use `/bin/ls` rather than the interactive `ls` — the
  shell's `ls` function can hang on this volume.
