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
"""`QwenImage21Rope`'s tables for the joint sequence's three layouts.

What this pins: the three axes of `axes_dims_rope` — frame, row, column — laid out over the
text run, over one target grid, and over a condition grid followed by a target grid, which is
where the frame axis stops being zero. The port keeps one angle per rotated pair where the
reference repeats each cosine twice, so the dump de-interleaves after asserting the two halves
were equal.

Written with the kit's skeleton so the seven dumpers live in one place; the doll's-house widths
and the exact layouts are settled by the step that adds `RotaryEmbeddingTests`.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

# Doll's house: three axes summing to one head of sixteen, which is the real config's shape
# (16 + 56 + 56 = 128) at a size that commits.
THETA = 2000
AXES_DIM = [4, 6, 6]


def dump(out: pathlib.Path) -> None:
    from diffusers.models.transformers.transformer_qwenimage_21 import QwenImage21Rope

    rope = QwenImage21Rope(theta=THETA, axes_dim=AXES_DIM)
    layouts = {
        # One 3x4 target grid, which is the text-to-image case.
        "target": [(1, 3, 4)],
        # A 2x3 condition grid then a 3x4 target, which is the edit case.
        "edit": [(1, 2, 3), (1, 3, 4)],
        # Two conditions and a target, where the frame axis has to count past one.
        "twoConditions": [(1, 2, 2), (1, 2, 3), (1, 3, 4)],
    }
    tensors = {}
    for label, shapes in layouts.items():
        mask = torch.zeros(sum(frames * height * width for frames, height, width in shapes))
        cos, sin = rope(shapes, mask.bool(), torch.device("cpu"))
        assert torch.equal(cos[..., 0::2], cos[..., 1::2]), "the reference interleaves pairs"
        tensors[f"{label}.cos"] = cos[..., 0::2].float().contiguous()
        tensors[f"{label}.sin"] = sin[..., 0::2].float().contiguous()
    save_file(tensors, str(out / "rope.safetensors"))
    print(f"rope: {len(tensors)} tensors")


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
