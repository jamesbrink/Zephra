# QwenImage21Kit provenance

Where this port came from, and every place it deliberately does something the reference does
not. Keep it true: the clean-room claim rests on the fixtures, and the departures below are the
only differences that are meant to be there.

## Sources read

- `huggingface/diffusers` at commit `6256aa7666cedd47443adc8f82da9a10e110b09c`, Apache-2.0:
  `QwenImage21Pipeline`, `QwenImage21Transformer2DModel`, `AutoencoderKLQwenImage21`,
  `FlowMatchEulerDiscreteScheduler`.
- `huggingface/transformers` 5.17.0, Apache-2.0: `Qwen3VLForConditionalGeneration` and the
  Qwen3-VL text and vision models under it.
- The release's own configuration files, under `Qwen/Qwen-Image-2.1`.

## Sources deliberately not read

- `mzbac/qwen.image.swift` — GPL-3.0. No file, no line, no naming scheme.
- Any other Swift or MLX port of Qwen-Image or Qwen-Image 2.1.

## Departures

### The terminal stretch of a one-step ladder

The reference's `stretch_shift_to_terminal` divides by `(1 - sigmas[-1]) / (1 - shift_terminal)`.
A one-step ladder is the single sigma 1, so that scale factor is zero, and every sigma comes
back NaN with a `RuntimeWarning`. `QwenImage21Schedule` leaves the ladder alone in that one
case instead, giving `[1, 0]`. A NaN sigma is a run that produces nothing at all, and no
picture was ever made at one step; `ScheduleTests` pins both the reference's ladders and this
one departure.

### The fixture pins

`diffusers` comes from a git commit rather than a release, and `transformers` is 5.17.0, where
the other three kits pin 0.40.0 and 5.16.1. 2.1 landed after 0.40.0 was cut and Qwen3-VL needs
5.17. `Tests/QwenImage21Tests/Fixtures/README.md` states it beside the fixtures it explains.

### The rotary table is computed, not looked up

`QwenImage21Rope` builds the reference's 9216-row frequency table nowhere. The reference holds
positions 0 to 8191 followed by -1024 to -1, so a negative position indexes the tail by Python's
wrap; MLX has no such wrap, and the angle at row `p` is exactly `p * theta^(-2i/dim)` whatever
the sign of `p`. This port computes that angle from the position in doubles and rounds once,
which is the same number, needs no wrap, and has no bound at 8191. `RopeTests` pins all three
layouts against the reference's own tables and checks the negative rows separately.

### The prefix cache is held head-major

The reference stores a layer's prefix keys and values as `[batch, tokens, heads, headDim]` and
transposes on every step. `QwenImage21KVLayerCache` stores them transposed — the attention
kernel's own layout — which is the same numbers, saves a transpose per layer per step, and is
what makes the stored slice a **copy**: `MLX.contiguous` over a head-major slice has to copy,
where a contiguous prefix view would share the whole prefill's buffer and pin gigabytes for the
length of the run. `KVCacheTests` compares the held keys against the reference's transposed.

### The joint sequence is one gather

The reference builds the joint sequence with `repeat_interleave` and then a masked assignment
(`joint_hidden_states[:, image_pad_mask] = hidden_states`). This port precomputes, per joint
position, where it reads from in `[encoder tokens ++ latent tokens]`
(`QwenImage21JointLayout.sourceIndices`) and does the whole of it as one `take` along the token
axis. Same sequence, one operation, and no scatter.

### The block-causal mask is never built

Both of the reference's processors are implemented as one: the segment decomposition, with
MLX's own causal mask mode standing in for a text run's `[ones | tril]`, since MLX offsets its
triangle by `keys - queries` and so aligns it to the bottom right exactly as that concatenation
does. Nothing here builds a `BlockMask` or a dense score-sized mask, and a mask array appears at
all only for a right-padded prompt. `AttentionSegmentsTests` checks that the keys the segments
allow are exactly the keys `(q >= kv) or same image block` allows.

### The timestep ladder is a handful of last places out

The reference's sinusoid frequencies are `torch.exp` over a float32 tensor.
`QwenImage21TimestepEmbedding.ladder` builds the exponent in float32, as the reference does, but
takes the exponential in double and rounds once, which is correctly rounded where float32 `exp`
is not always. A few of the 128 entries therefore differ by one unit in the last place, the
timestep multiplies them by up to 1000, and the projection agrees with the reference to 2.9e-5
rather than to 1e-6. `ModulationTests` states the margin.

### The autoencoder has no frame axis, and six of its convolutions are never built

