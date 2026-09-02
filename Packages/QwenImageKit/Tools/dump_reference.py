# /// script
# requires-python = ">=3.11"
# dependencies = ["torch", "diffusers", "transformers", "safetensors", "numpy"]
# ///
"""Dump reference tensors from the Apache-2.0 diffusers implementation.

Every fixture this writes is a claim about what the reference does, checked in Swift by the
matching test. Files are tiny on purpose: a doll's-house configuration catches a transposed axis
or a swapped modulation chunk exactly as well as a real one, and can be committed.

Run with `uv run Tools/dump_reference.py --out Tests/QwenImageTests/Fixtures`.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file


def dump_rope(out: pathlib.Path) -> None:
    """QwenEmbedRope's image and text frequency tables, as real cosine/sine pairs."""
    from diffusers.models.transformers.transformer_qwenimage import QwenEmbedRope

    rope = QwenEmbedRope(theta=10000, axes_dim=[16, 56, 56], scale_rope=True)
    tensors = {}
    for label, (frames, height, width, text_length) in {
        "small": (1, 4, 4, 3),
        "wide": (1, 2, 6, 5),
        "large": (1, 64, 64, 20),
    }.items():
        image, text = rope([(frames, height, width)], max_txt_seq_len=text_length)
        tensors[f"{label}.image.cos"] = image.real.float().contiguous()
        tensors[f"{label}.image.sin"] = image.imag.float().contiguous()
        tensors[f"{label}.text.cos"] = text.real.float().contiguous()
        tensors[f"{label}.text.sin"] = text.imag.float().contiguous()
    save_file(tensors, str(out / "rope.safetensors"))
    print(f"rope: {len(tensors)} tensors")


def dump_scheduler(out: pathlib.Path) -> None:
    """The sigma ladder, for the published config, at a few step counts and image sizes."""
    from diffusers import FlowMatchEulerDiscreteScheduler

    config = {
        "base_image_seq_len": 256,
        "base_shift": 0.5,
        "invert_sigmas": False,
        "max_image_seq_len": 8192,
        "max_shift": 0.9,
        "num_train_timesteps": 1000,
        "shift": 1.0,
        "shift_terminal": 0.02,
        "stochastic_sampling": False,
        "time_shift_type": "exponential",
        "use_beta_sigmas": False,
        "use_dynamic_shifting": True,
        "use_exponential_sigmas": False,
        "use_karras_sigmas": False,
    }
    tensors = {}
    for steps, tokens in [(4, 4096), (8, 4096), (4, 1024), (20, 9216)]:
        scheduler = FlowMatchEulerDiscreteScheduler.from_config(config)
        slope = (config["max_shift"] - config["base_shift"]) / (
            config["max_image_seq_len"] - config["base_image_seq_len"]
        )
        mu = tokens * slope + config["base_shift"] - slope * config["base_image_seq_len"]
        scheduler.set_timesteps(num_inference_steps=steps, mu=mu)
        tensors[f"steps{steps}.tokens{tokens}.sigmas"] = scheduler.sigmas.float().contiguous()
    save_file(tensors, str(out / "scheduler.safetensors"))
    print(f"scheduler: {len(tensors)} tensors")


def dump_latent_packing(out: pathlib.Path) -> None:
    """The pipeline's own pack/unpack, on a tensor whose values name their coordinates."""
    from diffusers.pipelines.qwenimage.pipeline_qwenimage import QwenImagePipeline

    batch, channels, height, width = 1, 16, 8, 6
    latents = torch.arange(batch * channels * height * width, dtype=torch.float32)
    latents = latents.reshape(batch, channels, height, width)
    packed = QwenImagePipeline._pack_latents(latents, batch, channels, height, width)
    save_file(
        {"latents": latents.contiguous(), "packed": packed.contiguous()},
        str(out / "latent_packing.safetensors"),
    )
    print("latent packing: 2 tensors")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--only", nargs="*", default=None)
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)

    torch.manual_seed(0)
    dumpers = {
        "rope": dump_rope,
        "scheduler": dump_scheduler,
        "latent_packing": dump_latent_packing,
    }
    for name, dumper in dumpers.items():
        if arguments.only and name not in arguments.only:
            continue
        dumper(arguments.out)


if __name__ == "__main__":
    main()
