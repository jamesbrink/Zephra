# Vendored: zimage.swift

- **Upstream:** https://github.com/mzbac/zimage.swift
- **Vendored at:** `970f83e477028e81fc19fc7035228ced89dc1ffd` (`main`, 2025-12-20).
  Tag `0.1.2` predates the resident-pipeline API (`loadModel`, `generateToMemory`,
  progress callbacks), so `main` was used.
- **License:** MIT, per upstream `README.md` "License" section. The upstream
  repository has **no LICENSE file**; the text in `LICENSE` here is the standard
  MIT text with the upstream author as copyright holder.
- **Included:** `Sources/ZImage/**` (49 upstream files, directory tree preserved verbatim,
  plus the files the patch log below marks as new).
- **Excluded:** `Sources/ZImageCLI`, `Tests/**`, `examples/**`, `images/**`.

## Manifest changes (Package.swift)

- tools-version 5.9 → 6.0; platforms macOS 14 → 15; iOS dropped.
- mlx-swift `.upToNextMinor(from: "0.29.1")` → `exact: "0.31.3"` → `revision:
  "ea8a179690170ca891a97bc0473198ab1ecda5f4"` (main, 2026-09-11), for mlx v0.32.2's completion-handler
  fix — a GPU reset is rethrown on the calling thread instead of aborting inside Metal's
  completion handler — until a tagged mlx-swift release carries it.
- swift-transformers `.upToNextMinor(from: "0.1.24")` → `exact: "0.1.24"`, the pin every
  Zephra package carries: `QwenImageKit`'s assembled tokenizer leans on this version's `Split`
  pre-tokenizer behaviour, and one resolved version keeps the graph one copy.
- Added `swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]`
  on the `ZImage` target. The upcoming feature makes the pipeline's async methods run on the
  caller's executor, so Zephra's inference actor keeps MLX work on its own serial queue.
- Dropped CLI and test targets (Zephra has its own `ZephraBench` tool).
- Added `.package(path: "../ZephraMLXKit")` and the `ZephraMLX` product on the `ZImage` target,
  for `LayerWeightStream` and `ShardIndex` (see "stream the block stacks and the text encoder"
  in the patch log). A copy of the stream inside this package would not do: it reports every
  pass into `ZephraMLX.WeightStreamMeter`, which `ZephraBench --stream` and
  `MLXRuntime.weightStreamReading()` read, and a second meter would report nothing to either.
  `ZephraMLX` depends only on MLX, MLXNN and `ZephraCore`, all of which this package's graph
  already resolves, so it adds no new package and no new version to pin. It is the one Zephra
  dependency here; `VAETiledDecode` and `ZImageLatentPreview` stay copies on purpose, as their
  entries below say, because those are whole algorithms and this is one type with a contract.

## Re-sync procedure

```sh
git clone https://github.com/mzbac/zimage.swift /tmp/zimage-src
git -C /tmp/zimage-src diff 970f83e4..<new-sha> -- Sources/ZImage > /tmp/zimage.diff
# hand-apply against Packages/ZImageKit/Sources/ZImage, re-apply the patches below,
# bump UPSTREAM_SHA in scripts/vendored-diff.sh and the "Vendored at" line above, then:
make vendored-diff
```

`scripts/vendored-diff.sh` fetches upstream at the pinned commit into a scratch clone
(`~/.cache/zephra/zimage-src`, or `ZIMAGE_SCRATCH`) and diffs it against
`Packages/ZImageKit/Sources/ZImage`. Without a flag it prints the whole unified diff and
then every hunk with no `ZEPHRA-PATCH` marker; `--check` prints only those and exits 1 when
there are any, or when a file of ours has no marker in its opening comment. It is the
mechanical form of the rule at the top of the next section: an unmarked hunk is either a
patch that lost its reason or an edit that should not be there.

## Local patches

Every local edit carries a `// ZEPHRA-PATCH: <reason>` comment and a line here.

- `Pipeline/ZImagePipeline.swift`, `Pipeline/ZImageControlPipeline.swift`: `RandomStateOrKey?` seed key
  typed as `MLXArray?` (mlx-swift 0.31 rejects the existential in the generic `key:` parameter). 3 sites.
