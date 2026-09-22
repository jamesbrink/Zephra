# Provenance of Zephra's own model ports

Zephra may ship commercially, so where each of its own model implementations
came from is a legal question and not only a technical one. This file records
the answers while they are still checkable. `Packages/QwenImage21Kit` and
`Packages/WanKit` are clean-room ports; `Packages/Flux2Kit` and
`Packages/LTX2Kit` are translations with attribution. The claims are different, and each section says which it is
making.

# `Packages/QwenImage21Kit`

## The short version

`Packages/QwenImage21Kit` is a clean-room implementation. It was written from
Qwen-Image 2.1's own published configuration files and from the Apache-2.0
`diffusers` and `transformers` references. **No code was read from or copied
out of `mzbac/qwen.image.swift`, or out of any other Swift or MLX port of this
model.**

**This section is a summary. The kit keeps its own
`Packages/QwenImage21Kit/PROVENANCE.md`**, which is the longer file and the
authoritative one: it lists every source read, every source deliberately not
read, and each of the port's two dozen deliberate departures with the
measurement behind it. What is here is the part a reader of this file needs
without opening that one.

## Why that mattered

`mzbac/qwen.image.swift` is the obvious starting point: it is by the same
author as the `zimage.swift` Zephra already vendors, and it already runs a
Qwen-Image on mlx-swift. It is **GPL-3.0**, and its README says so plainly —
"Commercial usage is allowed as long as your downstream distribution also
complies with GPLv3". Copying from it, or deriving from it, would make Zephra a
GPLv3 work and require publishing Zephra's source. That forecloses an option
`AGENTS.md` deliberately keeps open, so the repository was never opened, and
the same rule was applied to every other port of 2.1.

The **weights** are a separate question from the code, and 2.1 is the one model
in the catalog where the two answers differ. The port is Zephra's own and is
covered by Zephra's own license; the weights are under the Qwen RESEARCH
LICENSE AGREEMENT, which permits research and evaluation only.
`THIRD_PARTY_NOTICES.md` carries that license whole and is the disclosure.

## What was used instead

| Reference | License | What was taken |
|---|---|---|
| `Qwen/Qwen-Image-2.1` config files | Qwen Research License (the weights; the configs were read, not redistributed) | Every architectural constant: 32 transformer blocks, 32 heads at 128, hidden 4096, `mlp_ratio` 3, `axes_dims_rope` `[16, 56, 56]`, `patch_size` 1, the autoencoder's `z_dim` 64 and spatial factor 16, the scheduler's shift parameters, the text encoder's 36 layers and `rope_theta` 5e6, the vision tower's depth 27 and its DeepStack indexes. Read out of the shipped `config.json` files rather than from prose about them. |
| `huggingface/diffusers` at commit `6256aa7666cedd47443adc8f82da9a10e110b09c` | Apache 2.0 | The reference behaviour. `QwenImage21Pipeline`, `QwenImage21Transformer2DModel`, `AutoencoderKLQwenImage21` and `FlowMatchEulerDiscreteScheduler` define what this port must reproduce. |
| `huggingface/transformers` 5.17.0 | Apache 2.0 | `Qwen3VLForConditionalGeneration` and the text and vision models under it, which are the text encoder. |

## How the boundary was kept honest

Behaviour was pinned by comparison with `diffusers` and `transformers`, not
with another Swift port. `Packages/QwenImage21Kit/Tools/` holds eight dumpers
that run the Python reference and write tensors into
`Tests/QwenImage21Tests/Fixtures`; the Swift suites assert against those.
`WeightKeyCoverageTests` claims every published tensor against the module trees
— the transformer's 297 and the autoencoder's 238 among them — so a key the
port does not read is named rather than assumed.

Past the per-component fixtures there is an **end-to-end parity suite**.
`PipelineParityTests` loads the whole 33 GB release streamed, takes the
starting noise the reference drew — an MLX key and a `torch.Generator` are
different algorithms, so the same seed is a different picture and only shared
noise is comparable — walks a short ladder and compares the finished latent:
0.87% mean absolute difference against the latent's own magnitude, Pearson
0.99996, and 0.70 of 255 mean byte difference on the decoded picture. That is
the test that says this port makes the reference's picture rather than a
plausible one. It is also the second place this kit departs from the
repository's "no test loads model weights" rule, the first being five
autoencoder suites that read the release's 1.35 GB `vae/*.safetensors`; both
departures are stated in the kit's own file.

## The fixture pins, which differ from the other kits'

`diffusers` is read at a **commit** rather than a release, and `transformers`
at **5.17.0**, where `Flux2Kit`, `LTX2Kit` and `WanKit` pin `diffusers` 0.40.0
and `transformers` 5.16.1. 2.1 landed after 0.40.0 was cut, and Qwen3-VL does
not exist before transformers 5.17. The divergence is deliberate, it is
recorded in `Tests/QwenImage21Tests/Fixtures/README.md` beside the fixtures it
explains and in that directory's `versions.json`, and it is the first thing to
check if a later run of the dumpers produces different tensors.

