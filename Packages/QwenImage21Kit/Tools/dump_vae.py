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
"""`AutoencoderKLQwenImage21`, at doll's-house size and at the real one.

What this pins: **four channels in and four out**, so alpha survives the round trip, which is
2.1's headline feature and the one thing a three-channel port would lose silently; the causal
3-D convolutions that are 2-D ones with a frame axis folded away; the residual stages and their
parameter-free average-down and duplicate-up shortcuts; the posterior's **mode** rather than a
sample, which is what `sample_mode="argmax"` asks for, so the encoder's log-variance half is
produced and never read; and the per-channel `latents_mean` / `latents_std`, divided out after
an encode and multiplied back before a decode -- a statistic read wrong shifts every colour by
a plausible amount.

Two fixtures, because they answer two different questions.

`vae.safetensors` is a doll's house: a configuration small enough to commit its weights beside
its activations, so the architecture is pinned on any Mac with no 33 GB release anywhere near
it. Its `dim_mult` and `temperal_downsample` are chosen so that every shape the real tree takes
appears once -- a stage that folds time and one that does not, a stage that neither folds nor
downsamples, an `upsample3d` and an `upsample2d`, and residual blocks with and without a
`conv_shortcut`.

`vae_real.safetensors` is the published autoencoder itself. It is only 337.74 M parameters, so
unlike the transformer and the text encoder it can actually be run here, and a doll's house
cannot catch a scale read off the wrong axis of a 96-channel stage. It carries a whole encode,
a whole decode, and the input and output of every stage of both, so a parity failure bisects to
one block instead of to "the autoencoder".

Run: `QWEN_IMAGE_21_SNAPSHOT=... uv run Tools/dump_vae.py`.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

# The doll's house. `dim_mult` has three entries and `temperal_downsample` two, which is the
# real file's relationship (one fewer): stage 0 halves space alone, stage 1 halves space and
# folds time, stage 2 does neither. Widths differ between the halves as the real config's do.
CONFIG = {
    "base_dim": 8,
    "decoder_base_dim": 12,
    "z_dim": 8,
    "dim_mult": [1, 2, 2],
    "num_res_blocks": 1,
    "temperal_downsample": [False, True],
    "dropout": 0.0,
    "is_residual": True,
    "in_channels": 4,
    "out_channels": 4,
    "attn_scales": [],
}

# A frame axis of one, because that is the only shape a still image ever takes here.
PICTURE = (1, 4, 1, 16, 16)
# Big enough that the encoder's four halvings leave a 4 x 4 latent, small enough to commit.
REAL_PICTURE = (1, 4, 1, 64, 64)
# The bisect runs at a quarter of that, so a stage's whole feature map is kilobytes.
BISECT_PICTURE = (1, 4, 1, 32, 32)
REAL_LATENT = (1, 64, 1, 4, 4)
BISECT_LATENT = (1, 64, 1, 2, 2)


def _alpha_edge(shape: tuple[int, ...]) -> torch.Tensor:
    """Seeded noise with a hard alpha edge down the middle.

    Noise alone would not say whether the alpha channel is carried or quietly replaced with an
    opaque one: an autoencoder that dropped it would still return something noise-shaped. A
    step from fully transparent to fully opaque is the thing a three-channel port cannot fake.
    """
    picture = torch.randn(*shape).clamp(-1.0, 1.0)
    width = shape[-1]
    picture[:, 3] = -1.0
    picture[:, 3, :, :, width // 2 :] = 1.0
    return picture.contiguous()


def _stage_taps(model, names: list[str]) -> tuple[dict[str, torch.Tensor], list]:
    """Forward hooks recording what each named submodule hands on.

    Outputs only. Each stage's input is the stage before it's output, and safetensors refuses
    to write two names over one allocation -- the first input of the chain is written beside
    these as `bisect.picture` or `bisect.latent`.
    """
    recorded: dict[str, torch.Tensor] = {}
    handles = []
    for name in names:
        module = model.get_submodule(name)

        def record(_module, _args, output, name=name):
            tensor = output[0] if isinstance(output, tuple) else output
            recorded[f"tap.{name}"] = tensor.detach().clone().float().contiguous()

        handles.append(module.register_forward_hook(record))
    return recorded, handles


def dump_dolls_house(out: pathlib.Path) -> None:
    from diffusers.models.autoencoders.autoencoder_kl_qwenimage21 import (
        AutoencoderKLQwenImage21,
    )

    model = AutoencoderKLQwenImage21(**CONFIG).eval()
    channels = CONFIG["z_dim"]
    # Deliberately not zero and one: the identity would let a port that skipped the
    # normalisation altogether pass.
    mean = torch.randn(channels)
    std = torch.rand(channels) + 0.5
    picture = _alpha_edge(PICTURE)

    with torch.no_grad():
        latents = model.encode(picture).latent_dist.mode()
        normalised = (latents - mean.view(1, -1, 1, 1, 1)) / std.view(1, -1, 1, 1, 1)
        restored = normalised * std.view(1, -1, 1, 1, 1) + mean.view(1, -1, 1, 1, 1)
        decoded = model.decode(restored).sample

    tensors = {
        f"model.{name}": value.float().contiguous() for name, value in model.state_dict().items()
    }
    # The decoder's stages over the same latent, so a doll's-house failure bisects the way the
    # published one does.
    names = ["post_quant_conv", "decoder.conv_in", "decoder.mid_block"] + [
        f"decoder.up_blocks.{index}" for index in range(len(CONFIG["dim_mult"]))
    ] + ["decoder.conv_out"]
    recorded, handles = _stage_taps(model, names)
    with torch.no_grad():
        model.decode(restored)
    for handle in handles:
        handle.remove()
    tensors.update(recorded)

    tensors["in.picture"] = picture
    tensors["in.latentsMean"] = mean.contiguous()
    tensors["in.latentsStd"] = std.contiguous()
    tensors["out.latents"] = latents.float().contiguous()
    tensors["out.normalised"] = normalised.float().contiguous()
    tensors["out.decoded"] = decoded.float().contiguous()
    save_file(tensors, str(out / "vae.safetensors"))
    print(f"vae: {len(tensors)} tensors")


def dump_real(out: pathlib.Path, snapshot: pathlib.Path) -> None:
    from diffusers.models.autoencoders.autoencoder_kl_qwenimage21 import (
        AutoencoderKLQwenImage21,
    )

    model = AutoencoderKLQwenImage21.from_pretrained(
        str(snapshot / "vae"), torch_dtype=torch.float32
    ).eval()
    mean = torch.tensor(model.config.latents_mean).view(1, -1, 1, 1, 1)
    std = torch.tensor(model.config.latents_std).view(1, -1, 1, 1, 1)

    tensors: dict[str, torch.Tensor] = {
        "config.latentsMean": mean.flatten().contiguous(),
        "config.latentsStd": std.flatten().contiguous(),
    }

    torch.manual_seed(1)
    picture = _alpha_edge(REAL_PICTURE)
    latent_in = torch.randn(*REAL_LATENT)
    with torch.no_grad():
        encoded = model.encode(picture).latent_dist.mode()
        normalised = (encoded - mean) / std
        decoded = model.decode(latent_in).sample
    tensors["real.picture"] = picture
    tensors["real.encoded"] = encoded.float().contiguous()
    tensors["real.normalised"] = normalised.float().contiguous()
    tensors["real.latent"] = latent_in.contiguous()
    tensors["real.decoded"] = decoded.float().contiguous()

    # Encoder stages, at a quarter of the picture so a whole feature map is kilobytes.
    encoder_names = ["encoder.conv_in"] + [
        f"encoder.down_blocks.{index}" for index in range(5)
    ] + ["encoder.mid_block", "encoder.conv_out", "quant_conv"]
    recorded, handles = _stage_taps(model, encoder_names)
    torch.manual_seed(2)
    bisect_picture = _alpha_edge(BISECT_PICTURE)
    with torch.no_grad():
        model.encode(bisect_picture)
    for handle in handles:
        handle.remove()
    tensors["bisect.picture"] = bisect_picture
    tensors.update(recorded)

    # Decoder stages, from a latent small enough that the last one is still kilobytes.
    decoder_names = ["post_quant_conv", "decoder.conv_in", "decoder.mid_block"] + [
        f"decoder.up_blocks.{index}" for index in range(5)
    ] + ["decoder.conv_out"]
    recorded, handles = _stage_taps(model, decoder_names)
    torch.manual_seed(3)
    bisect_latent = torch.randn(*BISECT_LATENT)
    with torch.no_grad():
        model.decode(bisect_latent)
    for handle in handles:
        handle.remove()
    tensors["bisect.latent"] = bisect_latent.contiguous()
    tensors.update(recorded)

    save_file(tensors, str(out / "vae_real.safetensors"))
    megabytes = sum(t.numel() * 4 for t in tensors.values()) / 1e6
    print(f"vae_real: {len(tensors)} tensors, {megabytes:.1f} MB")


def dump(out: pathlib.Path) -> None:
    import dump_reference

    dump_dolls_house(out)
    dump_real(out, dump_reference.snapshot())


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
