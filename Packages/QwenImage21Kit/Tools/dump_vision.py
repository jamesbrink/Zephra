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
"""Qwen3-VL's vision tower at doll's-house size, DeepStack taps included.

What this pins: the patch embedding over a temporal patch of two, which a still picture is
repeated to fill; the learned position table interpolated onto this picture's patch grid rather
than sliced; the two-by-two spatial merge, so four patches leave the tower as one image slot;
and the **DeepStack taps**, the outputs of the blocks `deepstack_visual_indexes` names, which
are added into the decoder's own stream at those depths and are invisible in the tower's final
output — a port that dropped them would produce a plausible picture of the wrong reference.

Written with the kit's skeleton so the seven dumpers live in one place; the doll's-house widths
are settled by the step that adds the tower's parity suite.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

VISION_CONFIG = {
    "depth": 4,
    "hidden_size": 32,
    "num_heads": 2,
    "intermediate_size": 64,
    "in_channels": 3,
    "patch_size": 4,
    "temporal_patch_size": 2,
    "spatial_merge_size": 2,
    "num_position_embeddings": 64,
    "out_hidden_size": 32,
    "deepstack_visual_indexes": [1, 3],
    "hidden_act": "gelu_pytorch_tanh",
}

# Patch grid: one temporal patch, four rows, four columns, which merges to four image slots.
GRID = (1, 4, 4)


def dump(out: pathlib.Path) -> None:
    from transformers.models.qwen3_vl.configuration_qwen3_vl import Qwen3VLVisionConfig
    from transformers.models.qwen3_vl.modeling_qwen3_vl import Qwen3VLVisionModel

    config = Qwen3VLVisionConfig(**VISION_CONFIG)
    model = Qwen3VLVisionModel(config).eval()
    patch = config.in_channels * config.temporal_patch_size * config.patch_size**2
    pixels = torch.randn(GRID[0] * GRID[1] * GRID[2], patch)
    grid = torch.tensor([list(GRID)])

    with torch.no_grad():
        output, deepstack = model(pixels, grid_thw=grid)

    tensors = {f"model.{name}": value.float().contiguous() for name, value in model.state_dict().items()}
    tensors["in.pixels"] = pixels.contiguous()
    tensors["in.grid"] = grid.to(torch.int32).contiguous()
    tensors["out.slots"] = output.float().contiguous()
    for index, tap in enumerate(deepstack):
        tensors[f"out.deepstack{index}"] = tap.float().contiguous()
    save_file(tensors, str(out / "vision.safetensors"))
    print(f"vision: {len(tensors)} tensors")


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
