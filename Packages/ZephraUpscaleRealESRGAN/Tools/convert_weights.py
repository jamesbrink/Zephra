# /// script
# requires-python = ">=3.11"
# dependencies = ["torch", "safetensors", "numpy"]
# ///
"""Convert the published realesr-general-x4v3 checkpoint into the file this package bundles.

The release asset is a torch pickle whose state dict is wrapped under `params` (some releases
under `params_ema`); MLX reads safetensors. So the conversion is: download once, unwrap once,
cast to float16, write. Nothing is renamed and nothing is transposed -- the OIHW to OHWI
transpose belongs in Swift, where `SRVGGNetWeights` does it and a test pins it.

The SHA-256 this prints goes into `PROVENANCE.md`, so a re-conversion is checkable, and so is
which of the two keys was unwrapped: picking the wrong one is a silent swap of one trained
network for another.

Run with `uv run Tools/convert_weights.py`.
"""

import argparse
import hashlib
import pathlib
import urllib.request

import torch
from safetensors.torch import save_file

RELEASE = (
    "https://github.com/xinntao/Real-ESRGAN/releases/download/"
    "v0.2.5.0/realesr-general-x4v3.pth"
)
EXPECTED_BYTES = 4_885_111


def download(cache: pathlib.Path) -> pathlib.Path:
    """The release asset, downloaded once into `cache`."""
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / "realesr-general-x4v3.pth"
    if not path.exists():
        print(f"downloading {RELEASE}")
        urllib.request.urlretrieve(RELEASE, path)
    size = path.stat().st_size
    if size != EXPECTED_BYTES:
        raise SystemExit(f"{path} is {size} bytes, expected {EXPECTED_BYTES}")
    print(f"source: {path} ({size} bytes)")
    return path


def unwrap(checkpoint: dict) -> tuple[dict, str]:
    """The flat state dict inside the pickle, and which key held it."""
    for key in ("params", "params_ema"):
        if key in checkpoint:
            return checkpoint[key], key
    raise SystemExit(f"no params under {sorted(checkpoint)[:8]}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        type=pathlib.Path,
        default=pathlib.Path("Sources/ZephraUpscaleRealESRGAN/Resources/Weights"),
    )
    parser.add_argument(
        "--cache", type=pathlib.Path, default=pathlib.Path.home() / ".cache" / "zephra-upscale"
    )
    args = parser.parse_args()

    source = download(args.cache)
    checkpoint = torch.load(source, map_location="cpu", weights_only=True)
    state, key = unwrap(checkpoint)
    print(f"unwrapped: {key} ({len(state)} tensors)")

    tensors = {name: value.to(torch.float16).contiguous() for name, value in state.items()}
    parameters = sum(value.numel() for value in tensors.values())
    print(f"parameters: {parameters}")

    args.out.mkdir(parents=True, exist_ok=True)
    destination = args.out / "realesr-general-x4v3-fp16.safetensors"
    save_file(tensors, str(destination))

    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    print(f"wrote: {destination} ({destination.stat().st_size} bytes)")
    print(f"sha256: {digest}")


if __name__ == "__main__":
    main()
