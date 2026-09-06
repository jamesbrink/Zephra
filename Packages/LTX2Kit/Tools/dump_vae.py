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
"""Dump reference tensors for the LTX-2.5 video autoencoder's convolutional decoder.

A doll's-house decoder with the real one's shape: the same five residual stages and four
depth-to-space upsamplers in the same order (two spatiotemporal, one temporal, one spatial), the
same patch-4 unpatchify, zero spatial padding and a non-causal time axis -- only the widths are
cut to a thirty-second of the real ones and the stages hold one or two blocks. Every structural
mistake worth catching -- a pixel shuffle in the wrong channel order, a first frame not dropped,
a kernel axis swapped, the per-channel statistics skipped -- shows up at this size exactly as it
would at the real one, and the file is small enough to commit.

The fixture is written under the *official* key layout the `mlx-community/ltx-2.5-mlx` pack
uses (`up_blocks.N.res_blocks.M`, `up_blocks.N.conv`, `per_channel_statistics.{mean,std}`),
with convolution kernels already in MLX's `[out, kd, kh, kw, in]` order, so the Swift decoder
loads the fixture exactly as it loads the pack.
"""

import pathlib

import torch
from safetensors.torch import save_file

# diffusers' decoder module paths, and the official ones the pack spells them as. Longest first,
# so `up_blocks.0.upsamplers.0` is renamed before `up_blocks.0` could be.
_TO_OFFICIAL = [
    ("mid_block.resnets", "up_blocks.0.res_blocks"),
    ("up_blocks.0.upsamplers.0", "up_blocks.1"),
    ("up_blocks.0.resnets", "up_blocks.2.res_blocks"),
    ("up_blocks.1.upsamplers.0", "up_blocks.3"),
    ("up_blocks.1.resnets", "up_blocks.4.res_blocks"),
    ("up_blocks.2.upsamplers.0", "up_blocks.5"),
    ("up_blocks.2.resnets", "up_blocks.6.res_blocks"),
    ("up_blocks.3.upsamplers.0", "up_blocks.7"),
    ("up_blocks.3.resnets", "up_blocks.8.res_blocks"),
]


def _official_name(diffusers_key: str) -> str | None:
    """The pack's name for a diffusers decoder parameter, or None for one the pack has not got."""
    if diffusers_key == "latents_mean":
        return "per_channel_statistics.mean"
    if diffusers_key == "latents_std":
        return "per_channel_statistics.std"
    if not diffusers_key.startswith("decoder."):
        return None
    name = diffusers_key[len("decoder.") :]
    for theirs, ours in _TO_OFFICIAL:
        if name.startswith(theirs + "."):
            return ours + name[len(theirs) :]
    return name  # conv_in.conv.*, conv_out.conv.*


def dump_decoder(out: pathlib.Path) -> None:
    """The decoder's weights and one decode of a random denormalised latent."""
    from diffusers.models.autoencoders.autoencoder_kl_ltx2 import AutoencoderKLLTX2Video

    torch.manual_seed(0)
    vae = AutoencoderKLLTX2Video(
        in_channels=3,
        out_channels=3,
        latent_channels=4,
        block_out_channels=(8, 16, 32, 32),
        decoder_block_out_channels=(8, 16, 16, 32),
        layers_per_block=(1, 1, 1, 1, 1),
        decoder_layers_per_block=(1, 1, 2, 1, 1),
        spatio_temporal_scaling=(True, True, True, True),
        decoder_spatio_temporal_scaling=(True, True, True, True),
        decoder_inject_noise=(False, False, False, False, False),
        downsample_type=("spatial", "temporal", "spatiotemporal", "spatiotemporal"),
        upsample_type=("spatiotemporal", "spatiotemporal", "temporal", "spatial"),
        upsample_residual=(False, False, False, False),
        upsample_factor=(2, 2, 1, 2),
        timestep_conditioning=False,
        patch_size=4,
        patch_size_t=1,
        resnet_norm_eps=1e-6,
        encoder_causal=True,
        decoder_causal=False,
        encoder_spatial_padding_mode="zeros",
        decoder_spatial_padding_mode="zeros",
        spatial_compression_ratio=32,
        temporal_compression_ratio=8,
    ).eval()
    with torch.no_grad():
        # Non-trivial statistics, so a port that forgot to denormalise cannot pass.
        vae.latents_mean.copy_(torch.randn(4))
        vae.latents_std.copy_(torch.rand(4) + 0.5)

    tensors = {}
    for key, value in vae.state_dict().items():
        name = _official_name(key)
        if name is None:
            continue
        if value.ndim == 5:
            # [out, in, kd, kh, kw] -> MLX's [out, kd, kh, kw, in], which is how the pack stores them.
            value = value.permute(0, 2, 3, 4, 1)
        tensors[f"vae_decoder.{name}"] = value.clone()

    # The pipeline denormalises before it hands the decoder the latent; the port does both.
    latent = torch.randn(1, 4, 2, 2, 3)
    with torch.no_grad():
        denormalised = latent * vae.latents_std.view(1, -1, 1, 1, 1) + vae.latents_mean.view(1, -1, 1, 1, 1)
        video = vae.decode(denormalised, return_dict=False)[0]
    assert video.shape == (1, 3, 9, 64, 96), video.shape

    tensors["vae_decoder.in.latent"] = latent
    tensors["vae_decoder.out.video"] = video  # [1, 3, F, H, W], unclipped
    tensors = {name: value.float().contiguous() for name, value in tensors.items()}
    save_file(tensors, str(out / "vae_decoder.safetensors"))
    print(f"vae_decoder: {len(tensors)} tensors")


def dump_frames(out: pathlib.Path) -> None:
    """How -1...1 pixels become bytes: `(x + 1) / 2 * 255`, rounded to the nearest, clipped."""
    import numpy as np
    from diffusers.utils import numpy_to_pil

    torch.manual_seed(1)
    # Values past the range too, so the clip is pinned as well as the rounding.
    pixels = torch.rand(2, 4, 5, 3) * 2.4 - 1.2
    unit = (pixels / 2 + 0.5).clamp(0, 1).numpy()
    frames = np.stack([np.asarray(image) for image in numpy_to_pil(unit)])  # uint8 [F, H, W, 3]
    assert frames.dtype == np.uint8 and frames.shape == (2, 4, 5, 3)
    save_file(
        {"in.pixels": pixels.contiguous(), "out.bytes": torch.from_numpy(frames).contiguous()},
        str(out / "frames.safetensors"),
    )
    print("frames: 2 tensors")


DUMPERS = {"vae_decoder": dump_decoder, "frames": dump_frames}
