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
| `versions.json` | every dumper | nothing; it is the record |

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

The dumpers that write nothing yet — `dump_text_encoder.py`, `dump_vision.py`, `dump_vae.py` —
landed with the kit's skeleton so the seven live in one place. Each states in its docstring what
it pins and which suite will read it; their doll's-house widths are settled by the step that
adds that suite.
