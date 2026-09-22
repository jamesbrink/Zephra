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
#     "torchvision",
# ]
# ///
"""Run the reference `QwenImage21Pipeline` end to end and dump what it produced.

This is the one fixture that says the Swift port makes the *reference's* picture rather than a
plausible one. Every other fixture here pins one component against one input; this pins all of
them together, in the order the pipeline runs them, over the release's own weights.

**The noise is saved, not the seed.** `MLXRandom` is not a `torch.Generator`, so the same seed
is a different draw and no tolerance on a picture means anything. So the packed latent this
draws is written into the fixture and `PipelineParityTests` hands it straight to
`QwenImage21Request.noise`: both loops then walk the same ladder from the same place.

Small on purpose. 256 x 256 is 16 x 16 latent cells and 256 target tokens, two steps is two
forwards, and the whole fixture is a few hundred kilobytes. What it catches is everything that
is the same at any size: the template, the drop index, the layout, the rotary, the cache, the
schedule, the Euler step and the autoencoder, in one number.

    QWEN_IMAGE_21_SNAPSHOT=/path/to/Qwen-Image-2.1 uv run Tools/dump_pipeline.py

`QWEN21_DEVICE` picks the device (`mps` by default, `cpu` for a machine without the memory)
and `QWEN21_DTYPE` the precision (`bfloat16` by default, which is what the release ships and
what Zephra runs).

`torchvision` is in the dependencies and is never used: `Qwen3VLProcessor` builds a video
processor it will not be asked for, and that class refuses to exist without it. It is left
unpinned for that reason, and `pipeline.json` records which version ran.
"""

import json
import os
import pathlib
import sys

import numpy as np
import torch
from safetensors.torch import save_file

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

PROMPT = "a red ceramic teapot on a wooden table"
HEIGHT = 256
WIDTH = 256
STEPS = 2
SEED = 7


def snapshot() -> pathlib.Path:
    path = os.environ.get("QWEN_IMAGE_21_SNAPSHOT", "")
    if not path:
        raise SystemExit("QWEN_IMAGE_21_SNAPSHOT is not set; it must name the release directory.")
    directory = pathlib.Path(path)
    if not directory.is_dir():
        raise SystemExit(f"QWEN_IMAGE_21_SNAPSHOT names {directory}, which is not a directory.")
    return directory


def default_out() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parent.parent / "Tests" / "QwenImage21Tests" / "Fixtures"


def dump(out: pathlib.Path) -> None:
    from diffusers import QwenImage21Pipeline

    device = os.environ.get("QWEN21_DEVICE", "mps")
    dtype = getattr(torch, os.environ.get("QWEN21_DTYPE", "bfloat16"))
    pipe = QwenImage21Pipeline.from_pretrained(str(snapshot()), torch_dtype=dtype)
    pipe.to(device)
    pipe.set_progress_bar_config(disable=True)

    # The noise the loop starts from, drawn in the unpacked latent grid and packed the way
    # `prepare_latents` does, so what is handed in is exactly what it would have drawn.
    cells = (2 * (HEIGHT // 32), 2 * (WIDTH // 32))
    generator = torch.Generator(device="cpu").manual_seed(SEED)
    unpacked = torch.randn(
        (1, 1, pipe.transformer.config.in_channels, *cells), generator=generator, dtype=torch.float32
    )
    packed = unpacked.view(1, pipe.transformer.config.in_channels, cells[0] * cells[1]).transpose(1, 2)

    common = dict(
        prompt=PROMPT, height=HEIGHT, width=WIDTH, num_inference_steps=STEPS,
        latents=packed.to(device=device, dtype=dtype))
    latents = pipe(**common, output_type="latent").images
    picture = pipe(**common, output_type="np").images[0]

    tensors = {
        "noise": packed.to(torch.float32).contiguous(),
        "latents": latents.to("cpu", torch.float32).contiguous(),
        "pixels": torch.from_numpy(np.round(picture * 255).astype(np.uint8)).contiguous(),
        "sigmas": pipe.scheduler.sigmas.detach().clone().to("cpu", torch.float32).contiguous(),
    }
    out.mkdir(parents=True, exist_ok=True)
    save_file(tensors, str(out / "pipeline.safetensors"))
    from importlib.metadata import version

    (out / "pipeline.json").write_text(
        json.dumps(
            {
                "prompt": PROMPT, "height": HEIGHT, "width": WIDTH, "steps": STEPS, "seed": SEED,
                "device": device, "dtype": str(dtype).removeprefix("torch."),
                "torchvision": version("torchvision"),
            },
            indent=2,
        )
        + "\n"
    )
    print(
        "pipeline:",
        ", ".join(f"{name} {tuple(tensor.shape)} {tensor.dtype}" for name, tensor in tensors.items()),
    )


if __name__ == "__main__":
    dump(pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else default_out())