`AutoencoderKLQwenImage21` is Wan's video autoencoder specialised to a single frame.
`QwenImage21CausalConv3d` **subclasses `nn.Conv2d`**, squeezes the frame axis away, pads
explicitly with the symmetric padding the convolution was configured with, runs it with
`padding=(0, 0)` and puts the axis back; every stored kernel is 4-D. `_encode` runs one chunk
and `_decode` one, with `first_chunk=True`.

So this port drops the frame axis entirely -- activations are `[batch, height, width,
channels]` -- and **does not build the six `time_conv` modules**, whose twelve tensors
`QwenImage21VAEWeights.sanitized` drops at load. They are unreachable rather than approximated:
both are guarded on what the feature cache holds at their index, and on the only chunk a still
image has, the encoder's cache holds `None` there (the branch taken records the activation and
moves on) and the decoder's the sentinel `"Rep"` (the branch taken replaces it). The
convolution is reached from the second chunk onward and there is never a second chunk.
`WeightKeyCoverageTests+VAE` claims all 238 published keys: 226 as parameters of the tree and
those twelve by name, so the count has no hole in it.

The temporal half of the two parameter-free shortcuts is **not** dropped, because for one frame
it is not a no-op. `QwenImage21AvgDown` still zero-pads the front of the time axis, so at the
three encoder stages that fold time the one real frame pairs with a frame of zeros and half of
every group averages to zero; `QwenImage21DupUp` still keeps the last time offset, which at the
decoder stage that halves its width picks out the odd input channels rather than duplicating.
Skipping either would be a different model that still ran.

### Colour under a fully transparent pixel is not carried

Measured on the published autoencoder over a 256 x 256 RGBA picture, round-tripped: the opaque
half comes back at 38 to 49 dB a colour channel and the alpha channel at 51, while the fully
transparent half's colour comes back at 4 to 8 dB. That is the model behaving correctly -- an
RGBA autoencoder spending latent capacity on colour nobody can see would be spending it wrongly
-- and it is written down because it looks exactly like a broken port otherwise.
`AutoencoderRoundTripTests` judges the picture where the picture is visible.

### The tiled decode is a coarser approximation here than in the other families

`ZephraMLX.TiledDecode` overlaps a quarter of the tile. This decoder has four
nearest-neighbour doublings with a 3 x 3 convolution after each, so one latent cell reaches
further into the picture than that overlap covers and a tile decoded on its own is wrong near
its edges over a wider band than the cross-fade repairs. Measured against the untiled decode of
a real 16 x 16 latent: 12 cells is 24 dB, 8 cells is 17 dB, and a tile at or above the latent's
own size is the untiled decode exactly. Over random normal latents -- the worst case there is
-- the mean absolute error on a range of 2 falls from 0.048 at a 6-cell tile to 0.010 at a
24-cell tile. Nothing here is wrong; the tile the backend ships has to be chosen well up that
curve, and `TiledDecodeTests` carries the figures so the choice is made against measurements.

### Two kinds of suite, and five of them load the release's autoencoder weights

`AutoencoderTests`, `AutoencoderStageTests`, `LatentNormalizationTests`, `TiledDecodeTests` and
`AutoencoderRoundTripTests` read `vae/diffusion_pytorch_model.safetensors` -- 1.35 GB, 337.74 M
parameters -- when `SnapshotUnderTest.qwenImage21.hasRelease` says it is there, and skip
otherwise. That is a departure from the repository's "no test loads model weights", taken
deliberately and for this component alone: unlike the transformer and the text encoder this
model is small enough to run in a second, and a doll's house cannot catch a scale read off the
wrong axis of a 96-channel stage or a shortcut that only misbehaves at the published widths.
The doll's-house suites beside them need no release and pin the architecture on any Mac.

### The pixels go out through the shared buffer, which now carries four channels

`QwenImage21PixelBuffer` existed while `ZephraMLX.PixelBuffer` appended an opaque alpha column
unconditionally, which over four channels would have made five. The shared one now takes three
channels or four — straight alpha, `CGImageAlphaInfo.last`, the same rounding — so the kit's
copy and `PixelBufferTests` beside it are **deleted** and both doors, the finished PNG and the
preview frame, call the shared one. `LatentPreviewTests.alphaIsCarried` is what still says the
fourth channel is the picture's own and not an invented 255.

### The text encoder's final norm is not built