- Same files: CFG blend `guidanceScale * (positive - negative)` wraps the scalar in `MLXArray(...)`
  because Swift 6.3 resolved the `*` to an unrelated overload. 3 sites. No behaviour change.
- `Weights/WeightsMapping.swift`: `applyTransformer` withholds the `all_final_layer` subtree from
  the generic `Module.update`. That subtree's `adaLN_modulation` is a module keyed `"1"`, and
  `ModuleParameters.unflattened` reads a numeric path segment as an array index, so the update
  offered an array where a module was expected and threw. Because `Module.update` walks `items()`,
  a Swift dictionary whose order is seeded per process, the throw sometimes landed before the 30
  transformer blocks were reached and left them on their random initialisation. Correctness fix,
  not a performance one: affected runs produced smooth colour blobs instead of an image.
  `loadFinalLayerWeights` already loads that subtree, and the quantization manifest does not
  quantize it, so nothing is lost.
- `Model/Transformer/ZImageTransformerPrecision.swift` (new) and `Model/Transformer/ZImageTransformer2D.swift`:
  the 8-bit repository stores every unpacked transformer tensor as F32, including the quantization
  scales, and MLX widens a mixed multiply, so the whole DiT ran in float32. Parameters are cast to
  bfloat16 once at load and `forward` casts its latents and prompt embeddings on entry, shadowing
  its own parameters with `let` so the labels stay upstream's (`timestep:`, `promptEmbeds:`) — an
  earlier version renamed them to `timestepIn:`/`promptEmbedsIn:` for no reason the diff
  needed, which put a hunk on every call site. Measured:
  resident 13029 MB to 12236 MB, peak 24298 MB to 23501 MB. Step time unchanged within the noise
  of a shared machine; the isolated kernels are about 8 percent faster in bfloat16. Output at a
  fixed seed is identical in composition with a mean absolute pixel difference of 2.2 of 255,
  which is bfloat16 rounding. `ZEPHRA_DIT_DTYPE=f32` restores the old behaviour.
- `Tokenizer/Tokenizer.swift`: `encodeChat` pads to the longest prompt rounded up to a multiple of
  32 instead of to the 512-token limit. The Qwen encoder is causal, so a trailing pad token cannot
  reach a real token and the kept embeddings are unchanged. Measured 352 ms to 43 ms per
  generation at 1024 pixels. `ZEPHRA_PAD_PROMPT=full` restores the old behaviour.
- `Model/VAE/AutoencoderKL.swift`: `VAEDecoder.callAsFunction` evaluates after each up block. As
  one lazy graph the decoder held every intermediate feature map alive, and at 1024 pixels it took
  peak memory from 16.4 GB to 26.5 GB, more than the weights themselves. Staging it caps the peak
  at 23.5 GB. Decode time is unchanged.
- `Weights/WeightsApplyError.swift` (new), `Weights/WeightsMapping.swift`,
  `Pipeline/ZImageControlPipeline.swift`: a failed weight apply used to be logged and swallowed, so
  a model with randomly initialised layers reported a successful load. That is how the
  `all_final_layer` bug above stayed hidden. `applyToModule` now throws `WeightsApplyError`, and so
  do `applyTransformer`, `applyTextEncoder`, `applyVAE` and the empty-weights paths that previously
  warned and returned. The error propagates out of `loadModel`. The control pipeline carried its
  own copy of the same swallowing apply; it throws too, and it gained the same `all_final_layer`
  key filter, without which making it throw would turn a load that used to half-succeed into a hard
  failure for ControlNet users. Zephra does not exercise the control path, so that half is
  compile-verified only.
- `Pipeline/ZImageStepProfile.swift` (new), `Pipeline/ZImagePipeline.swift`: opt-in phase timing and
  MLX memory reporting for the denoise loop, the text encoder and the VAE, enabled with
  `ZEPHRA_PROFILE_STEP=1`. Compiles to a branch on a `static let` when off.
- `Pipeline/ZImagePipeline.swift`: `clearsCacheAfterGeneration` makes the trailing `GPU.clearCache()`
  a knob instead of an unconditional call. Default on, because the VAE decode peak is what pushes
  the process into memory pressure; `ZEPHRA_KEEP_CACHE=1` keeps the warm buffers for the next run.
