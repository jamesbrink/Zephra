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
"""`AutoencoderKLQwenImage21` at doll's-house size, both towers and the normalisation.

What this pins: **four channels in and four out**, so alpha survives the round trip, which is
2.1's headline feature and the one thing a three-channel port would lose silently; the causal
3-D convolutions that are 2-D ones with a frame axis folded away; the residual stages; the
posterior's **mode** rather than a sample, which is what `sample_mode="argmax"` asks for, so
the encoder's log-variance half is produced and never read; and the per-channel
`latents_mean` / `latents_std`, divided out after an encode and multiplied back before a
decode — a statistic read wrong shifts every colour by a plausible amount.

Written with the kit's skeleton so the seven dumpers live in one place; the doll's-house widths
are settled by the step that adds `VAEParityTests`.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

CONFIG = {
    "base_dim": 8,
    "decoder_base_dim": 12,
    "z_dim": 8,
    "dim_mult": [1, 2],
    "num_res_blocks": 1,
    "temperal_downsample": [False],
    "dropout": 0.0,
    "is_residual": True,
    "in_channels": 4,
    "out_channels": 4,
    "attn_scales": [],
}

PICTURE = (1, 4, 1, 16, 16)


def dump(out: pathlib.Path) -> None:
    from diffusers.models.autoencoders.autoencoder_kl_qwenimage_21 import (
        AutoencoderKLQwenImage21,
    )

    model = AutoencoderKLQwenImage21(**CONFIG).eval()
    channels = CONFIG["z_dim"]
    # Deliberately not zero and one: the identity would let a port that skipped the
    # normalisation altogether pass.
    mean = torch.randn(channels)
    std = torch.rand(channels) + 0.5
    picture = torch.randn(*PICTURE)

    with torch.no_grad():
        posterior = model.encode(picture).latent_dist
        latents = posterior.mode()
        normalised = (latents - mean.view(1, -1, 1, 1, 1)) / std.view(1, -1, 1, 1, 1)
        restored = normalised * std.view(1, -1, 1, 1, 1) + mean.view(1, -1, 1, 1, 1)
        decoded = model.decode(restored).sample

    tensors = {f"model.{name}": value.float().contiguous() for name, value in model.state_dict().items()}
    tensors["in.picture"] = picture.contiguous()
    tensors["in.latentsMean"] = mean.contiguous()
    tensors["in.latentsStd"] = std.contiguous()
    tensors["out.latents"] = latents.float().contiguous()
    tensors["out.normalised"] = normalised.float().contiguous()
    tensors["out.decoded"] = decoded.float().contiguous()
    save_file(tensors, str(out / "vae.safetensors"))
    print(f"vae: {len(tensors)} tensors")


def main() -> None:
    import dump_reference

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=dump_reference.default_out())
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(0)
    dump(arguments.out)


if __name__ == "__main__":
    import sys

    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    main()
