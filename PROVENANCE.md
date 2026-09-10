# Provenance of Zephra's own model ports

Zephra may ship commercially, so where each of its own model implementations
came from is a legal question and not only a technical one. This file records
the answers while they are still checkable. `Packages/QwenImageKit` and
`Packages/WanKit` are clean-room ports; `Packages/Flux2Kit` and
`Packages/LTX2Kit` are translations with attribution. The claims are different, and each section says which it is
making.

# `Packages/QwenImageKit`

## The short version

`Packages/QwenImageKit` is a clean-room implementation. It was written from
Qwen-Image-2512's own published configuration files and from Apache-2.0 and
MIT references. **No code was read from or copied out of
`mzbac/qwen.image.swift`.**

## Why that mattered

`mzbac/qwen.image.swift` is the obvious starting point: it is by the same
author as the `zimage.swift` Zephra already vendors, and it already runs
Qwen-Image-2512 on mlx-swift. It is **GPL-3.0**, and its README says so
plainly — "Commercial usage is allowed as long as your downstream distribution
also complies with GPLv3". Copying from it, or deriving from it, would make
Zephra a GPLv3 work and require publishing Zephra's source. That forecloses an
option `AGENTS.md` deliberately keeps open, so the repository was never opened.

## What was used instead

| Reference | License | What was taken |
|---|---|---|
| `Qwen/Qwen-Image-2512` config files | Apache 2.0 | Every architectural constant: layer counts, head dimensions, rope axis widths, VAE channel multipliers, scheduler shift parameters. Read directly out of the model's `config.json` files rather than from prose about them. |
| `huggingface/diffusers` | Apache 2.0 | The reference behaviour. `QwenImageTransformer2DModel`, `AutoencoderKLQwenImage`, `FlowMatchEulerDiscreteScheduler` and the pipeline's prompt handling define what this port must reproduce. |
| `mlx-gen` (https://github.com/lpalbou/mlx-gen) | MIT | One published finding, not code: that four-bit modulation layers cost coherent structure in this architecture. It is why `QwenImageQuantizationPlan` holds them at eight bits. |
| `Packages/ZImageKit` (vendored) | MIT | One approach, not a file: assembling a byte-level BPE tokenizer from `vocab.json` and `merges.txt` when a snapshot ships no `tokenizer.json`. Noted in `THIRD_PARTY_NOTICES.md`. The assembly itself now follows `transformers`' `Qwen2Tokenizer` rather than that copy, which carried GPT-2's pre-tokenizer and dropped the merges beginning `#`; `QwenImageTokenizer+Assembly.swift` says what it emits. |

## How the boundary was kept honest

Behaviour was pinned by comparison with `diffusers`, not by comparison with
another Swift port. `Packages/QwenImageKit/Tools/dump_reference.py` runs the
Python reference and writes tensors to
`Packages/QwenImageKit/Tests/QwenImageTests/Fixtures`; the Swift suites assert
against those. Every component has such a fixture — rope, scheduler, latent
packing, text encoder, one MMDiT block, the whole transformer, VAE decode, VAE
encode, and the tokenizer — so "does this match the reference" is a question
the test suite answers rather than a claim in a commit message.

The tokenizer's fixture is `tokenizer_ids.json`: the ids the Hugging Face
`Qwen2Tokenizer` produces for twenty-five prompts chosen for the ways an
assembled pre-tokenizer can differ from the real one (hyphens, contractions,
digits, runs of newlines, merges that begin with `#`, a combining accent, other
scripts), plus the pipeline's own `prompt_template_encode` and its
`prompt_template_encode_start_idx`, both read off `QwenImagePipeline` itself. So
`QwenImagePromptTemplate`'s text and `dropIndex` are checked against the
reference too, not only against each other. Until that fixture existed the
suite compared the tokenizer only to itself, and its pre-tokenizer was GPT-2's
rather than Qwen2's; nine of the twenty-five prompts encoded differently. The
text-encoder fixture is dumped from a plain `Qwen2Model` rather than
`Qwen2_5_VLForConditionalGeneration`, which is equivalent for text-only input
because the three multimodal rotary axes coincide when no image is present; that
reduction is why a 1-D rotary embedding in the port is correct.

`QwenImageVAEEncoder` and `QwenImageVAEDownsample` were written from
`diffusers`' `QwenImageEncoder3d` and `QwenImageResample` in
`models/autoencoders/autoencoder_kl_qwenimage.py`, and from the shipped
`vae/config.json`, the same way the decoder was. Their fixture is
`vae.in.pixels` / `vae.out.latent` in `vae.safetensors`, dumped by
`dump_vae` from `vae.encode(picture).latent_dist.mode()`, and
`VAEEncoderParityTests` asserts against it. Two behaviours of the reference are
pinned there because both fail quietly: `quant_conv` is applied inside
`_encode`, before the diagonal Gaussian is formed; and a downsampler's
`time_conv` is skipped for the first chunk of a sequence, which a still image
always is.

The structural differences from a port that had been derived are visible in
the source and are the natural consequence of writing from `diffusers`:

- The 3-D causal autoencoder is implemented in two dimensions. A single frame
  makes the other two temporal kernel slices multiply nothing but zero
  padding, so dropping them is exact, and it removes `Conv3d` and every 5-D
  tensor from both halves. `QwenImageVAEWeights` slices the checkpoint
  accordingly. The encoder's `down_blocks` is a flat, heterogeneous list
  because the checkpoint's keys are one, while the decoder's `up_blocks` are
  nested because its keys are; a port that had been derived from another would
  not have both shapes side by side.
- The transformer's module tree does not mirror the checkpoint's `Sequential`
  numbering. MLX unflattens a numeric path segment into an array position when
  loading parameters but into a dictionary key when replacing modules during
  quantization, so a mirrored tree can be loaded or quantized but not both.
  `QwenImageTransformerWeights` renames four prefixes at load instead.
- The vision tower and `lm_head` are neither ported nor loaded — 391 of the
  text encoder's 729 tensors — because text-to-image supplies no pixels and
  conditions on hidden states rather than logits. `WeightKeyCoverageTests`
  asserts that rather than leaving it assumed.

## If this ever needs re-checking

The claim to defend is narrow: no file in `Packages/QwenImageKit` was copied
from or derived from a GPL-licensed source. The git history of this branch
shows the port being built component by component, each one landing with its
`diffusers` fixture in the same commit or the one after it.

# `Packages/Flux2Kit`

## The short version

`Packages/Flux2Kit` is a translation, not a clean-room port. Two MIT-licensed
Swift implementations of FLUX.2 klein exist, and MIT permits translating them
into proprietary software with attribution, so there was no reason to pretend
otherwise. Both are credited in `THIRD_PARTY_NOTICES.md`. **No GPL-licensed
source was consulted**, and one unlicensed package was deliberately not
opened.

## What was used

| Reference | License | What was taken |
|---|---|---|
| `black-forest-labs/FLUX.2-klein-4B` config files | Apache 2.0 | Every architectural constant, read out of the model's `config.json` files: the block counts, the head width, the four rotary axes and their base, the encoder's layer count and head width, the autoencoder's widths and its batch-norm epsilon. |
| `huggingface/diffusers` | Apache 2.0 | The reference behaviour. `Flux2Transformer2DModel`, `AutoencoderKLFlux2`, `Flux2KleinPipeline` and its `compute_empirical_mu` define what this port reproduces, and every fixture is dumped from them. That includes the timestep's precision: the reference rounds the sigma to the stream's dtype before scaling it by a thousand and casts the float32 sinusoid back to that dtype before the MLP, and since the audit of 2026-09-05 so does this port, pinned by `timestep_bf16.safetensors`, a fixture dumped with the reference in bfloat16 because the float32 ones cannot see either rounding. |
| `xocialize/flux2-klein-swift` | MIT | The shape of the transformer: modulation computed once and shared across blocks, the single-stream block's fused query-key-value-feed-forward projection, the four-axis rotary layout, and the finding that mlx-swift up to 0.31.6 miscompiles a bf16 split-K matmul on M5-class GPUs at the single block's output shape. |
| `VincentGourbin/flux-2-swift-mlx` | MIT | The schedule with the empirical shift, the autoencoder's encoder and decoder, and how a reference picture is fitted and placed after the image being made. |
| `mflux-community/mflux` | MIT | A third reading of the same architecture in Python, for the places the two Swift ports disagree. No code. |

## What was not

`xocialize/flux2-vae-mlx-swift`, from which the first port takes its
autoencoder decoder, has no license file. It was never opened. The autoencoder
here was written from the second port and from `diffusers`.

`mzbac/qwen.image.swift` and `mzbac/flux.swift` are GPL-3.0 and were never
opened, for the reason the Qwen-Image section gives.

## Where this port departs from its sources, on purpose

Because the fixtures pin the port to `diffusers` rather than to either Swift
port, the places where a port disagrees with the reference show up as failing
tests. Four were found and resolved in the reference's favour:

- **The schedule.** `flux2-klein-swift` bends its sigma ladder with the
  scheduler's published `base_shift` and `max_shift` and starts the ladder at
  `linspace(1, 0.001, N)`. The klein pipeline ignores both numbers: it computes
  its shift from the token count and the step count with fitted constants, and
  starts from `linspace(1, 1/N, N)`. At 1024 pixels and four steps the two
  schedules are not close. `EmpiricalShift` carries the reference's constants
  and `SchedulerTests` pins the ladder.
- **The query-key norm epsilon.** Both `flux2-klein-swift` and `mflux` use
  1e-5. The reference threads the model's `eps`, 1e-6, into every norm.
- **The timestep scale.** `mflux` multiplies the timestep by a thousand only
  when it is at most one. The reference multiplies unconditionally, and so
  does this port.
- **Reference pictures.** `flux2-klein-swift` resizes a reference to the
  output's square. The reference pipeline scales it to at most a megapixel
  keeping its shape and trims each edge to a multiple of sixteen, so the
  reference keeps its own grid; `Flux2ImageFitting` and
  `ReferenceOrderingTests` hold that.

## Shared between the two ports, and what is not

(`Packages/LTX2Kit` shares the same pieces of `ZephraMLX` — the packed loader,
`LayerWeightStream`, `LatentPreview`'s pooling and byte packing, `PixelBuffer` —
and none of the rotary machinery, whose construction differs; its own section
above says so.)

Both ports are written against `diffusers`, so where the reference does the
same thing for both models the Swift is one copy in `ZephraMLX`
(`Packages/ZephraMLXKit`), and the fixtures of each kit pin it through that
copy: `RotaryFrequencies` and its `rotate`, the layer norm (now
`MLXFast.layerNorm` with nothing learned, in both), the packed-weight loader,
the manifest reader, and `PixelBuffer`'s way out to bytes, which rounds as
`(image * 255).round()` does. Four things stay two copies on purpose, because
the references differ:

- **The final norm.** `AdaLayerNormContinuous` chunks scale then shift in
  both, but klein's `norm_out.linear` is bias-free and Qwen-Image's has a bias.
  Two nine-line classes, one per kit, rather than a `bias:` knob.
- **The schedule.** Both walk the same Euler step, `sample + v * (σ_next − σ)`,
  pinned by each kit's `SchedulerTests`. What bends the ladder is not the
  same: klein uses the pipeline's `compute_empirical_mu` (`EmpiricalShift`),
  deliberately not the scheduler config's `base_shift` and `max_shift`, and
  Qwen-Image uses those very fields (`DynamicShift`) plus a static `shift`
  branch klein's config never takes. The two `FlowMatchEulerScheduler`s stay
  in their kits.
- **The rotary compute dtype.** klein's reference rotates in float32 whatever
  the stream is; Qwen-Image's rotates in the stream's own dtype. The shared
  `rotate(_:computeDType:)` takes that as its one argument, `.float32` from
  klein and `x.dtype` from Qwen-Image, so the shared function is the record of
  the difference rather than a place it could be lost.
- **`ReferenceLatents`.** Where an edit enters the ladder and what it enters
  with, in Qwen-Image's kit and in the vendored `ZImageKit`; two copies because
  one lives inside vendored code re-synced against upstream, and the two
  schedules are typed differently. `AGENTS.md`, "Starting from a picture".

## If this ever needs re-checking

The claim to defend is narrower than the Qwen-Image one: every file in
`Packages/Flux2Kit` was written by Zephra from MIT- or Apache-licensed
sources, each credited in `THIRD_PARTY_NOTICES.md`, and nothing in it derives
from a GPL-licensed or unlicensed source. The git history shows each component
landing with its `diffusers` fixture.

# `Packages/LTX2Kit`

## The short version

`Packages/LTX2Kit` is a translation with attribution, the way `Packages/Flux2Kit`
is. The reference implementations are Apache-2.0 — the LTX-2 modules in
`huggingface/diffusers` and the Gemma 4 model in `huggingface/transformers` —
and every fixture in `Tests/LTX2Tests/Fixtures` is dumped from them by
`Tools/dump_reference.py`. Two MLX ports were read as cross-checks and credited
in `THIRD_PARTY_NOTICES.md`; no code was taken from either. **The official
`Lightricks/LTX-2` repository states no license for its code**: it was run to
confirm the audio-free forward and nothing in it was copied. No GPL-licensed
source was consulted.

The weights are not permissively licensed. The LTX-2.x Community License
Agreement (revenue gate, non-compete, derivative terms) is quoted in
`THIRD_PARTY_NOTICES.md` and reproduced there in full; the packed variant
carries the pack's `LICENSE.md`.

## What was used

| Reference | License | What was taken |
|---|---|---|
| `mlx-community/ltx-2.5-mlx` configs and headers | LTX-2.x Community | Every architectural constant and every tensor name: the transformer's 48 blocks, 32 heads of 128, the 9-row block modulation table, the connector's 8 blocks and 128 registers, Gemma 4's 48 layers with eight full-attention layers that share their key and value projection, the decoder's stage plan and per-channel statistics. Lightricks' own repositories are gated and were never fetched. |
| `huggingface/diffusers` | Apache 2.0 | The reference behaviour of the transformer block (`LTX2VideoTransformerBlock`), the audio-video rotary embedding, the text connectors and both halves of the video autoencoder, and every fixture for them; and the first-frame conditioning of `pipeline_ltx2_image2video.py` and `pipeline_ltx2_condition.py` — the per-token timestep, the conditioning mask, and the blend in `x0` space around each step. |
| `huggingface/transformers` | Apache 2.0 | The reference behaviour of `Gemma4TextModel`: the four sandwich norms, `layer_scalar`, the per-head query and key norms, the scale-free value norm, attention scaling of 1, the rotate-half rotary layout with a partial factor on the full-attention layers, and the per-layer-type masks; and every fixture for it. |
| `dgrauet/ltx-2-mlx` | MIT | Read for the pack's key names, its bidirectionally verified decoder stage plan (zeros spatial padding, non-causal), the encoder's stage plan and space-to-depth downsampler, and its block-streaming and decode-tiling design. No code was taken. |
| `xocialize/ltx-2-mlx-swift` | Apache 2.0 | Read for the tokenizer's missing BOS, the front-truncation rule, the float32 aggregate projection, the kernel-compilation warm-up, its measured envelopes, and its re-imposition of a fully held frame after each step. No code was taken. |
| `Lightricks/LTX-2` | unstated | Run, not read for copying: `LTXModel(video, audio=None)` confirmed the video-only forward this port implements, and its `DISTILLED_SIGMA_VALUES` and ancestral sampler constants were checked against diffusers'. |

## What was not

- `Lightricks/LTX-2.5` and `Lightricks/LTX-2.5-Diffusers`: gated; never fetched.
- `xocialize/ltx-2.5-granules` and any other redistribution: not opened.

## Where this port departs from its sources, on purpose

- **Video only.** The transformer runs the official `audio=None` forward: the
  audio stream, the audio-to-video cross-attention and its conditioners are
  omitted from the pack and from the module tree. The video output differs from
  the audio-video model's by the cross-attention term that is gone; fixtures are
  dumped the same way. `LTX2Block` keeps the seam for the audio stream
  (`ROADMAP.md`).
- **The decoder computes in bfloat16**, the dtype the pack ships it in, where
  Zephra's other autoencoders stay float32. The reference decodes in bfloat16;
  parity was measured at 8e-6 in float32 on the doll's-house fixture.
- **The rotary frequency ladder is Double on the CPU** (`frequencies_precision:
  float64` in the pack's config); the outer product with positions is float32,
  as in the reference. Nothing is shared with `ZephraMLX.RotaryFrequencies`,
  whose construction is the geometric ladder klein and Qwen-Image use.
- **The aggregate projection runs float32** with float32 scales left uncast:
  188160 products summed in bfloat16 lose the prompt (the Swift port's finding).
  Every other packed layer's scales are cast to the stream's dtype at load.
- **The tokenizer is our own byte-pair encoder** over the pack's
  `tokenizer.json`: swift-transformers 0.1.24 splits by grapheme cluster and
  turns emoji joined with a zero-width joiner into bytes, and Swift `String`
  keys merge canonically equivalent tokens, so the vocabulary is keyed by UTF-8
  bytes. Ids are pinned against Hugging Face's `tokenizers` for twelve prompts.
- **The first-frame marker is added unconditionally**, as the official pipelines
  do (`_first_frame_keyframes_mask`); diffusers 0.40.0 carries the parameter but
  no way to apply it in `forward`, so the fixture wraps the input projection to
  match the official behaviour.
- **The first frame is encoded as it is.** The reference image-to-video
  pipeline re-compresses the picture through H.264 at CRF 18 before encoding
  it, so the model sees the artefacts it was trained beside. This port skips
  that, as the MLX Swift port does; whether it is worth adding is a
  `ROADMAP.md` item and not a claim either way.
- **The encoder takes the mean and nothing else.** `conv_out` writes 129
  channels, of which the first 128 are the latent's mean and the last is a
  log-variance the reference broadcasts into a diagonal Gaussian. Both official
  pipelines encode with `sample_mode: "argmax"`, so the mean is what is taken
  and the extra channel is dropped rather than sampled from; there is no seeded
  draw here to reproduce.
- **The encoder's statistics are renamed at the door.** The pack calls them
  `_mean_of_means` and `_std_of_means`; mlx-swift's parameter filter drops any
  key beginning with an underscore, so a tree spelling them that way would load
  them, normalise correctly, and then be invisible to `parameters()` — to the
  streams, to anything that walks the tree, and to the key check that exists to
  notice a statistic that never loaded. `LTX2VAEWeights` renames both ways and
  `VAEEncoderWeightKeyTests` pins the rename against the real header.
- **The per-token noise level is two sigmas and a marker**, not a
  `[tokens, rows, dim]` field. The reference embeds each token's own timestep;
  one held frame gives that field exactly two values, so both are computed as
  one batch of two sigmas and chosen per token after the nine-row table is
  split. Choosing before the split would broadcast all nine rows to every
  token — a quarter of a gigabyte a block at 768 x 512 — where row by row each
  result is one activation the block is about to multiply anyway.
- **A fully held frame is re-imposed after the step.** The condition pipeline
  has no blend after the sampler; its image-to-video sibling instead slices the
  held frame out of the sample and never steps it, which at strength 1 is the
  same thing. This port keeps one code path and puts the picture back where the
  mask is exactly 1, so an ancestral step's fresh noise cannot drift a frame
  that was meant to stay. A partially held frame is left stepped, as the
  reference leaves it.
- **No temporal chunking of the decode** yet; at 768 x 512 x 49 the peak
  intermediate is a fraction of a gigabyte, and it matters past about 121
  frames at 1024 (`ROADMAP.md`).
- **No M5 gate**: the stream is bfloat16 on every GPU (see
  `LTX2ActivationPrecision`).

## If this ever needs re-checking

The claim to defend: every file in `Packages/LTX2Kit` was written by Zephra
from Apache-2.0 references, with MIT- and Apache-licensed ports read and
credited, and nothing in it derives from a GPL-licensed or unlicensed source.
The git history shows each component landing with its fixture, and
`WeightKeyCoverageTests` pins the pack's key set against the module trees.

# `Packages/WanKit`

## The short version

`Packages/WanKit` is a clean-room implementation in the sense `Packages/QwenImageKit`
is: written from the release's own configuration files and from the Apache-2.0
reference implementations in `huggingface/diffusers` (the Wan transformer, its
rotary embedding, the Wan autoencoder, the image-to-video pipeline's first-frame
conditioning) and `huggingface/transformers` (the UMT5 encoder), with every
fixture in `Tests/WanTests/Fixtures` dumped from them by `Tools/dump_reference.py`.
**No other port of Wan was read** — not `Wan-Video/Wan2.2`, not a ComfyUI or MLX
port — and no GPL-licensed source was consulted. The one further source is
FastVideo's own Apache-2.0 repository, read for the three timesteps, the
training noise shift and the re-noising rule of its distribution-matching
sampler; no code was taken from it.

The weights are Apache-2.0 throughout: FastVideo's distilled checkpoint, the
Wan 2.2 autoencoder and Google's UMT5-XXL it carries, each recorded in
`THIRD_PARTY_NOTICES.md`.

## What was used

| Reference | License | What was taken |
|---|---|---|
| `FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers` configs and headers | Apache 2.0 | Every architectural constant and every tensor name: the transformer's 30 blocks of 24 heads by 128, its patch of 1 x 2 x 2 and 48 latent channels, UMT5's 24 blocks of 64 heads by 64 with 32 buckets over 128 positions, the autoencoder's 160/256 widths, `[1, 2, 4, 4]` multipliers, temporal downsampling on the last two stages, patch size 2 and the 48 published channel means and deviations. |
| `huggingface/diffusers` | Apache 2.0 | The reference behaviour of `WanTransformer3DModel` (the per-token modulation, the across-heads RMS norm on query and key, the three-axis rotary split of 44/42/42), `AutoencoderKLWan` in its 2.2 residual layout with its causal feature cache and chunked encode and decode, and `WanImageToVideoPipeline`'s `expand_timesteps` conditioning — the first-frame mask, the per-token timestep, the imposition after each step; and every fixture for them. |
| `huggingface/transformers` | Apache 2.0 | The reference behaviour of `UMT5EncoderModel`: the per-block relative-position bias, the bidirectional bucket function, the RMS layer norm, the gated GELU feed-forward, attention scaling of 1, and `T5Tokenizer`'s ids for the tokenizer fixture; and every fixture for it. |
| `hao-ai-lab/FastVideo` | Apache 2.0 | Read for the DMD sampler: timesteps `1000, 757, 522`, the training noise shift of 8, `x0 = x - sigma * v` at the nearest grid sigma, and `(1 - sigma_next) * x0 + sigma_next * noise` between steps. No code was taken. |

## What was not

- `Wan-Video/Wan2.2` and `Wan-Video/Wan2.1`: not opened.
- Any ComfyUI, MLX or other port of Wan: not opened.

## Where this port departs from its sources, on purpose

- **Image-to-video on the distilled weights.** FastWan was distilled
  text-to-video; the first-frame conditioning is the reference pipeline's
  `expand_timesteps` mechanism run with the DMD sampler. The two compose without
  a change to either, and the frame is held exactly; a strength would be a
  different mechanism.
- **The timestep field is embedded once per distinct value** and gathered per
  token (`WanTimestepField`), rather than the reference's `[B, seq, 6, 3072]`
  held across every block; the arithmetic is identical and pinned by the
  per-token fixtures.
- **The time embedder runs in float32** with its output cast to the stream, as
  diffusers keeps it under a bfloat16 load; the head's `scale_shift_table + temb`
  is float32 too. Schedule sigmas are computed in `Double`.
- **The tokenizer is Zephra's own Unigram** (`WanTokenizer`): swift-transformers
  0.1.24 aborts on the vocabulary's canonically equivalent pieces. It follows
  transformers 5.16.1's constructed backend (whitespace split, Metaspace, `</s>`
  appended, no normaliser), and unknown characters become the file's `<unk>`
  (id 3) where transformers' `T5Tokenizer` hard-codes id 2.
- **`prompt_clean` without ftfy**: entities are unescaped from a table of
  common names and whitespace collapsed; ftfy's mojibake repair is not ported.
- **A frame count off the `1 + 4k` ladder is a precondition**, where the
  reference drops the trailing partial chunk; the catalog clamps before it.
- **The decoder returns channels-last pixels** and clamps them, as
  `LTX2VideoDecoder` does; `clip_output` is not a constructor argument in
  diffusers 0.40.0.
- **Only the 2.2 residual autoencoder layout** is ported: `is_residual: false`,
  `attn_scales`, tiling, slicing and sampling from the distribution are not.
- **No M5 gate**: the stream is bfloat16 on every GPU (`WanActivationPrecision`).

## If this ever needs re-checking

The claim to defend: every file in `Packages/WanKit` was written by Zephra from
Apache-2.0 references and the release's own configs, and nothing in it derives
from another port. The git history shows each component landing with its
fixture, and the three `*WeightKeyTests` suites pin the release's key sets
against the module trees, tensor for tensor.
