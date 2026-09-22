# QwenImage21Kit fixtures

Everything here was written by `Tools/dump_reference.py` (or one of the seven dumpers beside
it, each runnable on its own) and is a claim about what the reference implementation does. A
Swift suite that loads a fixture is checking this port against that, rather than against its own
idea of the architecture. Regenerate with:

```
QWEN_IMAGE_21_SNAPSHOT=/path/to/Qwen-Image-2.1 uv run Tools/dump_reference.py
```

`versions.json` records what the last run actually installed, and it is the file to look at
before believing a fixture.

## The pins here are not the other three kits' pins

`QwenImageKit`, `Flux2Kit` and `LTX2Kit` pin `diffusers==0.40.0` and `transformers==5.16.1`.
This kit pins:

- **diffusers from git**, at commit `6256aa7666cedd47443adc8f82da9a10e110b09c`. Qwen-Image 2.1
  landed in diffusers after 0.40.0 was cut, so there is no release on PyPI that carries
  `QwenImage21Pipeline` at all. The commit is the one the port was read at; `versions.json`
  records it as `0.41.0.dev0`, which is what the working tree called itself, and the commit
  above is the real identity.
- **`transformers==5.17.0`**. The text encoder is Qwen3-VL, which the model card requires
  5.17 or newer for; 5.16.1 has no `qwen3_vl` at all.

Both differences are one-way: nothing here is regenerated when the other kits' pins move, and
moving these does not move theirs. A bump on this side means regenerating every fixture in this
directory in the same commit, and saying so in the commit message.

## What is here

| file | written by | read by |
| --- | --- | --- |
| `scheduler.safetensors` | `dump_scheduler.py` | `ScheduleTests` |
| `tokenizer_ids.json` | `dump_tokenizer.py` | `TokenizerTests` |
| `rope.safetensors` | `dump_rope.py` | `RopeTests`, `JointLayoutTests` |
| `joint_layout.safetensors` | `dump_rope.py` | `JointLayoutTests` |
| `segments.safetensors` | `dump_rope.py` | `AttentionSegmentsTests` |
| `modulation.safetensors` | `dump_transformer.py` | `ModulationTests` |
| `transformer_block.safetensors` | `dump_transformer.py` | `TransformerParityTests`, `KVCacheTests` |
| `transformer_model.safetensors` | `dump_transformer.py` | `TransformerParityTests`, `KVCacheTests` |
| `vae.safetensors` | `dump_vae.py` | the autoencoder suites, on any Mac |
| `vae_real.safetensors` | `dump_vae.py` | the autoencoder suites, with a release |
| `text_encoder.safetensors` | `dump_text_encoder.py` | `Qwen3VLLanguageModelTests`, `Qwen3VLRotaryTests` |
| `vision.safetensors` | `dump_vision.py` | `VisionTowerTests`, `VisionPositionTests`, `DeepStackTests`, `ImagePreprocessingTests`, `PromptEncoderTests` |
| `pipeline.safetensors`, `pipeline.json` | `dump_pipeline.py` | `PipelineParityTests` |
| `pipeline_reference.safetensors`, `.json`, `.png` | `dump_pipeline_reference.py` | `PipelineReferenceParityTests` |
| `versions.json` | every dumper | nothing; it is the record |

`pipeline.safetensors` is the whole reference pipeline run end to end, and it is the only
fixture here that needed the release loaded in Python. Two steps at 256 square — 16 by 16
latent cells, 256 target tokens — over one short prompt, and it holds four things: the packed
latent the reference **drew** (`noise`), the latent it finished on (`latents`), the RGBA bytes
it decoded that to (`pixels`), and the sigma ladder it walked (`sigmas`). `pipeline.json` says
what was asked for, so the Swift side cannot drift from it.

The noise is in the file because `MLXRandom` is not a `torch.Generator`: the same seed is a
different draw, so the Swift run is handed the reference's own noise through
`QwenImage21Request.noise` and the two loops walk one ladder from one place. Without that there
is no tolerance on a picture that means anything. `PROVENANCE.md` states it.

`pipeline_reference.safetensors` is the same run with a condition picture in it, which is the
half of 2.1 the first fixture cannot reach: the picture goes through the vision tower as
context *and* through the autoencoder as latent tokens prepended to the noise, and a port that
showed the tower a picture the autoencoder never saw would still make a plausible picture from
the prompt alone. Beside `noise`, `latents` and `pixels` it carries `condition`, the picture's
packed condition latents `[1, 4096, 64]` (float32, a megabyte), which `ConditionLatentParityTests`
compares with the autoencoder alone. The whole run is `mps` bfloat16 except that the dumper
runs the autoencoder's `QwenImage21AvgDown3D` fold a band of rows at a time: whole, `mps`
returns zeros from it at this size, and the first dump of this fixture recorded exactly that
(`PROVENANCE.md`).