## Deliberate departures, in short

The kit's own `PROVENANCE.md` states each with its measurement. The ones that
change what a reader of this file would otherwise assume:

- **The autoencoder has no frame axis.** `AutoencoderKLQwenImage21` is a video
  autoencoder specialised to one frame, so `QwenImage21CausalConv` subclasses
  `nn.Conv2d` and the six `time_conv` modules are **never built**; their twelve
  tensors are dropped at load and claimed by name in the coverage test, so the
  count has no hole in it. The two parameter-free temporal shortcuts are *not*
  dropped, because for a single frame they are not no-ops.
- **Colour under a fully transparent pixel is not carried.** Measured on the
  published autoencoder: the opaque half of a round-tripped RGBA picture comes
  back at 38 to 49 dB a channel and the alpha at 51, while the fully
  transparent half's colour comes back at 4 to 8. That is the model behaving
  correctly, and it is written down because it looks exactly like a broken
  port.
- **The prefix cache is always on**, which is the reference's own default. The
  reference's docstring says the flag does not reproduce a picture bit for bit
  in reduced precision, so offering it would mean recording which setting made
  every picture, or the same seed would mean two pictures.
- **A reference picture is resampled by Core Graphics, not by PIL's lanczos.**
  The fit lands on the reference's own size, pinned by `ImageFittingTests`, but
  the kernel differs, so a conditioned picture is one resample away from what
  `diffusers` would have made. Core Graphics also has no straight-alpha
  context, so the draw is premultiplied and un-premultiplied afterwards.
- **The tiled decode is a coarser approximation here** than in the other
  families: four nearest-neighbour doublings, each followed by a 3 x 3
  convolution, reach further than `TiledDecode`'s quarter-tile overlap covers.
  `TiledDecodeTests` carries the curve — 12 cells is 24 dB, 8 cells is 17 — so
  the backend's tile is chosen against measurements rather than by habit, and
  `QwenImage21RequestMapper` floors it at 12.
- **The text encoder's final norm and `lm_head` are neither built nor packed**,
  because the pipeline takes a hidden state out of the layer stack and never
  reaches a logit. The **vision tower is** built, loaded and packed, unlike the
  tower of the model this replaced, since it is what reads a reference picture.

## If this ever needs re-checking

The claim to defend is narrow: no file in `Packages/QwenImage21Kit` was copied
from or derived from a GPL-licensed source. The branch's commit history shows
the port being built component by component, each landing with its `diffusers`
fixture in the same commit or the one after it. The claim about the *weights*
is a different one and lives in `THIRD_PARTY_NOTICES.md`.

# `Packages/Flux2Kit`

## The short version

`Packages/Flux2Kit` is a translation, not a clean-room port. Two MIT-licensed
Swift implementations of FLUX.2 klein exist, and MIT permits translating them
with attribution, whatever the result is licensed under, so there was no reason
to pretend otherwise. Both are credited in `THIRD_PARTY_NOTICES.md`. **No
GPL-licensed source was consulted**, and one unlicensed package was
deliberately not opened.

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

(`Packages/LTX2Kit`, `Packages/WanKit` and `Packages/QwenImage21Kit` share the
same pieces of `ZephraMLX` — the packed loader, `LayerWeightStream`,
`LatentPreview`'s pooling and byte packing, `PixelBuffer` — and none of the
rotary machinery, whose construction differs; their own sections say so.)

Every kit here is written against `diffusers`, so where the reference does the
same thing for two models the Swift is one copy in `ZephraMLX`
(`Packages/ZephraMLXKit`), and the fixtures of each kit pin it through that
copy: `RotaryFrequencies` and its `rotate`, the layer norm (now
`MLXFast.layerNorm` with nothing learned, in both), the packed-weight loader,
the manifest reader, and `PixelBuffer`'s way out to bytes, which rounds as
`(image * 255).round()` does. Four things stay two copies on purpose, because
the references differ:

- **The final norm.** `AdaLayerNormContinuous` chunks scale then shift, and
  klein's `norm_out.linear` is bias-free. It stays a nine-line class in the kit
  rather than a `bias:` knob in the shared code, because the reference makes
  that choice per model.
- **The schedule.** Every kit walks the same Euler step,
  `sample + v * (σ_next − σ)`, pinned by its own `SchedulerTests`. What bends
  the ladder is not the same: klein uses the pipeline's `compute_empirical_mu`
  (`EmpiricalShift`), deliberately not the scheduler config's `base_shift` and
  `max_shift`, while `QwenImage21Schedule` uses those very fields with the
  release's exponential `time_shift_type` and its `shift_terminal` stretch. The
  `FlowMatchEulerScheduler`s stay in their kits.
- **The rotary compute dtype.** klein's reference rotates in float32 whatever
  the stream is. The shared `rotate(_:computeDType:)` takes that as its one
  argument, `.float32` from klein, so the shared function is the record of the
  difference rather than a place it could be lost; `QwenImage21Rope` is its own
  file entirely, since 2.1 rotates interleaved pairs rather than halves.

