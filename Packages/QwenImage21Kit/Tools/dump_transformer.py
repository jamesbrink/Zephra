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
"""`QwenImage21Transformer2DModel` at doll's-house size: one block, and a whole small model.

What this pins, and every one of them is a way 2.1 differs from 2512 that loads cleanly and
then makes noise: the **single shared modulation table** every block reads rather than a table
per block; the `causal_condition` row, which is that table evaluated at `t = 0` and given to
the condition tokens ahead of the target; `patch_size = 1`, so the image projection takes 64
channels a token straight off the latent; the zero-centre RMS norm in the text projection,
which stores `scale - 1`; the block-causal attention mask cut by `img_shapes`; and the fact
that there are no biases anywhere.

Written with the kit's skeleton so the seven dumpers live in one place; the doll's-house widths
are settled by the step that adds `TransformerParityTests`.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

# Doll's house: two heads of sixteen, three rope axes filling one head, four layers' worth of
# modulation in one table.
CONFIG = {
    "attention_head_dim": 16,
    "axes_dims_rope": [4, 6, 6],
    "context_in_dim": 32,
    "in_channels": 8,
    "num_attention_heads": 2,
    "num_layers": 2,
    "out_channels": 8,
    "patch_size": 1,
    "mlp_ratio": 3,
    "eps": 1e-6,
    "causal_condition": True,
}

TEXT_TOKENS = 5
CONDITION_GRID = (1, 2, 3)
TARGET_GRID = (1, 3, 4)


def dump(out: pathlib.Path) -> None:
    from diffusers.models.transformers.transformer_qwenimage_21 import (
        QwenImage21Transformer2DModel,
    )

    model = QwenImage21Transformer2DModel(**CONFIG).eval()
    inner = CONFIG["num_attention_heads"] * CONFIG["attention_head_dim"]
    condition = CONDITION_GRID[1] * CONDITION_GRID[2]
    target = TARGET_GRID[1] * TARGET_GRID[2]

    hidden = torch.randn(1, condition + target, CONFIG["in_channels"])
    encoder = torch.randn(1, TEXT_TOKENS, inner)
    timestep = torch.tensor([0.75])
    shapes = [[CONDITION_GRID, TARGET_GRID]]
    # True where the vision-language sequence holds an image slot; each slot stands for four
    # latent tokens, and the target's own slots are appended by the pipeline.
    mask = torch.zeros(1, TEXT_TOKENS + target // 4, dtype=torch.bool)

    with torch.no_grad():
        output = model(
            hidden_states=hidden,
            encoder_hidden_states=encoder,
            timestep=timestep,
            img_shapes=shapes,
            img_mask=mask,
            return_dict=False,
        )[0]

    tensors = {f"model.{name}": value.float().contiguous() for name, value in model.state_dict().items()}
    tensors["in.hidden"] = hidden.contiguous()
    tensors["in.encoder"] = encoder.contiguous()
    tensors["in.timestep"] = timestep.contiguous()
    tensors["in.mask"] = mask.to(torch.int32).contiguous()
    tensors["out.velocity"] = output.float().contiguous()
    save_file(tensors, str(out / "transformer.safetensors"))
    print(f"transformer: {len(tensors)} tensors")


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
