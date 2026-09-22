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
