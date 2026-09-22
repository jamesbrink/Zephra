# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "torch==2.14.0",
#     "diffusers @ git+https://github.com/huggingface/diffusers@6256aa7666cedd47443adc8f82da9a10e110b09c",
#     "transformers==5.17.0",
#     "tokenizers==0.23.2",
#     "safetensors==0.8.0",
#     "numpy==2.5.2",
#     "pillow",
# ]
# ///
"""`QwenImage21Rope`, `build_token_metadata` and `_qwenimage21_prefix_segments`.

What this pins: the three axes of `axes_dims_rope` — frame, row, column — laid out over a text
run, over one target grid, and over condition grids followed by a target grid, which is where
the frame axis stops being zero and where the row and column axes go negative. Then the joint
sequence's own bookkeeping: the four-fold expansion of every vision-language image slot, the
block ids cut by `img_shapes` rather than by runs of `True`, the target mask and the prefix
length, and the prefix split into the attention segments the non-flex processor runs.

The reference returns one **complex** table of `sum(axes_dim) / 2` entries a token, which is
one angle per rotated pair; the dump stores its real and imaginary parts, which are the cosine
and the sine `ZephraMLX.RotaryFrequencies` holds.

Three layouts, and every block's token count is a multiple of four because one vision-language
image slot stands for four latent tokens:

- `target`: five text tokens then a 3x4 target. The text-to-image case.
- `edit`: text, a 2x4 condition, more text, then the target. The edit case.
- `twoConditions`: two conditions of different shapes before the target, so the frame counter
  has to advance by `max(height, width)` twice and two adjacent blocks stay two blocks.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

# Doll's house: three axes summing to one head of sixteen, which is the real config's shape
# (16 + 56 + 56 = 128) at a size that commits. Theta is the model's own hard-coded 10000.
THETA = 10000
AXES_DIM = [4, 6, 6]

# Each layout is the vision-language image mask as `(is_image, count)` runs, plus the latent
# grids the blocks cover, condition images first and the target last.
LAYOUTS = {
    "target": ([(False, 5), (True, 3)], [(1, 3, 4)]),
    "edit": ([(False, 4), (True, 2), (False, 3), (True, 3)], [(1, 2, 4), (1, 3, 4)]),
    "twoConditions": (
        [(False, 2), (True, 1), (False, 1), (True, 2), (False, 3), (True, 3)],
        [(1, 2, 2), (1, 2, 4), (1, 3, 4)],
    ),
}


def img_mask(runs) -> torch.Tensor:
    """The vision-language mask, `True` at an image slot, as the pipeline hands it over."""
    values = [flag for flag, count in runs for _ in range(count)]
    return torch.tensor(values, dtype=torch.bool)[None]


def dump(out: pathlib.Path) -> None:
    from diffusers.models.transformers.transformer_qwenimage21 import (
        _IMG_TOKENS_PER_SLOT,
        QwenImage21Rope,
        QwenImage21Transformer2DModel,
        _qwenimage21_prefix_segments,
    )

    rope = QwenImage21Rope(theta=THETA, axes_dim=AXES_DIM)
    rows, layout_rows, segment_rows = {}, {}, {}
    for label, (runs, shapes) in LAYOUTS.items():
        mask = img_mask(runs)
        repeats = torch.where(mask, _IMG_TOKENS_PER_SLOT, 1)[0]
        image_pad_mask = torch.repeat_interleave(mask[0], repeats)

        freqs = rope(shapes, image_pad_mask, torch.device("cpu"))
        rows[f"{label}.cos"] = freqs.real.float().contiguous()
        rows[f"{label}.sin"] = freqs.imag.float().contiguous()
        rows[f"{label}.imgMask"] = mask[0].to(torch.int32).contiguous()
        rows[f"{label}.imagePadMask"] = image_pad_mask.to(torch.int32).contiguous()

        image_ids, target_token_mask = QwenImage21Transformer2DModel.build_token_metadata(
            image_pad_mask, shapes
        )
        prefix_len = int((~target_token_mask).sum())
        layout_rows[f"{label}.imageIDs"] = image_ids.to(torch.int32).contiguous()
        layout_rows[f"{label}.targetTokenMask"] = target_token_mask.to(torch.int32).contiguous()
        layout_rows[f"{label}.prefixLength"] = torch.tensor([prefix_len], dtype=torch.int32)

        segments = _qwenimage21_prefix_segments(image_ids, prefix_len)
        segment_rows[f"{label}.segments"] = torch.tensor(
            [[start, end, int(is_text)] for start, end, is_text in segments], dtype=torch.int32
        )

    save_file(rows, str(out / "rope.safetensors"))
    save_file(layout_rows, str(out / "joint_layout.safetensors"))
    save_file(segment_rows, str(out / "segments.safetensors"))
    print(f"rope: {len(rows)} tensors, layout: {len(layout_rows)}, segments: {len(segment_rows)}")


def main() -> None:
    import dump_reference

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=dump_reference.default_out())
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(0)
    dump(arguments.out)


if __name__ == "__main__":
    import sys

    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    main()