The conditioning the transformer reads is the output of decoder layer 35 **before**
`model.language_model.norm`. The reference pipeline reaches that by registering a forward hook
on the norm that hands back its own input, because from transformers 5.0 `hidden_states[-1]`
is otherwise the normalised state. This port implements the hook as "the norm does not exist":
`Qwen3VLLanguageModel` builds `embed_tokens` and 36 layers and stops, and
`Qwen3VLTextWeights.omitted` names `model.language_model.norm.weight` and `lm_head.weight` as
the two published tensors it never loads. `Qwen3VLLanguageModelTests` checks both that the
answer matches the hooked reference and that it is far from the unhooked one;
`WeightKeyCoverageTests+TextEncoder` checks that both omitted tensors really are in the
release, since `tie_word_embeddings` is false and a pack has to exclude `lm_head` explicitly
rather than assume it away.

### The vision tower's rotary theta is written down here

`vision_config` in `text_encoder/config.json` states no `rope_theta` and no `rope_parameters`,
so transformers supplies its own default, and the inverse frequencies it computes live in a
`persistent=False` buffer that is therefore in none of the 750 published tensors. The number is
**10,000** — not the decoder's five million — and `Qwen3VLVisionRotary.theta` is its only
written-down form in this repository. `Tools/dump_vision.py` dumps `rope.real.theta` and
`rope.real.invFreq` from `Qwen3VLVisionRotaryEmbedding` against the release's own vision config,
and `VisionPositionTests` pins the constant against them.

### The prompt is capped at 512 tokens

The reference pipeline caps nothing: `model_max_length` is 262,144 and `encode_prompt` takes
whatever the tokenizer produces. `QwenImage21Tokenizer.encode(_:limit:referenceCount:)` keeps
`dropIndex + 512`, because every prompt token is about half a megabyte of prefix key-value
cache across the 32 transformer blocks and is paid for the whole run. The truncation keeps the
front, which is where somebody says what they want, and a prompt long enough to be cut loses
the template's own five-token tail rather than having it spliced back on, which would make the
ids for a long prompt something the reference never produces for any input.

### The tower's own `smart_resize` is required to be a no-op

The pipeline fits every reference picture to `calculate_dimensions(1024², ratio)` — a multiple
of 32 — before either the tower's copy or the autoencoder's is made, and 32 is exactly
`patch_size * merge_size`, so the tower's own `smart_resize` never moves one.
`Qwen3VLImagePreprocessing.fitted(...)` is that arithmetic, pinned against the reference for six
shapes at the published bounds, and `patches(of:processor:)` **throws**
`Qwen3VLEncodingError.sizeNotFitted` for a picture it would not be a no-op for rather than
resampling it. The alternative is a second bicubic resampler in this kit whose only job is to
disagree with the pipeline's lanczos one.

### The alpha is flattened over white with a rounded float blend

`_get_qwen_prompt_embeds` composites a reference's alpha over white with PIL's `paste` and an
alpha mask, which is integer arithmetic (`MULDIV255`).
`Qwen3VLImagePreprocessing.compositedOverWhite` is a rounded float lerp instead, which agrees
with PIL byte for byte on eight-bit inputs; `ImagePreprocessingTests` checks it against the
reference's own output at tolerance zero. Only the tower's copy is flattened — the autoencoder
keeps all four channels.

### DeepStack's injection layers are a list index, not a configured depth

The tower taps blocks 8, 16 and 24 (`deepstack_visual_indexes`) and the decoder adds those
three outputs after layers **0, 1 and 2**, because the reference's condition is
`layer_idx in range(len(deepstack_visual_embeds))`. The two sets of numbers are unrelated, and
the doll's-house fixture taps tower blocks 1, 2 and 3 precisely so that a port which confused
them fails. `Qwen3VLLanguageModel` counts the layer inside the weight stream's closure for the
same reason klein's encoder counts its taps there: `LayerWeightStream.run` hands back the layer
and not its index.

### The encoder answers one prompt at a time, so the padding mask is nothing

Tokenisation is left-padded as the checkpoint was trained; the valid slice is then extracted
per row and the *embeddings* are right-padded for the transformer (spec C.4). At batch one
there is nothing padded, so `Qwen3VLAttentionMask` is the causal triangle and nothing else, and
`encode_prompt`'s own `if prompt_embeds_mask.all(): prompt_embeds_mask = None` means the
transformer is handed no mask either. A batched encoder would need the left-padding term, and
`Qwen3VLAttentionMask` is the one file that would grow it.

### A picture cannot match `diffusers` bit for bit, because the noise is not torch's

`prepare_latents` draws the starting noise with a `torch.Generator` seeded by the caller.
`QwenImage21Pipeline` draws it with `MLXRandom.normal(_:key:)` over the request's seed, in the
unpacked latent grid, and packs it the way the reference does. The two generators are different
algorithms, so the same seed is a different picture, and no tolerance on a finished image means
anything.