`pipeline_reference.png` (37 KB) is that picture, committed at **1024 square, which is the size
the pipeline would have resized it to** — `calculate_dimensions(1024², 1)`. That is the whole
reason for its size: the reference resizes a condition image with PIL's lanczos and
`QwenImage21ReferencePicture` fits it through Core Graphics at `.high`, and those are different
kernels, so a picture committed at any other size would put the two runs a resample apart
before the model saw anything. At the fitted size both are identities — PIL's `resize` returns
a copy when the size already matches, and a Core Graphics draw into a bitmap of the picture's
own size is a copy too — and the dumper refuses to write the fixture if that stops being true.
The picture is a gradient with a seeded 32-pixel block overlay (a pure gradient is separable in
both axes, so a port that transposed it would reproduce it exactly) and a hard alpha edge two
thirds across. The colour under the transparent third is **zero** on purpose: Core Graphics has
no straight-alpha context, so the Swift fit draws premultiplied and un-premultiplies, which
loses the colour beneath a fully transparent pixel, and a picture that has none there round
trips exactly. That is the one departure this fixture deliberately does not measure, because it
could not measure it honestly.

`scheduler.safetensors` holds seven ladders as `steps<N>.tokens<M>.{sigmas,timesteps,mu}`. Two
of the seven are the pipeline's own defaults — 40 steps at 1024 square (4096 latent tokens) and
at 512 square (1024 tokens) — and 40 at 16384 tokens is 2048 square, which is past the config's
`max_image_seq_len` and so pins the extrapolation the reference deliberately does not clamp.
One step is **not** in the set: its ladder is the single sigma 1, so the terminal stretch
divides by zero and the reference returns NaN with a warning. A fixture of NaNs pins nothing,
and `ScheduleTests` checks separately that the port answers something finite there.

`tokenizer_ids.json` holds 25 prompts, both prompt templates with an empty user prompt, the ids
of the rendered system turn, and the derived `_drop_idx`, which is **14** for this checkpoint.
That number is the point of the file: the pipeline throws that many hidden states away before
the transformer sees anything, and a count one out shifts every conditioning vector by a token.
`TokenizerTests` asserts the constant against the real tokenizer's own count rather than
trusting it.

The transformer's three files are all one doll's house — two heads of sixteen, three rotary axes
filling one head, two layers — over three layouts: text-only, one reference image inside the
prompt, and a right-padded prompt, which is the only thing that exercises the joint key-valid
mask. `transformer_block.safetensors` and `transformer_model.safetensors` each carry a cached
group beside their prefill: the same step run from a prefix cache and run fresh over the whole
sequence, which is what `KVCacheTests` compares.

`dump_vae.py` writes both, because they answer two different questions.

`vae.safetensors` (511 KB) is a **doll's house**: a configuration small enough to commit its
weights beside its activations, so the architecture is pinned on a Mac with no 33 GB release
anywhere near it. Its `dim_mult` and `temperal_downsample` are chosen so every shape the real
tree takes appears once — a stage that folds time and one that does not, a stage that neither
folds nor resizes, an `upsample3d` and an `upsample2d`, and residual blocks with and without a
`conv_shortcut`. It carries the model's own `model.*` tensors, one encode, one decode, and the
decoder's stages.

`vae_real.safetensors` (3.5 MB) is the **published autoencoder's own answers**. It is only
337.74 M parameters, so unlike the transformer and the text encoder it can simply be run here,
and a doll's house cannot catch a scale read off the wrong axis of a 96-channel stage. It holds
a whole encode of a 64 x 64 RGBA picture, a whole decode of a fixed 4 x 4 x 64 latent, the
config's `latents_mean` and `latents_std`, and the output of every stage of both halves over a
smaller input, so a parity failure bisects to one block rather than to "the autoencoder". The
suites that read it are gated on `SnapshotUnderTest.qwenImage21.hasRelease`, because they load
the release's 1.35 GB of weights; `PROVENANCE.md` states that departure.

Both pictures carry a **hard alpha edge** down the middle rather than only noise. Noise alone
would not say whether the fourth channel is carried or quietly replaced with an opaque one: an
autoencoder that dropped alpha would still return something noise-shaped.
`text_encoder.safetensors` holds a four-layer, 32-wide Qwen3-VL decoder — its weights, a fixed
token run and the hidden state at the last layer **before** the stack's final norm, dumped
under the same forward hook the pipeline installs, with the unhooked (normalised) answer beside
it so a Swift suite can show the two differ. It also holds the interleaved MRoPE tables at
**both** widths: the doll's `head_dim` 8 over section `[2, 1, 1]`, and the published
`head_dim` 128 over `[24, 20, 20]`, each over a text-only run of positions and over a
three-axis run with a picture in it. The published tables cost no weights at all — the rotary
is decided by a configuration — and they are what say which half-dim reads which axis.

`vision.safetensors` holds the doll's-house tower (four blocks, three DeepStack taps), the
whole doll's-house `Qwen3VLModel` over one picture under the same hook (so the slots, the
three-axis positions and the DeepStack injections are all in one hidden state), the tower's
inverse frequencies and theta at both widths, the position table's interpolation taps and the
tower rotary's tables for four grids (the last 64 by 64, a 1024-square reference), `smart_resize` at the **published** bounds for six
shapes, the processor's own block-major patch tensor, and PIL's alpha-over-white blend. The
theta is the point of the rope entries: it is in no shipped config and in none of the 750
published tensors, and 10,000 is what transformers supplies.

