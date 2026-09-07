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
"""Dump reference tensors for the LTX-2.5 video autoencoder's convolutional decoder and encoder.

A doll's-house decoder with the real one's shape: the same five residual stages and four
depth-to-space upsamplers in the same order (two spatiotemporal, one temporal, one spatial), the
same patch-4 unpatchify, zero spatial padding and a non-causal time axis -- only the widths are
cut to a thirty-second of the real ones and the stages hold one or two blocks. Every structural
mistake worth catching -- a pixel shuffle in the wrong channel order, a first frame not dropped,
a kernel axis swapped, the per-channel statistics skipped -- shows up at this size exactly as it
would at the real one, and the file is small enough to commit.

The encoder fixture mirrors it: five residual stages with four space-to-depth downsamplers
between them (spatial, temporal, then two spatiotemporal), a patch-4 spatial patchify at the
door, and causal time padding throughout. Its `layers_per_block` is spelled out as the real
checkpoint's `(4, 6, 4, 2, 2)` rather than left to the diffusers constructor's default of
`(4, 6, 6, 2, 2)`, which is **not** this checkpoint: the third stage holds four blocks, not six,
and a fixture dumped at the default would pin the wrong tree.

Both fixtures are written under the *official* key layout the `mlx-community/ltx-2.5-mlx` pack
uses (`up_blocks.N.res_blocks.M`, `up_blocks.N.conv`, `per_channel_statistics.{mean,std}`;
`down_blocks.N.res_blocks.M`, `down_blocks.N.conv`, and the encoder's own underscore-prefixed
`per_channel_statistics.{_mean_of_means,_std_of_means}`), with convolution kernels already in
MLX's `[out, kd, kh, kw, in]` order, so the Swift modules load the fixtures exactly as they load
the pack.
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

# The same for the encoder. diffusers splits it into four `down_blocks`, each holding its resnets
# and one downsampler, plus a `mid_block` for the last stage; the pack flattens all nine into one
# `down_blocks` list, so a stage's index there is twice the diffusers block's.
_TO_OFFICIAL_ENCODER = [
    ("mid_block.resnets", "down_blocks.8.res_blocks"),
    ("down_blocks.0.downsamplers.0", "down_blocks.1"),
    ("down_blocks.1.downsamplers.0", "down_blocks.3"),
    ("down_blocks.2.downsamplers.0", "down_blocks.5"),
    ("down_blocks.3.downsamplers.0", "down_blocks.7"),
    ("down_blocks.0.resnets", "down_blocks.0.res_blocks"),
    ("down_blocks.1.resnets", "down_blocks.2.res_blocks"),
    ("down_blocks.2.resnets", "down_blocks.4.res_blocks"),
    ("down_blocks.3.resnets", "down_blocks.6.res_blocks"),
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


def _official_encoder_name(diffusers_key: str) -> str | None:
    """The pack's name for a diffusers encoder parameter, or None for one the pack has not got.

    The statistics are a different pair from the decoder's and keep their leading underscores,
    which is how the official checkpoint registers them.
    """
    if diffusers_key == "latents_mean":
        return "per_channel_statistics._mean_of_means"
    if diffusers_key == "latents_std":
        return "per_channel_statistics._std_of_means"
    if not diffusers_key.startswith("encoder."):
        return None
    name = diffusers_key[len("encoder.") :]
    for theirs, ours in _TO_OFFICIAL_ENCODER:
        if name.startswith(theirs + "."):
            return ours + name[len(theirs) :]
    return name  # conv_in.conv.*, conv_out.conv.*


def _dolls_house(seed: int, layers_per_block: tuple[int, ...]):
    """A whole autoencoder at a thirty-second of the real widths, with both halves' real shape.

    One constructor for both fixtures, because the two halves share `latent_channels`, the patch
    size and the compression ratios, and a fixture that disagreed with its opposite about any of
    those would pin a pair that cannot round-trip.

    `layers_per_block` is the encoder's alone and is passed in rather than fixed, for a reason
    that is about the fixtures and not about the model: the two halves are constructed in one
    pass of the random number generator, so widening the encoder shifts every decoder weight
    after it. The decoder fixture therefore keeps the one-block encoder it was dumped beside and
    stays byte for byte what it was; the encoder fixture asks for the real `(4, 6, 4, 2, 2)`.
    """
    from diffusers.models.autoencoders.autoencoder_kl_ltx2 import AutoencoderKLLTX2Video

    torch.manual_seed(seed)
    return AutoencoderKLLTX2Video(
        in_channels=3,
        out_channels=3,
        latent_channels=4,
        block_out_channels=(8, 16, 32, 32),
        decoder_block_out_channels=(8, 16, 16, 32),
        layers_per_block=layers_per_block,
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


def dump_decoder(out: pathlib.Path) -> None:
    """The decoder's weights and one decode of a random denormalised latent."""
    vae = _dolls_house(seed=0, layers_per_block=(1, 1, 1, 1, 1))
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


def dump_encoder(out: pathlib.Path) -> None:
    """The encoder's weights and two encodes: a nine-frame clip and a single picture.

    The picture is the fixture that matters for holding a first frame. A causal encoder gives one
    pixel frame a latent frame of its own, and if it did not, a held first frame would either
    borrow from frames that come after it or land on the wrong latent frame entirely.

    `sample_mode: "argmax"` is what both official pipelines encode with, so the mean is taken and
    the log-variance channel `conv_out` also writes is dropped rather than sampled from; the
    result is then normalised by the per-channel statistics, which the pipeline does and this
    port folds into the encoder. `scaling_factor` is read off the config rather than assumed, so
    a checkpoint carrying one other than 1 would not pass silently.
    """
    # The real checkpoint's stage counts: the constructor's default third stage holds six
    # blocks and this one holds four.
    vae = _dolls_house(seed=2, layers_per_block=(4, 6, 4, 2, 2))
    with torch.no_grad():
        # Non-trivial statistics, so a port that forgot to normalise cannot pass.
        vae.latents_mean.copy_(torch.randn(4))
        vae.latents_std.copy_(torch.rand(4) + 0.5)

    tensors = {}
    for key, value in vae.state_dict().items():
        name = _official_encoder_name(key)
        if name is None:
            continue
        if value.ndim == 5:
            # [out, in, kd, kh, kw] -> MLX's [out, kd, kh, kw, in], as the pack stores them.
            value = value.permute(0, 2, 3, 4, 1)
        tensors[f"vae_encoder.{name}"] = value.clone()

    assert vae.config.scaling_factor == 1.0, vae.config.scaling_factor
    mean = vae.latents_mean.view(1, -1, 1, 1, 1)
    std = vae.latents_std.view(1, -1, 1, 1, 1)
    for label, frames in [("clip", 9), ("picture", 1)]:
        pixels = torch.rand(1, 3, frames, 64, 96) * 2 - 1
        with torch.no_grad():
            distribution = vae.encode(pixels, return_dict=False)[0]
            latent = (distribution.mode() - mean) * vae.config.scaling_factor / std
        expected = (1, 4, 2 if frames == 9 else 1, 2, 3)
        assert tuple(latent.shape) == expected, (label, latent.shape)
        tensors[f"vae_encoder.in.pixels.{label}"] = pixels
        tensors[f"vae_encoder.out.latent.{label}"] = latent

    tensors = {name: value.float().contiguous() for name, value in tensors.items()}
    save_file(tensors, str(out / "vae_encoder.safetensors"))
    print(f"vae_encoder: {len(tensors)} tensors")


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


DUMPERS = {"vae_decoder": dump_decoder, "vae_encoder": dump_encoder, "frames": dump_frames}
