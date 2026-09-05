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
"""Dump reference tensors for the FLUX.2 autoencoder, both towers.

A doll's-house autoencoder: two stages instead of four, four latent channels instead of
thirty-two, four norm groups instead of thirty-two. Every structural mistake worth catching --
a transposed convolution kernel, the encoder's asymmetric downsample padding, the mean and the
log-variance the wrong way round, a batch-norm statistic skipped -- shows up at this size
exactly as it would at the real one, and the file is small enough to commit.

The running statistics are deliberately randomised. `nn.BatchNorm2d` initialises them to zero
and one, which is the identity: with the defaults left alone, a port that forgot to normalise
at all would pass.
"""

import pathlib

import torch
from safetensors.torch import save_file


def dump(out: pathlib.Path) -> None:
    """The autoencoder's weights, an encode, and a decode, at doll's-house size."""
    from diffusers.models.autoencoders.autoencoder_kl_flux2 import AutoencoderKLFlux2
    from diffusers.pipelines.flux2.pipeline_flux2_klein import Flux2KleinPipeline

    torch.manual_seed(0)
    latent_channels = 4
    patch_size = [2, 2]
    packed_channels = latent_channels * patch_size[0] * patch_size[1]

    vae = AutoencoderKLFlux2(
        in_channels=3,
        out_channels=3,
        down_block_types=("DownEncoderBlock2D",) * 2,
        up_block_types=("UpDecoderBlock2D",) * 2,
        block_out_channels=[8, 16],
        layers_per_block=1,
        act_fn="silu",
        latent_channels=latent_channels,
        norm_num_groups=4,
        sample_size=32,
        use_quant_conv=True,
        use_post_quant_conv=True,
        mid_block_add_attention=True,
        batch_norm_eps=1e-4,
        patch_size=patch_size,
    ).eval()

    with torch.no_grad():
        # Non-trivial statistics, so that a dropped normalisation cannot pass.
        vae.bn.running_mean.copy_(torch.randn(packed_channels))
        vae.bn.running_var.copy_(torch.rand(packed_channels) + 0.5)

    mean = vae.bn.running_mean.view(1, -1, 1, 1)
    spread = torch.sqrt(vae.bn.running_var.view(1, -1, 1, 1) + vae.config.batch_norm_eps)

    tensors = {f"vae.{name}": value.clone() for name, value in vae.state_dict().items()}

    # Encode, exactly as `Flux2KleinPipeline._encode_vae_image` does it: the posterior's mean
    # (the pipeline asks `retrieve_latents` for "argmax"), then patchify, then normalise -- the
    # normalisation is in patchified space, which is the only space the statistics fit.
    image = torch.rand(1, 3, 32, 32) * 2 - 1
    with torch.no_grad():
        latents = vae.encode(image).latent_dist.mode()
        encoded = (Flux2KleinPipeline._patchify_latents(latents) - mean) / spread

    # Decode, as the end of `Flux2KleinPipeline.__call__` does it: denormalise, unpatchify,
    # then the decoder. Saved unclipped; the port clips to -1...1 the way the image processor
    # does, so the Swift side compares against a clipped copy of this.
    packed = torch.randn(1, packed_channels, 4, 4)
    with torch.no_grad():
        unpacked = Flux2KleinPipeline._unpatchify_latents(packed * spread + mean)
        pixels = vae.decode(unpacked, return_dict=False)[0]

    tensors["vae.in.image"] = image
    tensors["vae.out.packed"] = encoded
    tensors["vae.in.packed"] = packed
    tensors["vae.out.pixels"] = pixels

    tensors = {name: value.float().contiguous() for name, value in tensors.items()}
    save_file(tensors, str(out / "vae.safetensors"))
    print(f"vae: {len(tensors)} tensors, pixels in [{pixels.min():.3f}, {pixels.max():.3f}]")