- `Pipeline/ReferenceLatents.swift` (new), `Pipeline/ZImagePipeline.swift`,
  `Pipeline/PipelineUtilities.swift`, `Pipeline/ZImageControlPipeline.swift`: SDEdit, so a
  generation can start from a picture instead of from pure noise.

  `ZImageGenerationRequest` gains `referenceImage: CGImage?` and `referenceStrength: Float`,
  both defaulted to the old behaviour, so every existing caller compiles and behaves unchanged.
  When a reference is present, `generateCore` encodes it to a latent, enters the denoise loop
  `steps * strength` steps from the end, and starts that step from
  `(1 - sigma) * reference + sigma * noise` — the same interpolation the flow-matching scheduler
  walks back down, using the run's own seeded noise, so a fixed seed still reproduces exactly.
  The loop's range starts at that index; the progress reports still count against the full
  requested step count, so a host drawing one segment per step shows the skipped ones as
  finished rather than showing a shorter run.

  The two decisions — where to enter and what to enter with — live in `ReferenceLatents` as pure
  functions, so `ZImageScheduleTests` pins them without loading weights. Strength buys a share
  of the steps rather than naming a noise level, which is diffusers' `get_timesteps` mapping;
  entering at the first sigma at or below the strength looks equivalent and is not, because a
  distilled ladder is not evenly spaced. A strength of 1 lands on step 0, where the mix is pure
  noise and the picture contributes nothing, which is why the unpatched path is a special case
  of the patched one rather than a branch beside it. A strength too small to buy a whole step
  still buys one: running none would hand the reference straight back. The share is
  *truncated*, where `get_timesteps` takes its ceiling — a deliberate departure, because
  truncating is the only mapping under which every strength the slider offers keeps some of
  the picture (the ceiling of 0.8 or 0.9 of four steps is four, an entry of 0). The product is
  taken in doubles with the strength nudged up by 1e-7 first, so a `Float` strength's own
  rounding (ten steps at 0.7 come to 6.9999999) cannot truncate a whole share to the one below.

  `encodeImageToLatents` moved from `ZImageControlPipeline`, where it was private to the
  ControlNet path and so never reached from Zephra, which does not run that pipeline — it was
  live code upstream, not dead code. It is now in `PipelineUtilities`, so the SDEdit path and
  the ControlNet path share one encode
  instead of drifting as two copies. Its body is unchanged apart from taking the latent channel
  count and the scale and shift factors directly rather than a `ZImageVAEConfig`, because the
  two callers have that config in two different shapes. The encoder it drives needs no new
  weights: the autoencoder builds it unconditionally and `WeightsMapping.applyVAE` has always
  applied its 106 tensors, in both the 8-bit and the 4-bit snapshots.
