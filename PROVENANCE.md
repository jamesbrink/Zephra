# Provenance of `Packages/QwenImageKit`

Zephra may ship commercially, so where its Qwen-Image implementation came from
is a legal question and not only a technical one. This file records the answer
while it is still checkable.

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
| `mlx-gen` | MIT | One published finding, not code: that four-bit modulation layers cost coherent structure in this architecture. It is why `QwenImageQuantizationPlan` holds them at eight bits. |
| `Packages/ZImageKit` (vendored) | MIT | One approach, not a file: assembling a byte-level BPE tokenizer from `vocab.json` and `merges.txt` when a snapshot ships no `tokenizer.json`. Noted in `THIRD_PARTY_NOTICES.md` and in the source. |

## How the boundary was kept honest

Behaviour was pinned by comparison with `diffusers`, not by comparison with
another Swift port. `Packages/QwenImageKit/Tools/dump_reference.py` runs the
Python reference and writes tensors to
`Packages/QwenImageKit/Tests/QwenImageTests/Fixtures`; the Swift suites assert
against those. Every component has such a fixture — rope, scheduler, latent
packing, text encoder, one MMDiT block, the whole transformer, VAE decode — so
"does this match the reference" is a question the test suite answers rather
than a claim in a commit message.

The structural differences from a port that had been derived are visible in
the source and are the natural consequence of writing from `diffusers`:

- The 3-D causal autoencoder is implemented in two dimensions. A single frame
  makes the other two temporal kernel slices multiply nothing but zero
  padding, so dropping them is exact, and it removes `Conv3d` and every 5-D
  tensor from the decode. `QwenImageVAEWeights` slices the checkpoint
  accordingly.
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
`diffusers` fixture in the same commit.
