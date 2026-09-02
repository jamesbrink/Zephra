# Vendored: zimage.swift

- **Upstream:** https://github.com/mzbac/zimage.swift
- **Vendored at:** `970f83e477028e81fc19fc7035228ced89dc1ffd` (`main`, 2025-12-20).
  Tag `0.1.2` predates the resident-pipeline API (`loadModel`, `generateToMemory`,
  progress callbacks), so `main` was used.
- **License:** MIT, per upstream `README.md` "License" section. The upstream
  repository has **no LICENSE file**; the text in `LICENSE` here is the standard
  MIT text with the upstream author as copyright holder.
- **Included:** `Sources/ZImage/**` (49 files, directory tree preserved verbatim).
- **Excluded:** `Sources/ZImageCLI`, `Tests/**`, `examples/**`, `images/**`.

## Manifest changes (Package.swift)

- tools-version 5.9 → 6.0; platforms macOS 14 → 15; iOS dropped.
- mlx-swift `.upToNextMinor(from: "0.29.1")` → `exact: "0.31.3"`.
- Added `swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]`
  on the `ZImage` target. The upcoming feature makes the pipeline's async methods run on the
  caller's executor, so Zephra's inference actor keeps MLX work on its own serial queue.
- Dropped CLI and test targets (Zephra has its own `ZephraBench` tool).

## Re-sync procedure

```sh
git clone https://github.com/mzbac/zimage.swift /tmp/zimage-src
git -C /tmp/zimage-src diff 970f83e4..<new-sha> -- Sources/ZImage > /tmp/zimage.diff
# hand-apply against Packages/ZImageKit/Sources/ZImage, re-apply the patches below
```

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
  bfloat16 once at load and `forward` casts its latents and prompt embeddings on entry. Measured:
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
  change the tile between generations without a relaunch. It starts at `ZEPHRA_VAE_TILE`, which
  is how `ZephraBench` and the command line still reach it; the Zephra app overwrites it from
  Settings > Performance for the model it is about to run, so inside the app the environment
  variable only decides what happens before the first window appears. Written from the main
  thread and read on the inference thread, which is why it is `nonisolated(unsafe)`: the worst a
  race can do is decode one image with the previous setting.

## Known upstream behaviour (not patched)

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