- `Model/VAE/VAETiledDecode.swift` (new), `Model/VAE/AutoencoderKL.swift`: an opt-in tiled decode.
  The decode's transient scales with the resolution it runs at, not with the weights, so a set
  latent tile edge makes the decoder take overlapping latent tiles, evaluate each as it is
  produced, and cross-fade the quarter-tile overlap with a linear ramp. Shaped after diffusers'
  `enable_vae_tiling`. Measured at 1024 pixels with a 64-cell tile: peak 23501 MB to
  17673 MB, so the decode transient falls from 11265 MB to 5437 MB against unchanged resident
  memory. Output at a fixed seed is the same image with a mean absolute pixel difference of 0.97
  of 255 and no visible seam at a tile boundary. Off by default because the untiled decode is
  exact and 32 GB Macs do not need this; it is what lets a 16 GB Mac reach 1024 pixels on
  the 4-bit variant, where the untiled peak is 17839 MB.

  `VAETiledDecode.latentTile` is a public settable property rather than a constant, so a host can
  change the tile between generations without a relaunch. It starts at `ZEPHRA_VAE_TILE`, read
  here because this package cannot take `InferenceEnvironment`; `ZephraBackendZImage` overwrites
  it from the engine's per-run choice just before every generation, on the inference queue, so
  in Zephra the vendored read decides nothing and the app and the bench both set it the same
  way. `nonisolated(unsafe)` because it is a static written and read on more than one thread in
  the general case; in Zephra both happen on the inference queue.

  The pixels kept from each tile are the stride's worth, and the blend is the rest of the tile:
  both are derived from the rounded latent stride rather than rounded separately, because a
  tile edge whose quarter is not whole (18, say) would otherwise keep more than it strode past
  and return an image wider than the latent with a doubled band at every seam.

  `ZephraMLX.TiledDecode` in `Packages/ZephraMLXKit` is the same algorithm, shared by the other
  families. This copy is kept on purpose: pointing vendored code at a Zephra package would
  complicate every re-sync, so the two are expected to drift only when one of them is fixed.

  Cancellable between tiles (`// ZEPHRA-PATCH: stop between VAE tiles`): `VAETiledDecode.decode`
  takes a throwing `body` and rethrows, `VAEDecoder.callAsFunction` checks
  `Task.checkCancellation()` before each tile and so throws, and the chain above it —
  `AutoencoderKL.decode`, `PipelineUtilities.decodeLatents`, and the private `decodeLatents` in
  both pipelines — is marked `throws` and called with `try`. A 1024-pixel decode is seconds, and
  Stop should not wait for it. Untiled, nothing is checked and nothing changes; the audit of
  2026-09-05 found the earlier entry here did not say the tiled decode was uncancellable, and
  this replaces that gap. The two application sites in the ControlNet pipeline are
  compile-verified only, as the rest of that pipeline is.

