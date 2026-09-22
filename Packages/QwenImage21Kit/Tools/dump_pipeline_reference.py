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
"""Run the reference `QwenImage21Pipeline` with a condition image and dump what it produced.

`dump_pipeline.py` pins the text-to-image path. This pins the other one, which is most of what
2.1 is for: the picture goes through the vision tower as context *and* through the autoencoder
as condition latents prepended to the noise, and both copies come from one resize. A port that
fed the tower a picture it never showed the autoencoder, or laid the condition tokens out in
the wrong place, would still make a plausible picture from the prompt alone -- so the
text-to-image fixture cannot catch it and this one can.

**The committed picture is already the size the pipeline would resize it to**, which is what
makes the comparison about the port rather than about two resamplers. The reference resizes
every condition image to `calculate_dimensions(output_resolution**2, ratio)` with PIL's
lanczos; `QwenImage21ReferencePicture` does the same fit through Core Graphics at `.high`.
Those are different kernels, so any picture that actually needed resizing would put the two
runs a resample apart before the model saw anything. At the fitted size both are identities:
PIL's `Image.resize` returns a copy when the size already matches, and a Core Graphics draw of
a picture into a bitmap of its own size is a copy too. 1024 x 1024 is that size for a square
picture at the default `output_resolution`, so that is what is written.

The picture the pipeline is handed is written out as `pipeline_reference.png` and nowhere else:
the round trip is checked to be lossless, so the Swift suite compares its own fit against that
file's own pixels rather than against a second 4.2 MB copy of them in the fixture.

**Alpha is binary and the transparent pixels are black.** Core Graphics has no straight-alpha
context, so the Swift fit draws premultiplied and un-premultiplies afterwards, which loses the
colour under a fully transparent pixel (`PROVENANCE.md` states it). A picture whose transparent
region is already black round-trips exactly, so the one thing this fixture is not measuring is
the one departure it could not measure honestly.

**The noise is saved, not the seed**, for `dump_pipeline.py`'s reason: `MLXRandom` is not a
`torch.Generator`.

    QWEN_IMAGE_21_SNAPSHOT=/path/to/Qwen-Image-2.1 uv run Tools/dump_pipeline_reference.py

`QWEN21_DEVICE` picks the device (`mps` by default) and `QWEN21_DTYPE` the precision
(`bfloat16`, which is what the release ships and what Zephra runs).
"""

import json
import os
import pathlib
import sys

import numpy as np
import torch
from PIL import Image as PILImage
from safetensors.torch import save_file

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

PROMPT = "keep the shapes and make the light warmer"
HEIGHT = 256
WIDTH = 256
STEPS = 2
SEED = 11
OUTPUT_RESOLUTION = 1024
# `calculate_dimensions(1024 * 1024, 1.0)`: the size a square condition image is brought to, and
# therefore the size it is committed at, so neither side resamples. Asserted below.
CONDITION = 1024
PICTURE_SEED = 42


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


