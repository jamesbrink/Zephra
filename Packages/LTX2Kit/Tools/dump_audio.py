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
"""Dump reference tensors for LTX-2.5's audio path: the audio autoencoder's decoder and the
vocoder with its bandwidth extender.

Both at a doll's-house width with the real shape. The decoder keeps three levels widened by
`(1, 2, 4)`, three blocks a level, a causal time axis and pixel norms, at a base of eight
channels over four latent channels and eight mel bins, so its packed width (four channels
by two latent bins) is the base width the statistics are registered at, as it is in the
real model (eight by sixteen is 128). The vocoder keeps the real kernels and strides — they
are the sample arithmetic — at 128 and 64 hidden channels rather than 1536 and 512, with
every Snake parameter, sinc filter and Fourier basis randomised so a port that skips one is
caught. Weights are written under the pack's names in MLX's kernel order.
"""

import pathlib

import torch
from safetensors.torch import save_file

AUDIO_VAE = dict(
    base_channels=8, output_channels=2, ch_mult=(1, 2, 4), num_res_blocks=2, in_channels=2,
    resolution=64, latent_channels=4, norm_type="pixel", causality_axis="height",
    mid_block_add_attention=False, mel_bins=8, double_z=True,
)
LATENT_FRAMES = 5


def _vae():
    from diffusers.models.autoencoders.autoencoder_kl_ltx2_audio import AutoencoderKLLTX2Audio

    torch.manual_seed(5)
    model = AutoencoderKLLTX2Audio(**AUDIO_VAE).eval()
    with torch.no_grad():
        model.latents_mean.normal_()
        model.latents_std.uniform_(0.5, 1.5)
    return model


def _vae_pack_name(key: str) -> str | None:
    if key == "latents_mean":
        return "audio_vae.per_channel_statistics._mean_of_means"
    if key == "latents_std":
        return "audio_vae.per_channel_statistics._std_of_means"
    if key.startswith("decoder."):
        return "audio_vae." + key
    return None


def _mlx_kernel(name: str, value: torch.Tensor) -> torch.Tensor:
    """A PyTorch kernel in MLX's channels-last order: `[O, I, kh, kw]` to `[O, kh, kw, I]`,
    `[O, I, k]` to `[O, k, I]`, and a transposed convolution's `[I, O, k]` to `[O, k, I]`."""
    if value.ndim == 4:
        return value.permute(0, 2, 3, 1)
    if value.ndim == 3:
        return value.permute(1, 2, 0) if ".ups." in name or ".upsamplers." in name else value.permute(0, 2, 1)
    return value


def dump_audio_decoder(out: pathlib.Path) -> None:
    """A packed audio token sequence denormalised, unpacked and decoded to a stereo mel."""
    model = _vae()
    tensors = {}
    for name, value in model.state_dict().items():
        packed = _vae_pack_name(name)
        if packed is not None:
            tensors[packed] = _mlx_kernel(packed, value).float().contiguous()
    torch.manual_seed(6)
    width = AUDIO_VAE["latent_channels"] * (AUDIO_VAE["mel_bins"] // 4)
    tokens = torch.randn(1, LATENT_FRAMES, width)
    with torch.no_grad():
        latents = tokens * model.latents_std + model.latents_mean
        latents = latents.unflatten(2, (-1, AUDIO_VAE["mel_bins"] // 4)).transpose(1, 2)  # [1, C, L, M]
        mel = model.decode(latents, return_dict=False)[0]
    tensors.update({"in.tokens": tokens.contiguous(), "in.latent": latents.contiguous(), "out.mel": mel.contiguous()})
    save_file(tensors, str(out / "audio_decoder.safetensors"))
    print(f"audio_decoder: {len(tensors)} tensors, mel {tuple(mel.shape)}")


def _vocoder():
    from diffusers.pipelines.ltx2.vocoder import LTX2VocoderWithBWE

    torch.manual_seed(7)
    model = LTX2VocoderWithBWE(hidden_channels=128, bwe_hidden_channels=64).eval()
    with torch.no_grad():
        for name, parameter in model.named_parameters():
            if name.endswith(".alpha") or name.endswith(".beta"):
                parameter.normal_(std=0.3)
        for name, buffer in model.named_buffers():
            if name.endswith("filter") and "resampler" not in name:
                buffer.normal_(std=0.2)
            if name.endswith("mel_basis") or name.endswith("forward_basis"):
                buffer.normal_(std=0.1)
    return model


def _vocoder_pack_name(key: str) -> str | None:
    if key.startswith("resampler."):
        return None
    name = key
    if name.startswith("vocoder."):
        name = name  # the first generator keeps its prefix in the pack
    for theirs, ours in [
        ("conv_in.", "conv_pre."), ("upsamplers.", "ups."), ("resnets.", "resblocks."),
        ("act_out.", "act_post."), ("conv_out.", "conv_post."), ("downsample.filter", "downsample.lowpass.filter"),
    ]:
        name = name.replace(theirs, ours)
    return "vocoder." + name if not name.startswith("vocoder.") else name


def dump_vocoder(out: pathlib.Path) -> None:
    """A stereo log-mel through both generators to a 48 kHz waveform, with the first
    generator's 16 kHz waveform kept beside it."""
    model = _vocoder()
    tensors = {}
    for name, value in list(model.state_dict().items()):
        packed = _vocoder_pack_name(name)
        if packed is None:
            continue
        kernel = value
        if name.endswith("forward_basis") or name.endswith("inverse_basis"):
            kernel = value.permute(0, 2, 1)
        elif value.ndim == 3 and name.endswith("filter"):
            kernel = value.permute(0, 2, 1)
        else:
            kernel = _mlx_kernel(packed, value)
        tensors[packed] = kernel.float().contiguous()
    torch.manual_seed(8)
    mel = torch.randn(1, 2, 20, 64)
    with torch.no_grad():
        low = model.vocoder(mel)
        waveform = model(mel)
    tensors.update({"in.mel": mel.contiguous(), "out.low": low.contiguous(), "out.waveform": waveform.contiguous()})
    save_file(tensors, str(out / "vocoder.safetensors"))
    print(f"vocoder: {len(tensors)} tensors, low {tuple(low.shape)}, waveform {tuple(waveform.shape)}")


DUMPERS = {"audio_decoder": dump_audio_decoder, "vocoder": dump_vocoder}


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=pathlib.Path)
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    for dumper in DUMPERS.values():
        dumper(arguments.out)