- `Pipeline/ZImageLatentPreview.swift` (new), `Pipeline/ZImagePipeline.swift`,
  `Model/VAE/AutoencoderKL.swift`: preview frames of a run in flight. `generateToMemory` and
  `generateCore` take a second, defaulted `previewHandler`, and the denoise loop calls it after
  each step's `MLX.eval` — never on the last step, where the real decode follows immediately —
  with the step index, the step count, and a closure that makes the frame from the run's
  estimate of the *finished* latent, `x - sigma * v`, rather than from the latent it holds: the
  schedule is bent towards its noisy end, so the latent itself decodes to mush on the early
  rungs. A closure rather than
  a frame because the decode is a whole pass through the autoencoder: the host throttles to one
  frame every three quarters of a second and never pays for the ones it drops. The frame is made
  inside `ZImageStepProfile.measure("preview decode")`, so `ZEPHRA_PROFILE_STEP=1` reports it
  beside the step and VAE lines.

  `ZImageLatentPreview` pools the 16-channel latent so its long edge is at most 32 cells (a
  quarter at 1024 pixels, so a sixteenth of the decode's work) and decodes it through
  `AutoencoderKL.decodeUntiled`, a second ZEPHRA-PATCH entry point that skips the tiling — a
  latent that small is smaller than any tile worth cutting — and leaves the pixels channels-last
  in the range -1 to 1, which is what the byte packing wants. `VAEDecoder.untiled` widened from
  private to internal for it.

  `ZephraMLX.LatentPreview` in `Packages/ZephraMLXKit` holds the same pooling and byte packing
  for the other two families. This copy is kept on purpose, for the same reason `VAETiledDecode`
  is a copy: a Zephra dependency in this package's manifest would complicate every re-sync.

- `Pipeline/ZImageStreaming.swift` (new), `Weights/ZImageResidentParameters.swift` (new),
  `Model/Transformer/ZImageTransformer2D.swift`, `Model/Transformer/ZImageTransformerPrecision.swift`,
  `Model/TextEncoder/TextEncoder.swift`, `Weights/ZImageWeightsMapper.swift`,
  `Pipeline/PipelineUtilities.swift`, `Pipeline/ZImagePipeline.swift`: stream the three
  transformer block stacks and the text encoder's layers from disk, so a Mac that cannot hold
  this model still runs it.

  `loadModel` gains a defaulted `streaming: ZImageStreaming?`; nil is the unpatched path
  exactly. With it, each stack is handed to a `ZephraMLX.LayerWeightStream` over the shards
  `ZImageWeightsMapper.shardIndex(for:)` indexes, and `forward` runs the stack through the
  stream instead of its own `for` loop. The loops themselves are untouched and still there,
  under the `else`. What the streamed path costs is one read of the model per step; what it
  buys is a peak set by a window of three layers rather than by the whole stack.

  The order in `loadModel` is load-bearing and is the order `LayerWeightStream`'s own doc
  demands: apply the component's weights, cast its float32 parameters, attach its stream, and
  only then evaluate what is left. So `castFloatParameters` no longer calls `MLX.eval`: the
  cast has to stay lazy for the stream to capture it, and evaluating the whole tree there
  would read every streamed block off the disk and hold it, which is the one thing streaming
  must not do. `ZImageResidentParameters.eval` is where a load is read in now, last of all and
  told what is streamed. Resident that evaluates everything `castFloatParameters` used to and
  the text encoder and the autoencoder besides, which were lazy until first use before: the
  same bytes, read at load rather than at the first step, so `mem: load done` reports the
  load's figure and not a fraction of it. No output changes.

  The stacks are keyed on bare names (`layers.0.attention.to_q.weight`) because that is what
  both Z-Image layouts write and what `WeightsMapping.applyToModule` already matches against;
  the text encoder's stack is the one place the checkpoint and the module tree differ
  (`model.layers` against `encoder.layers`), and `ZImageResidentParameters` holds both spellings
  so the loader and the stream cannot drift. The encoder is not cast at load, so a streamed
  encode is bit-for-bit a resident one.

  Every door into either stack became throwing, since a streamed pass can fail on a shard that
  changed under the model and is stopped between layers with `Task.checkCancellation`:
  `ZImageTransformer2DModel.forward`, `QwenEncoder.forward` and `callAsFunction`,
  `QwenTextEncoder.encode`, `callAsFunction`, `forwardWithHiddenStates`, `encodeForZImage` and
  `encodeJoint`, and the `try` those forced on `PipelineUtilities.encodePrompt` and on the
  denoise loop's `step build`. With no stream attached none of them can throw.
  `QwenEncoder.forwardCausal` is deliberately left alone: it is the prompt enhancer's
  token-at-a-time path, which Zephra never enables, and it runs the stack once per token with
  a KV cache the stream knows nothing about. `ZImageControlPipeline` needed no change — its
  transformer is `ZImageControlTransformer2DModel`, which does not stream — and is
  compile-verified only, as the rest of that path is.

  `loadQuantizedComponent` now sorts the component's shards by name and lets the first of a
  duplicated key win. It used to iterate `contentsOfDirectory`, which has no defined order, and
  let the last win, so which shard a duplicated key resolved to was the file system's choice.
  `ShardIndex` and `SafetensorsShards.weights` both take the first of a sorted list, and a
  stream that disagreed with the loader about which shard a tensor came from would hand the
  forward pass a different tensor on the second pass than on the first. No snapshot the catalog
  names carries a key in two shards, so nothing that loads today changes.

- Marker discipline, retrofitted after the audit of 2026-09-05: about twenty changed lines
  carried no marker — every `try` the throwing weight apply forced on its call sites in
  `ZImagePipeline.swift`, `ZImageControlPipeline.swift` and `WeightsMapping.swift`, the
  `throws` on those signatures, the `ZImageStepProfile.noteMemory` readings in `loadModel`,
  the `clearsCacheAfterGeneration` call sites, the `CoreGraphics` import in
  `PipelineUtilities.swift`, the `padsToLimit` knob in `Tokenizer.swift`, and the deleted
  private `encodeImageToLatents` in the control pipeline. Each now carries a short trailing
  `// ZEPHRA-PATCH:` naming the patch above it belongs to, and `make vendored-diff` fails if
  another appears.

## Known upstream behaviour (not patched)

- `Tokenizer/Tokenizer.swift`'s `makeBPETokenizerData`, the fallback taken when a snapshot has
  `vocab.json` and `merges.txt` but no `tokenizer.json`, is wrong for the Qwen2 tokenizer
  family in the two ways `QwenImageKit`'s own assembly used to be: it emits a lone `ByteLevel`
  pre-tokenizer with `useRegex` on, which is GPT-2's regex rather than Qwen2's, and it drops
  every merge line beginning `#`, which takes 96 real merges with the `#version:` header. It
  is unused: both Z-Image snapshots the catalog names ship `tokenizer/tokenizer.json`, and the
  `tokenizer/*` pattern fetches it, so the `AutoTokenizer` branch is the one that runs. Not
  patched because nothing reaches it; `QwenImageTokenizer+Assembly.swift` is the corrected
  assembly should a re-sync ever need one.
- A denoise step is dominated by the 8-bit quantized matmuls, and those already run near the rate
  the same shapes reach in isolation. Measured with `ZephraBench --micro`, 8-bit group-size-32
  matmul is as fast as the dense bfloat16 equivalent at these shapes, so dequantizing the DiT to
  bfloat16 for speed would cost about 6 GB and buy nothing.
- Graph construction for a whole step takes single-digit milliseconds (1.3 ms measured on a quiet
  machine, 2 to 9 ms under load) against seconds of evaluation, so `MLX.compile` has no CPU-side
  overhead to remove.

## Experiments not kept

- **TeaCache-style step caching.** Implemented and measured, then removed: no threshold both
  saves a step and leaves the image alone. The idea is to accumulate the relative L1 change of
  the main block stack's input between consecutive steps and, while the total stays under a
  threshold, skip the 32 layers and reuse the previous step's residual. Over Z-Image-Turbo's 9
  steps at 1024 pixels, seed 42, those per-step changes are 0.154, 0.127, 0.118, 0.135, 0.167,
  0.216, 0.291 and 0.410 — never small. Thresholds of 0.05 and 0.10 therefore skipped nothing
  at all (and, as a control, reproduced the unpatched image bit for bit). A threshold of 0.13
  skipped one step of nine and gave a mean absolute pixel difference of 11.7 of 255, with the
  robot's head, hands and headline text all redrawn. A threshold of 0.20 skipped three and gave
  26.9 of 255 — a different picture, with an invented coffee cup. TeaCache is tuned for 25 to
  50 steps, where consecutive steps are close enough for the accumulation to mean something;
  a 9-step distilled schedule moves too far per step for any of it to apply.

## Corrections to earlier notes in this file

- The `all_final_layer` / `adaLN_modulation` apply failure was previously recorded here as
  harmless because output images looked correct. It was not harmless. See the patch log above.
- Peak memory was previously attributed to weight loading reading shards fully before applying
  them. Instrumenting MLX's allocator shows loading is entirely lazy and reaches 7.2 GB. The peak
  is the VAE decode at 1024 pixels, which alone took the process from 16.4 GB to 26.5 GB.

## Vendored code that Zephra links but never runs

The September 2026 audit looked for dead code across the whole app and found none
in our own sources. Roughly a third of the 10,946 lines here, though, is upstream
work this app has no path into. It stays, because the vendoring policy is to keep
the copy close to `mzbac/zimage.swift` so a re-sync is a diff and not a merge, and
`make vendored-diff` only works while that is true. It is written down because it
is license surface and audit surface for a commercial ship, and because "unused"
is worth knowing before someone reads it as a feature that exists:

- `Pipeline/ZImageControlPipeline.swift` and
  `Model/Transformer/ZImageControlTransformer2D.swift` — the ControlNet pipeline.
  Nothing outside this package names either type.
- `LoRA/` in its entirety. Zephra merges adapters at build time in
  `ZephraQuantization`'s packer, so no adapter reaches the runtime and
  `LoRALinear`, `LoRAKeyMapper`, `LoRAApplicator` and `LoRAWeightLoader` are
  never constructed. Runtime LoRA is a roadmap item; if it lands it will be
  built on the shared packer's own path, not on this.
- `Model/TextEncoder/Vision/` — Qwen2.5-VL's vision tower. Text-to-image supplies
  token ids and an attention mask and no pixels, which is why the port loads
  neither the ViT's weights nor `lm_head`; `WeightKeyCoverageTests` asserts that
  rather than leaving it assumed.
- `Weights/WeightsAudit.swift` — a diagnostic with no caller.

Anything here becoming reachable is a real change to what the app does, and wants
a `ZEPHRA-PATCH` note and an entry in the patch log above like any other.