What *is* comparable is a run that starts from the same noise, and that is what
`QwenImage21Request.noise` is for: `Tools/dump_pipeline.py` saves the packed latent it drew and
`PipelineParityTests` hands it straight in, so the Swift loop and the reference loop walk the
same ladder from the same place and their final latents can be compared.

### The prefix cache is always on, and it is part of what a seed means

The reference's `use_kv_cache` defaults to true and its own docstring says the flag does not
reproduce a picture bit for bit in reduced precision: caching makes a decode step attend over a
different sequence layout from the prefill, the two tile differently and land on different
rounding, and 32 blocks over forty steps amplify one unit in the last place into a visibly
different -- equally valid -- sample.

This port does not expose the flag. Every run caches, which is the reference's default, so a
seed means one thing here; a build that offered the choice would have to record which was used
beside every picture, or the same seed would give two pictures.

### One resample, and it is Core Graphics' rather than PIL's

The reference resizes each condition image once, to `calculate_dimensions(output_resolution`
squared`, its own aspect)`, with `PIL_INTERPOLATION["lanczos"]`, and that one copy feeds both
the vision tower and the autoencoder. `QwenImage21ReferencePicture.fitted` is that resize, and
it lands on the same size -- `ImageFittingTests` pins the arithmetic against the reference --
but it draws through Core Graphics at `.high` interpolation, which is a different kernel. A
picture conditioned on a reference is therefore a resample away from the reference's, wherever
the resample changed anything.

Two smaller consequences of using Core Graphics at all. It has no straight-alpha context, so
the draw is premultiplied and un-premultiplied afterwards, which loses the colour under a fully
transparent pixel -- the colour the autoencoder does not carry either, measured above. And the
whole picture goes into the whole bitmap rather than being scaled to cover and centred the way
klein's reference decode does: the fit keeps the aspect to within one 32-pixel step, so there
is nothing to crop, and a matte colour at the edges would be a matte the reference never
applies.

### A reference picture crosses as encoded bytes

`QwenImage21Request.references` is `[Data]` -- PNG, JPEG, anything ImageIO reads -- rather than
an array of pixels. That is the shape `Flux2GenerationRequest.referenceImage` uses and the
shape the engine already holds a reference in, and it puts the decode and the fit at one door:
an `MLXArray` handed in at an arbitrary size would have to be resampled here anyway, and by
then it would have been decoded once already.

### The Euler step is taken in float32 over bfloat16 latents

`FlowMatchEulerDiscreteScheduler.step` upcasts the sample to float32, takes the step there and
casts back to the model output's dtype. `QwenImage21Schedule.step` is the bare formula and the
pipeline does the upcast at the call site, which is the same arithmetic: forty steps of
bfloat16 accumulation drifts visibly in the darkest and lightest parts of a picture, and the
upcast is one multiply-add a step.

### The end-to-end parity suite loads the release's real weights

`PipelineParityTests` is the second place this kit departs from the repository's "no test loads
model weights", and it is the one that says the port makes the reference's picture rather than
a plausible one. It loads the whole 33 GB release -- streamed, so the two layer stacks are read
per step rather than held -- runs the reference's own noise through two steps at 256 square,
and compares both the finished latent and the RGBA bytes it decodes to. Everything else in the
suite runs without a release, in seconds.

What it measures, on halcyon against `Tools/dump_pipeline.py`'s bfloat16 `mps` run: the
finished latent's mean absolute difference is **0.0082** against a mean latent magnitude of
0.943, which is **0.87 per cent**, at a Pearson correlation of **0.99996**; the decoded
picture's mean byte difference is **0.70 on a range of 255**. Both ends run bfloat16
activations over the same weights, so what is left is rounding compounded through 32 blocks and
two steps rather than a difference in the arithmetic. The suite's bounds are two per cent and
two bytes -- a bit over twice each measurement -- and the whole run takes 35 seconds streamed.

### The reference-conditioned parity fixture is committed at the fitted size

`PipelineReferenceParityTests` is the same suite over the other path: one condition picture,
which the model reads twice -- through the vision tower as context and through the autoencoder
as latent tokens prepended to the noise -- from one resize. It is the half `PipelineParityTests`
cannot reach, because a port that showed the tower a picture the autoencoder never saw, or laid
the condition tokens out in the wrong place, would still make a plausible picture from the
prompt alone.