## If this ever needs re-checking

The claim to defend is narrower than the Qwen-Image 2.1 one: every file in
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
| `huggingface/diffusers` | Apache 2.0 | The reference behaviour of the transformer block (`LTX2VideoTransformerBlock`, both lanes and the cross-modal attentions), the audio-video rotary embedding, the text connectors, both halves of the video autoencoder, the audio autoencoder's decoder (`autoencoder_kl_ltx2_audio.py`) and the vocoder (`pipelines/ltx2/vocoder.py`, BigVGAN-v2 with its bandwidth extender), and every fixture for them; and the first-frame and multi-frame conditioning of `pipeline_ltx2_image2video.py` and `pipeline_ltx2_condition.py` — the per-token timestep, the conditioning mask, the blend in `x0` space around each step, and the audio re-noised at the second stage. NVIDIA's BigVGAN repository was not read. |
| `huggingface/transformers` | Apache 2.0 | The reference behaviour of `Gemma4TextModel`: the four sandwich norms, `layer_scalar`, the per-head query and key norms, the scale-free value norm, attention scaling of 1, the rotate-half rotary layout with a partial factor on the full-attention layers, and the per-layer-type masks; and every fixture for it. |
| `dgrauet/ltx-2-mlx` | MIT | Read for the pack's key names, its bidirectionally verified decoder stage plan (zeros spatial padding, non-causal), the encoder's stage plan and space-to-depth downsampler, and its block-streaming and decode-tiling design. No code was taken. |
| `xocialize/ltx-2-mlx-swift` | Apache 2.0 | Read for the tokenizer's missing BOS, the front-truncation rule, the float32 aggregate projection, the kernel-compilation warm-up, its measured envelopes, and its re-imposition of a fully held frame after each step. No code was taken. |
| `Lightricks/LTX-2` | unstated | Run, not read for copying: `LTXModel(video, audio=None)` confirmed the video-only forward this port implements, and its `DISTILLED_SIGMA_VALUES` and ancestral sampler constants were checked against diffusers'. |

## What was not

- `Lightricks/LTX-2.5` and `Lightricks/LTX-2.5-Diffusers`: gated; never fetched.
- `xocialize/ltx-2.5-granules` and any other redistribution: not opened.

## Where this port departs from its sources, on purpose

- **Two forwards from one tree.** The video-only entry runs the official
  `audio=None` forward: the audio stream, the audio-to-video cross-attention
  and its conditioners are omitted from the pack and from the module tree, and
  the video output differs from the audio-video model's by the cross-attention
  term that is gone. The entry with sound runs the whole model; its fixtures
  are dumped with `isolate_modalities=False`.
- **The audio autoencoder's decoder only.** Nothing conditions audio, so the
  encoder is neither ported nor packed (`audioEncoderOmitted`); the reference
  loads both halves.
- **Audio in float32 throughout**: the latents, the decoder and the vocoder,
  where the reference runs the decoder in the transformer's dtype. Parity was
  measured in float32 on doll's-house fixtures.
- **The vocoder's depthwise filters are single-channel convolutions.** The
  anti-aliased activations' stored 12-tap filters are applied per channel by
  folding to `[B*C, T, 1]`, since mlx-swift's convolutions take no groups;
  the arithmetic is the reference's.
- **The audio's own noise keys.** The reference draws the audio latents and
  their re-noising from the generator in sequence with the video's; here the
  audio's first latent is `seed + 30000`, its per-step re-noising `seed +
  50000` and its second-stage re-noising `seed + 40000`, so the video's draws
  are the same with or without the lane.
- **A partly held frame steps on scaled sigmas.** A held token's ancestral
  Euler step uses the sigmas scaled by `1 - strength`, matching the per-token
  noise level the transformer was told; the reference's sampler takes the
  scalar. Without this a partial hold (strength above zero) fills the held
  frames with noise at the seam.
- **The decoder computes in bfloat16**, the dtype the pack ships it in, where
  Zephra's other autoencoders stay float32. The reference decodes in bfloat16;
  parity was measured at 8e-6 in float32 on the doll's-house fixture.
- **The rotary frequency ladder is Double on the CPU** (`frequencies_precision:
  float64` in the pack's config); the outer product with positions is float32,
  as in the reference. Nothing is shared with `ZephraMLX.RotaryFrequencies`,
  whose construction is the geometric ladder klein uses.
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

`Packages/WanKit` is a clean-room implementation in the sense
`Packages/QwenImage21Kit` is: written from the release's own configuration files and from the Apache-2.0
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
- **The autoencoder runs in bfloat16**, cast at load from the release's float32,
  and each causal 3-D convolution runs as its temporal taps of 2-D convolutions
  one output frame at a time: the same arithmetic in another order and half the
  bytes, for a decode that was 38 s and 25 GB of a 62 s clip in float32 and is
  15 s and 15 GB. The fixtures pin the float32 path; the bfloat16 picture was
  checked by eye (`BENCHMARKS.md`).
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
