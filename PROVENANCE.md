# Provenance of Zephra's own model ports

Zephra may ship commercially, so where each of its own model implementations
came from is a legal question and not only a technical one. This file records
the answers while they are still checkable. `Packages/QwenImageKit` is a
clean-room port; `Packages/Flux2Kit` is a translation with attribution. The
two claims are different, and each section says which it is making.

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
