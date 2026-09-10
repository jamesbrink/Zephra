# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "torch==2.14.0",
#     "diffusers==0.40.0",
#     "transformers==5.16.1",
#     "tokenizers==0.23.2",
#     "safetensors==0.8.0",
#     "numpy==2.5.2",
# ]
# ///
"""Dump reference tensors for LTX-2.5's spatial latent upsampler, the second stage's door.

The reference is diffusers' `LTX2LatentUpsamplerModel` at the pack's shape -- three-deep
convolutions, a GroupNorm of 32 after the first, one stage of residual blocks either side of a
per-frame pixel shuffle that doubles height and width, and a plain `Conv2d + PixelShuffleND`
upsampler rather than the rational resampler -- at a doll's-house width. Sixty-four middle
channels is the narrowest that still means anything: GroupNorm's thirty-two groups then hold two
channels each, so a port that grouped every thirty-second channel together (MLX's default) rather
than neighbouring pairs (PyTorch's) gives a different answer, where thirty-two channels would
make the two groupings the same.

Every parameter is randomised, the GroupNorm affines included, since the defaults (unit weight,
zero bias) would let a port that never loaded them pass. Weights are saved under the pack's
names and prefix, with convolution kernels already in MLX's channels-last order
(`[out, kd, kh, kw, in]` and `[out, kh, kw, in]`), which is how `spatial_upscaler_x2_v1_1.safetensors`
stores them; the Swift module loads the fixture exactly as it loads the pack.

The second fixture pins what surrounds the network: the upsample pipeline denormalises a
normalised latent by the autoencoder's per-channel statistics before the upsampler, and the
next stage normalises what comes out. It carries no weights of its own; the test reads them
from the first fixture, which is dumped from the same seed.
"""

import pathlib

import torch
from safetensors.torch import save_file

# The pack's prefix on every tensor of the upsampler file.
PREFIX = "spatial_upscaler_x2_v1_1."


def _dolls_house():
    """The pack's configuration at eight latent and sixty-four middle channels, one block a stage."""
    from diffusers.pipelines.ltx2.latent_upsampler import LTX2LatentUpsamplerModel

    torch.manual_seed(3)
    model = LTX2LatentUpsamplerModel(
        in_channels=8,
        mid_channels=64,
        num_blocks_per_stage=1,
        dims=3,
        spatial_upsample=True,
        temporal_upsample=False,
        use_rational_resampler=False,
    ).eval()
    with torch.no_grad():
        for name, parameter in model.named_parameters():
            if parameter.ndim > 1:
                # A kernel scaled by its fan-in, so activations stay of order one through
                # nine convolutions and the comparison is not one of overflow.
                fan_in = parameter[0].numel()
                parameter.copy_(torch.randn_like(parameter) / fan_in**0.5)
            elif name.endswith("norm1.weight") or name.endswith("norm2.weight") or name.endswith("initial_norm.weight"):
                parameter.copy_(torch.rand_like(parameter) + 0.5)
            else:
                parameter.copy_(torch.randn_like(parameter) * 0.1)
    return model


def _pack_layout(value: torch.Tensor) -> torch.Tensor:
    """A kernel in the order the pack stores it: PyTorch's `[out, in, k...]` to `[out, k..., in]`."""
    if value.ndim == 5:
        return value.permute(0, 2, 3, 4, 1)
    if value.ndim == 4:
        return value.permute(0, 2, 3, 1)
    return value


def dump_upsampler(out: pathlib.Path) -> None:
    """The upsampler's weights and one pass over a random denormalised latent."""
    model = _dolls_house()
    tensors = {PREFIX + key: _pack_layout(value).clone() for key, value in model.state_dict().items()}
    assert len(tensors) == 24, len(tensors)

    latent = torch.randn(1, 8, 3, 4, 6)
    with torch.no_grad():
        upsampled = model(latent)
    assert upsampled.shape == (1, 8, 3, 8, 12), upsampled.shape

    tensors[PREFIX + "in.latent"] = latent
    tensors[PREFIX + "out.latent"] = upsampled
    tensors = {name: value.float().contiguous() for name, value in tensors.items()}
    save_file(tensors, str(out / "latent_upsampler.safetensors"))
    print(f"latent_upsampler: {len(tensors)} tensors")


def dump_normalized(out: pathlib.Path) -> None:
    """A normalised latent through the pipeline's denormalise, the upsampler, and the next
    stage's normalise, with the statistics it ran under.

    `_denormalize_latents` is the upsample pipeline's and `_normalize_latents` the generation
    pipeline's, called as they are, with the autoencoder's `scaling_factor` of 1.
    """
    from diffusers.pipelines.ltx2.pipeline_ltx2 import LTX2Pipeline
    from diffusers.pipelines.ltx2.pipeline_ltx2_latent_upsample import LTX2LatentUpsamplePipeline

    model = _dolls_house()
    torch.manual_seed(4)
    mean = torch.randn(8)
    std = torch.rand(8) + 0.5
    normalized = torch.randn(1, 8, 3, 4, 6)
    with torch.no_grad():
        denormalized = LTX2LatentUpsamplePipeline._denormalize_latents(normalized, mean, std, 1.0)
        upsampled = model(denormalized)
        renormalized = LTX2Pipeline._normalize_latents(upsampled, mean, std, 1.0)
    assert renormalized.shape == (1, 8, 3, 8, 12), renormalized.shape

    tensors = {
        PREFIX + "in.mean": mean,
        PREFIX + "in.std": std,
        PREFIX + "in.normalized": normalized,
        PREFIX + "out.normalized": renormalized,
    }
    tensors = {name: value.float().contiguous() for name, value in tensors.items()}
    save_file(tensors, str(out / "latent_upsampler_normalized.safetensors"))
    print(f"latent_upsampler_normalized: {len(tensors)} tensors")


DUMPERS = {
    "latent_upsampler": dump_upsampler,
    "latent_upsampler_normalized": dump_normalized,
}