def condition_picture() -> PILImage.Image:
    """A deterministic RGBA picture: a gradient, a seeded blocky overlay, a hard alpha edge.

    The overlay is 32-pixel blocks rather than per-pixel noise so the PNG stays small, and it is
    there at all because a pure gradient is separable in both axes -- a port that transposed the
    picture on its way to the tower would reproduce it exactly. The alpha edge is hard, and the
    colour beneath it is zero, so the premultiplied round trip in the Swift fit is lossless.
    """
    rows, columns = np.mgrid[0:CONDITION, 0:CONDITION].astype(np.float32) / (CONDITION - 1)
    gradient = np.stack(
        [columns * 255, rows * 255, (1 - 0.5 * (rows + columns)) * 255], axis=-1)
    blocks = np.random.default_rng(PICTURE_SEED).integers(
        -60, 61, size=(CONDITION // 32, CONDITION // 32, 3))
    overlay = np.repeat(np.repeat(blocks, 32, axis=0), 32, axis=1).astype(np.float32)
    colour = np.clip(gradient + overlay, 0, 255).astype(np.uint8)
    # Transparent from two thirds across: most of the picture still carries signal, and the
    # edge is one column wide so a resample of any kind would show up immediately.
    alpha = np.where(np.arange(CONDITION) < (2 * CONDITION) // 3, 255, 0).astype(np.uint8)
    alpha = np.broadcast_to(alpha, (CONDITION, CONDITION))
    colour = np.where(alpha[..., None] == 0, 0, colour)
    return PILImage.fromarray(
        np.concatenate([colour, alpha[..., None]], axis=-1).astype(np.uint8), mode="RGBA")


def dump(out: pathlib.Path) -> None:
    from diffusers import QwenImage21Pipeline
    from diffusers.pipelines.qwenimage21.pipeline_qwenimage21 import calculate_dimensions

    fitted_width, fitted_height, _ = calculate_dimensions(OUTPUT_RESOLUTION * OUTPUT_RESOLUTION, 1.0)
    if (fitted_width, fitted_height) != (CONDITION, CONDITION):
        raise SystemExit(
            f"the condition picture is committed at {CONDITION} square, but the pipeline would "
            f"resize a square picture to {fitted_width} x {fitted_height}; the fixture would be "
            f"measuring two resamplers rather than the port.")

    out.mkdir(parents=True, exist_ok=True)
    picture = condition_picture()
    picture.save(out / "pipeline_reference.png")
    # The committed PNG *is* the array the model reads, so the Swift suite can compare its own
    # fit against the PNG's own pixels rather than against a second copy of them in the
    # fixture -- 4.2 MB of redundancy. That only holds if the round trip is lossless, so it is
    # checked here rather than assumed.
    if not np.array_equal(np.asarray(PILImage.open(out / "pipeline_reference.png")), np.asarray(picture)):
        raise SystemExit(
            "the committed PNG does not read back as the array the pipeline is handed, so the "
            "Swift suite cannot compare its fit against it.")

    device = os.environ.get("QWEN21_DEVICE", "mps")
    dtype = getattr(torch, os.environ.get("QWEN21_DTYPE", "bfloat16"))
    pipe = QwenImage21Pipeline.from_pretrained(str(snapshot()), torch_dtype=dtype)
    pipe.to(device)
    pipe.set_progress_bar_config(disable=True)

    # The noise the loop starts from, drawn in the unpacked latent grid of the *target* and
    # packed the way `prepare_latents` does. The condition latents are prepended inside the
    # loop and are not part of it.
    cells = (2 * (HEIGHT // 32), 2 * (WIDTH // 32))
    generator = torch.Generator(device="cpu").manual_seed(SEED)
    channels = pipe.transformer.config.in_channels
    unpacked = torch.randn((1, 1, channels, *cells), generator=generator, dtype=torch.float32)
    packed = unpacked.view(1, channels, cells[0] * cells[1]).transpose(1, 2)

    common = dict(
        prompt=PROMPT, image=picture, height=HEIGHT, width=WIDTH, num_inference_steps=STEPS,
        output_resolution=OUTPUT_RESOLUTION, latents=packed.to(device=device, dtype=dtype))
    latents = pipe(**common, output_type="latent").images
    rendered = pipe(**common, output_type="np").images[0]

    tensors = {
        "noise": packed.to(torch.float32).contiguous(),
        "latents": latents.to("cpu", torch.float32).contiguous(),
        "pixels": torch.from_numpy(np.round(rendered * 255).astype(np.uint8)).contiguous(),
    }
    save_file(tensors, str(out / "pipeline_reference.safetensors"))
    from importlib.metadata import version

    (out / "pipeline_reference.json").write_text(
        json.dumps(
            {
                "prompt": PROMPT, "height": HEIGHT, "width": WIDTH, "steps": STEPS, "seed": SEED,
                "conditionWidth": CONDITION, "conditionHeight": CONDITION,
                "outputResolution": OUTPUT_RESOLUTION, "pictureSeed": PICTURE_SEED,
                "device": device, "dtype": str(dtype).removeprefix("torch."),
                "torchvision": version("torchvision"),
            },
            indent=2,
        )
        + "\n"
    )
    print(
        "pipeline_reference:",
        ", ".join(f"{name} {tuple(tensor.shape)} {tensor.dtype}" for name, tensor in tensors.items()),
    )


if __name__ == "__main__":
    dump(pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else default_out())
