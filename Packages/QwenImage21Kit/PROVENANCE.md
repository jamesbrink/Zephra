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
