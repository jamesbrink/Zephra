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
`VAEWeightKeyCoverageTests` claims all 238 published keys: 226 as parameters of the tree and
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

### `QwenImage21PixelBuffer` is temporary

It is `ZephraMLX.PixelBuffer` with the alpha channel carried rather than invented. The shared
one appends an opaque alpha column unconditionally, which over four channels would make five,
so 2.1 cannot use it at all. When the shared buffer learns four channels -- straight alpha,
`CGImageAlphaInfo.last`, the same rounding -- this file is deleted and the calls move over;
`PixelBufferTests` pins the same bytes either way, so the swap is checked rather than assumed.