The departure above -- Core Graphics' resample against PIL's lanczos -- is exactly what would
have made that measurement meaningless, so the fixture avoids it rather than absorbing it into
a wider bound. `pipeline_reference.png` is committed at **1024 square**, which is what
`calculate_dimensions(1024`squared`, 1)` answers for a square picture at the default
`output_resolution`, so neither side resamples anything: PIL's `Image.resize` returns a copy
when the size already matches, and a Core Graphics draw into a bitmap of the picture's own size
is a copy too. `Tools/dump_pipeline_reference.py` refuses to write the fixture at any other
size, and the suite's first expectation is that this kit's own fit of those bytes is the very
array the reference read, to the byte. A failure there is a decoder or a colour space; a
failure after it is the port.

The picture's transparent third carries **zero colour**, so the premultiplied round trip
measured above is lossless on it. That is deliberate: the one departure this fixture could not
measure honestly is the one it is built not to measure.

**The fixture was wrong, not the port, and it was `mps`.** The suite was first written
`.disabled`: on halcyon on 2026-09-22 the port landed 99.6 per cent from the reference's
finished latent (Pearson 0.57, 101 bytes a pixel), with the condition latents 76 per cent out
and the picture's own vision tokens 23.5. Walking the real 1024-square run stage by stage
against the reference found **no fault in the port**: in float32 this kit's autoencoder encoder
matches `diffusers` on the CPU to 3e-6 at every one of its stages, and the vision tower matches
`transformers` to 2.8e-5 at its merger, both at the real 64 by 64 grid. What differed was the
reference run itself. `QwenImage21AvgDown3D`, the shortcut around every encoder stage, folds
the frame axis and both spatial offsets into the channel axis through an eight-dimensional
`permute(...).contiguous()`, and torch 2.14's `mps` backend returns **all zeros** from that fold
once the padded tensor passes about 2**24 elements. At a 1024-square picture that is stages 1
and 2 (96 channels at 512 square, 192 at 256), so the `mps` dump silently dropped two of five
shortcuts and recorded condition latents 68 per cent from a correct encode. A dozen lines
against `torch.randn` reproduce it with no model loaded: `mean|cpu| 0.19942, mean|mps| 0.00000`,
identical answers once the tensor is 384 by 128 square. `Tools/dump_pipeline_reference.py` now
runs that fold a band of rows at a time (`fold_in_row_bands`), which is exact against the CPU
and keeps the whole run on `mps` in bfloat16.

What is left is bfloat16, and it is wider than `PipelineParityTests`' because the sequence is:

| measured, halcyon, 2026-09-22 | port against reference |
| --- | --- |
| the fitted picture, the joint layout, the prefix of 4118 | identical |
| condition latents, `[1, 4096, 64]` | **1.06 per cent** (the reference's bfloat16 encoder against this port's float32 one; 68 before the fix) |
| one transformer pass over the reference's own inputs, 4374 tokens | 1.8 per cent, evenly: text 1.7, condition 1.8, target 1.4 |
| two steps over the reference's own text embedding | 2.6 per cent |
| the finished latent, the whole port | **4.7 per cent**, Pearson 0.9988 (99.6 and 0.57 before) |
| the decoded picture | **7.4** bytes a pixel on 255 (101 before) |

The joint sequence is sixteen times the text-to-picture suite's 278 tokens and its attention
sums over sixteen times the keys, which is where one pass's 1.8 per cent comes from; nothing is
concentrated in a block, which is what a mask or a layout fault would look like. The suite's
bounds are therefore its own, a bit under twice each measurement as the other suite's are: 8
per cent and Pearson 0.995 on the latent, 15 bytes on the picture. Against the broken fixture
those read 99.6, 0.57 and 101, so they still separate a working port from one missing an
encoder stage by more than an order of magnitude.

Two suites now pin the real size directly. `ConditionLatentParityTests` loads the autoencoder
alone and compares this kit's condition tokens for the committed picture against the fixture's
`condition` (a megabyte, float32) at 3 per cent and Pearson 0.999: the check that would have
said, in a second, which half was wrong. And `vision.safetensors` now carries the tower's
interpolation taps, patch order and rotary tables at the 64 by 64 grid a 1024-square reference
lands on (2.5 MB), which `VisionPositionTests` reads beside the 6 by 8 and 32 by 32 it read before.

### An opaque picture is written opaque

The reference writes every picture as RGBA, and for an ordinary prompt the fourth channel is
opaque with noise on it: on the first pictures made here every alpha byte landed in 250...255,
none below. This port drops the channel when the lowest alpha is at or above 250 of 255
(`QwenImage21Opacity`), so a landscape is an RGB file and only a picture with a real hole keeps
its alpha. The pixels that are written are the reference's own; what changes is the colour type
of the file, and `PipelineParityTests` compares the decoded pixels, not the PNG bytes.
