"""Dump reference tensors for the Wan 2.2 video autoencoder, `diffusers.AutoencoderKLWan`.

A doll's house with the real checkpoint's shape: the same `[1, 2, 4, 4]` stage pattern read at
a twentieth of the width, one residual block a stage instead of two, four latent channels
instead of 48, and every structural choice of the 2.2 configuration kept -- `patch_size` 2,
`is_residual` with its averaged-down and duplicated-up shortcuts, the causal 3-D convolutions
with their frame cache, time halved in the last two downsamples and doubled in the first two
upsamples, and the single-head attention in the mid block. A pixel shuffle in the wrong
channel order, a cache that carries the wrong frame, or a shortcut that averages the wrong
group shows up at this size exactly as it would at the real one, and the files are small enough
to commit.

Both fixtures are made through the public `encode` and `decode`, so what they pin is the
reference's own chunking -- the first frame alone and then four at a time on the way in, one
latent frame at a time on the way out -- and the feature cache each chunk carries forward. Five
pixel frames is two chunks either way, which is what makes the cache visible: a port that ran
the clip in one pass would agree on the first frame and disagree on the rest, because the first
chunk is where the temporal resamplers are skipped.

Weights are written under the checkpoint's own names (`encoder.conv_in.weight`, `quant_conv.
weight`, and so on) in PyTorch's own layouts, `[out, in, kt, kh, kw]` for a convolution and
`[dim, 1, 1, 1]` for a norm's gain, so the Swift side loads a fixture exactly as it loads the
release. Inputs sit under `in.` and outputs under `out.`.
"""

import json
import pathlib

import torch
from safetensors.torch import save_file

# The real release's `vae/config.json`, first four of each list, so the doll's house normalises
# by numbers of the right size; the Swift `WanVAEConfiguration.wan22` carries all 48.
_LATENTS_MEAN = [-0.2289, -0.0052, -0.1323, -0.2339]
_LATENTS_STD = [0.4765, 1.0364, 0.4514, 1.1677]


def _dolls_house(seed: int):
    """The 2.2 autoencoder at a twentieth of the width, with random gains and random weights.

    `WanRMS_norm` initialises its gain to ones, which a port that skipped the gain would match
    by accident; every gain is drawn at random so the parity test sees it. `clip_output` is not
    a constructor argument in diffusers 0.40.0 and is left out: `decode` clamps to [-1, 1]
    regardless, which is what the fixture records.
    """
    from diffusers import AutoencoderKLWan

    torch.manual_seed(seed)
    vae = AutoencoderKLWan(
        base_dim=8,
        decoder_base_dim=8,
        dim_mult=[1, 1, 2, 2],
        num_res_blocks=1,
        attn_scales=[],
        temperal_downsample=[False, True, True],
        z_dim=4,
        in_channels=12,
        out_channels=12,
        patch_size=2,
        is_residual=True,
        latents_mean=_LATENTS_MEAN,
        latents_std=_LATENTS_STD,
        scale_factor_temporal=4,
        scale_factor_spatial=16,
    ).eval()
    with torch.no_grad():
        for name, parameter in vae.named_parameters():
            if name.endswith("gamma"):
                parameter.copy_(torch.rand_like(parameter) + 0.5)
    return vae


def _weights(vae, prefixes: tuple[str, ...]) -> dict[str, torch.Tensor]:
    """The state dict entries under any of `prefixes`, in PyTorch's own layouts."""
    return {
        key: value.clone()
        for key, value in vae.state_dict().items()
        if key.startswith(prefixes)
    }


def dump_encoder(out: pathlib.Path) -> None:
    """The encoder side plus `quant_conv`, and two encodes: a nine-frame clip and one picture.

    Nine frames is three chunks — the first frame alone, then four, then four — which is the
    first count that exercises the temporal downsamplers' carry from a chunk that was itself
    carried into, the rule every later chunk of a real clip follows.

    The latent is the distribution's mean, `sample_mode="argmax"` in the pipeline's words: the
    first `z_dim` channels of what `quant_conv` writes, the log-variance half dropped rather than
    sampled from. Nothing is normalised here; the pipeline does that, and the Swift
    `WanLatentNormalization` is tested against the config's numbers on its own.
    """
    vae = _dolls_house(seed=0)
    tensors = _weights(vae, ("encoder.", "quant_conv."))

    for label, frames, latent_name in [("video", 9, "latent"), ("picture", 1, "picture_latent")]:
        pixels = torch.rand(1, 3, frames, 64, 64) * 2 - 1
        with torch.no_grad():
            latent = vae.encode(pixels, return_dict=False)[0].mode()
        expected = (1, 4, 1 + (frames - 1) // 4, 4, 4)
        assert tuple(latent.shape) == expected, (label, latent.shape)
        tensors[f"in.{label}"] = pixels
        tensors[f"out.{latent_name}"] = latent

    tensors = {name: value.float().contiguous() for name, value in tensors.items()}
    save_file(tensors, str(out / "vae_encoder.safetensors"))
    print(f"vae_encoder: {len(tensors)} tensors")


def dump_decoder(out: pathlib.Path) -> None:
    """The decoder side plus `post_quant_conv`, and one decode of a three-frame latent: three
    chunks, so the temporal upsamplers' carry from a carried-into chunk is pinned.

    The latent is handed over as the decoder takes it, already denormalised; `decode` clamps
    its pixels to [-1, 1], and the fixture keeps the clamp, since the port does the same.
    """
    vae = _dolls_house(seed=1)
    tensors = _weights(vae, ("decoder.", "post_quant_conv."))

    latent = torch.randn(1, 4, 3, 4, 4)
    with torch.no_grad():
        video = vae.decode(latent, return_dict=False)[0]
    assert tuple(video.shape) == (1, 3, 9, 64, 64), video.shape
    assert video.min() >= -1 and video.max() <= 1
    tensors["in.latent"] = latent
    tensors["out.video"] = video

    tensors = {name: value.float().contiguous() for name, value in tensors.items()}
    save_file(tensors, str(out / "vae_decoder.safetensors"))
    print(f"vae_decoder: {len(tensors)} tensors")


DUMPERS = {"vae_encoder": dump_encoder, "vae_decoder": dump_decoder}
