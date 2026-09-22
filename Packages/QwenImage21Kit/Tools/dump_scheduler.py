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
"""The sigma ladder, the timesteps and the shift the Qwen-Image 2.1 pipeline walks.

Seven (steps, tokens) pairs, including the two the brief names — 40 steps at 1024 square
(4096 tokens) and at 512 square (1024 tokens) — and 16384 tokens, which is past the config's
`max_image_seq_len` and so exercises the extrapolation the reference does not clamp.

`uv run Tools/dump_scheduler.py` on its own; QWEN_IMAGE_21_SNAPSHOT is read for the published
scheduler config when it is set, and the published constants stand in when it is not.
"""

import argparse
import json
import os
import pathlib

import numpy as np
import torch
from safetensors.torch import save_file

# steps, latent tokens. 4096 is 1024 square and 1024 is 512 square, both at 40 steps; 16384 is
# 2048 square, past max_image_seq_len, which the reference extrapolates past rather than
# clamping to; two steps is the shortest finite ladder.
#
# One step is deliberately **not** here. Its ladder is the single sigma 1, so the terminal
# stretch divides by a scale factor of zero and every sigma comes back NaN — the reference
# warns and carries on. A fixture of NaNs pins nothing, and the port answers an unstretched
# ladder there instead, which `ScheduleTests` checks is at least finite.
PAIRS = [(40, 4096), (40, 1024), (40, 16384), (8, 4096), (4, 4096), (2, 4096), (50, 6144)]

PUBLISHED_CONFIG = {
    "num_train_timesteps": 1000,
    "shift": 1.0,
    "use_dynamic_shifting": True,
    "base_shift": 0.5,
    "max_shift": 0.9,
    "base_image_seq_len": 256,
    "max_image_seq_len": 8192,
    "shift_terminal": 0.02,
    "time_shift_type": "exponential",
    "invert_sigmas": False,
    "stochastic_sampling": False,
}


def published_config() -> dict:
    """The release's own scheduler config where there is one, else the constants it ships."""
    path = os.environ.get("QWEN_IMAGE_21_SNAPSHOT", "")
    if path:
        file = pathlib.Path(path) / "scheduler" / "scheduler_config.json"
        if file.is_file():
            config = json.loads(file.read_text())
            return {key: value for key, value in config.items() if not key.startswith("_")}
    return dict(PUBLISHED_CONFIG)


def calculate_shift(image_seq_len: int, config: dict) -> float:
    """The pipeline's own `calculate_shift`, which is a bare line with no clamp.

    diffusers moved this helper between modules more than once, so it is imported when it can
    be and the line is computed here when it cannot; the two are asserted equal where both
    exist, which is what keeps this copy honest.
    """
    base_seq_len = config["base_image_seq_len"]
    max_seq_len = config["max_image_seq_len"]
    base_shift = config["base_shift"]
    max_shift = config["max_shift"]
    slope = (max_shift - base_shift) / (max_seq_len - base_seq_len)
    mu = image_seq_len * slope + (base_shift - slope * base_seq_len)

    reference = None
    for module in (
        "diffusers.pipelines.qwenimage.pipeline_qwenimage_21",
        "diffusers.pipelines.qwenimage.pipeline_qwenimage",
        "diffusers.pipelines.flux.pipeline_flux",
    ):
        try:
            imported = __import__(module, fromlist=["calculate_shift"])
        except Exception:
            continue
        reference = getattr(imported, "calculate_shift", None)
        if reference is not None:
            break
    if reference is not None:
        theirs = reference(image_seq_len, base_seq_len, max_seq_len, base_shift, max_shift)
        assert abs(theirs - mu) < 1e-12, f"{theirs} != {mu}"
    return mu


def dump(out: pathlib.Path) -> None:
    from diffusers import FlowMatchEulerDiscreteScheduler

    config = published_config()
    tensors = {}
    for steps, tokens in PAIRS:
        scheduler = FlowMatchEulerDiscreteScheduler.from_config(config)
        mu = calculate_shift(tokens, config)
        # The pipeline passes its own ladder, linspace(1, 1/steps, steps), and its own mu.
        scheduler.set_timesteps(sigmas=np.linspace(1.0, 1 / steps, steps), mu=mu)
        key = f"steps{steps}.tokens{tokens}"
        tensors[f"{key}.sigmas"] = scheduler.sigmas.float().contiguous()
        tensors[f"{key}.timesteps"] = scheduler.timesteps.float().contiguous()
        tensors[f"{key}.mu"] = torch.tensor(mu, dtype=torch.float32)
    save_file(tensors, str(out / "scheduler.safetensors"))
    print(f"scheduler: {len(tensors)} tensors over {len(PAIRS)} ladders")


def main() -> None:
    import dump_reference

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=dump_reference.default_out())
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(0)
    dump(arguments.out)
    dump_reference.write_versions(arguments.out)


if __name__ == "__main__":
    import sys

    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    main()
