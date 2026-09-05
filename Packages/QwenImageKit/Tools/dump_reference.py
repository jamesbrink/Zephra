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
"""Dump reference tensors from the Apache-2.0 diffusers implementation.

Every fixture this writes is a claim about what the reference does, checked in Swift by the
matching test. Files are tiny on purpose: a doll's-house configuration catches a transposed axis
or a swapped modulation chunk exactly as well as a real one, and can be committed.

The dependency versions above are pinned so a fixture says what produced it; bump them
together and regenerate every fixture in the same commit.

Run with `uv run Tools/dump_reference.py --out Tests/QwenImageTests/Fixtures`. The tokenizer
fixture is the one that needs the real files rather than a doll's house: `--tokenizer DIR`
names a directory holding `vocab.json`, `merges.txt`, `tokenizer_config.json` and
`added_tokens.json` (a snapshot's `tokenizer/`); without it they are fetched from the hub.
"""

import argparse
import json
import pathlib

import torch
from safetensors.torch import save_file


def dump_rope(out: pathlib.Path) -> None:
    """QwenEmbedRope's image and text frequency tables, as real cosine/sine pairs."""
    from diffusers.models.transformers.transformer_qwenimage import QwenEmbedRope

    rope = QwenEmbedRope(theta=10000, axes_dim=[16, 56, 56], scale_rope=True)
    tensors = {}
    for label, (frames, height, width, text_length) in {
        "small": (1, 4, 4, 3),
        "wide": (1, 2, 6, 5),
        "large": (1, 64, 64, 20),
    }.items():
        image, text = rope([(frames, height, width)], max_txt_seq_len=text_length)
        tensors[f"{label}.image.cos"] = image.real.float().contiguous()
        tensors[f"{label}.image.sin"] = image.imag.float().contiguous()
        tensors[f"{label}.text.cos"] = text.real.float().contiguous()
        tensors[f"{label}.text.sin"] = text.imag.float().contiguous()
    save_file(tensors, str(out / "rope.safetensors"))
    print(f"rope: {len(tensors)} tensors")


def dump_scheduler(out: pathlib.Path) -> None:
    """The sigma ladder, for the published config, at a few step counts and image sizes."""
    import numpy as np
    from diffusers import FlowMatchEulerDiscreteScheduler

    config = {
        "base_image_seq_len": 256,
        "base_shift": 0.5,
        "invert_sigmas": False,
        "max_image_seq_len": 8192,
        "max_shift": 0.9,
        "num_train_timesteps": 1000,
        "shift": 1.0,
        "shift_terminal": 0.02,
        "stochastic_sampling": False,
        "time_shift_type": "exponential",
        "use_beta_sigmas": False,
        "use_dynamic_shifting": True,
        "use_exponential_sigmas": False,
        "use_karras_sigmas": False,
    }
    tensors = {}
    for steps, tokens in [(4, 4096), (8, 4096), (4, 1024), (20, 9216)]:
        scheduler = FlowMatchEulerDiscreteScheduler.from_config(config)
        slope = (config["max_shift"] - config["base_shift"]) / (
            config["max_image_seq_len"] - config["base_image_seq_len"]
        )
        mu = tokens * slope + config["base_shift"] - slope * config["base_image_seq_len"]
        # The pipeline does not take the scheduler's default ladder: QwenImagePipeline passes
        # linspace(1, 1/steps, steps) as the sigmas, and the shift and terminal stretch act on
        # that. Dumping the default would pin a schedule no image is ever made with.
        scheduler.set_timesteps(sigmas=np.linspace(1.0, 1 / steps, steps), mu=mu)
        tensors[f"steps{steps}.tokens{tokens}.sigmas"] = scheduler.sigmas.float().contiguous()
    save_file(tensors, str(out / "scheduler.safetensors"))
    print(f"scheduler: {len(tensors)} tensors")


def dump_latent_packing(out: pathlib.Path) -> None:
    """The pipeline's own pack/unpack, on a tensor whose values name their coordinates."""
    from diffusers.pipelines.qwenimage.pipeline_qwenimage import QwenImagePipeline

    batch, channels, height, width = 1, 16, 8, 6
    latents = torch.arange(batch * channels * height * width, dtype=torch.float32)
    latents = latents.reshape(batch, channels, height, width)
    packed = QwenImagePipeline._pack_latents(latents, batch, channels, height, width)
    save_file(
        {"latents": latents.contiguous(), "packed": packed.contiguous()},
        str(out / "latent_packing.safetensors"),
    )
    print("latent packing: 2 tensors")


def dump_text_encoder(out: pathlib.Path) -> None:
    """A doll's-house Qwen2.5 language stack: its weights, an input, and the hidden states.

    Small enough to commit, and it exercises every part that can be got backwards -- the bias on
    the query, key, and value projections, grouped-query attention, the SwiGLU gate order, and
    which hidden state Qwen-Image conditions on.
    """
    from transformers import Qwen2Config, Qwen2Model

    torch.manual_seed(7)
    config = Qwen2Config(
        hidden_size=64,
        num_hidden_layers=2,
        num_attention_heads=4,
        num_key_value_heads=2,
        intermediate_size=128,
        vocab_size=100,
        rms_norm_eps=1e-6,
        rope_theta=1000000.0,
        tie_word_embeddings=False,
        attn_implementation="eager",
    )
    model = Qwen2Model(config).eval()
    tokens = torch.tensor([[3, 17, 42, 8, 99, 1, 55]])
    with torch.no_grad():
        hidden = model(input_ids=tokens).last_hidden_state

    # Prefixed the way the published checkpoint names them, so the Swift side loads by name.
    tensors = {f"model.{key}": value.contiguous() for key, value in model.state_dict().items()}
    tensors["input_ids"] = tokens.to(torch.int32).contiguous()
    tensors["last_hidden_state"] = hidden.float().contiguous()
    save_file(tensors, str(out / "text_encoder.safetensors"))
    print(f"text encoder: {len(tensors)} tensors")


def dump_transformer(out: pathlib.Path) -> None:
    """A doll's-house MMDiT block and a two-block model, with weights, inputs, and outputs.

    Every way this can be silently wrong is structural: the modulation chunk order, which stream
    is concatenated first, the tanh flavour of GELU, and whether the final norm chunks scale
    before shift. All of them show up at any width.
    """
    from diffusers.models.transformers.transformer_qwenimage import (
        QwenEmbedRope,
        QwenImageTransformer2DModel,
        QwenImageTransformerBlock,
    )

    torch.manual_seed(11)
    dim, heads, head_dim = 32, 2, 16
    axes = [4, 6, 6]
    frames, height, width, text_length = 1, 3, 4, 5
    image_tokens = frames * height * width

    rope = QwenEmbedRope(theta=10000, axes_dim=axes, scale_rope=True)
    image_freqs, text_freqs = rope([(frames, height, width)], max_txt_seq_len=text_length)

    block = QwenImageTransformerBlock(
        dim=dim, num_attention_heads=heads, attention_head_dim=head_dim
    ).eval()
    image = torch.randn(1, image_tokens, dim)
    text = torch.randn(1, text_length, dim)
    conditioning = torch.randn(1, dim)
    with torch.no_grad():
        text_out, image_out = block(
            hidden_states=image,
            encoder_hidden_states=text,
            encoder_hidden_states_mask=None,
            temb=conditioning,
            image_rotary_emb=(image_freqs, text_freqs),
        )

    tensors = {f"block.{k}": v.contiguous() for k, v in block.state_dict().items()}
    tensors.update({
        "block.in.image": image.contiguous(),
        "block.in.text": text.contiguous(),
        "block.in.conditioning": conditioning.contiguous(),
        "block.in.image_freqs.cos": image_freqs.real.float().contiguous(),
        "block.in.image_freqs.sin": image_freqs.imag.float().contiguous(),
        "block.in.text_freqs.cos": text_freqs.real.float().contiguous(),
        "block.in.text_freqs.sin": text_freqs.imag.float().contiguous(),
        "block.out.image": image_out.contiguous(),
        "block.out.text": text_out.contiguous(),
    })
    save_file(tensors, str(out / "transformer_block.safetensors"))
    print(f"transformer block: {len(tensors)} tensors")

    # The whole stack, two blocks deep, to catch the top and tail wiring and the 60-way loop.
    torch.manual_seed(13)
    joint_dim = 24
    model = QwenImageTransformer2DModel(
        patch_size=2,
        in_channels=8,
        out_channels=2,
        num_layers=2,
        attention_head_dim=head_dim,
        num_attention_heads=heads,
        joint_attention_dim=joint_dim,
        axes_dims_rope=axes,
    ).eval()
    latents = torch.randn(1, image_tokens, 8)
    encoder = torch.randn(1, text_length, joint_dim)
    timestep = torch.tensor([0.7])
    with torch.no_grad():
        prediction = model(
            hidden_states=latents,
            encoder_hidden_states=encoder,
            # All-true is equivalent to no mask, and it is how the model learns the text length.
            encoder_hidden_states_mask=torch.ones(1, text_length, dtype=torch.bool),
            timestep=timestep,
            img_shapes=[(frames, height, width)],
            return_dict=False,
        )[0]

    tensors = {f"model.{k}": v.contiguous() for k, v in model.state_dict().items()}
    tensors.update({
        "model.in.latents": latents.contiguous(),
        "model.in.text": encoder.contiguous(),
        "model.in.timestep": timestep.contiguous(),
        "model.out.prediction": prediction.contiguous(),
    })
    save_file(tensors, str(out / "transformer_model.safetensors"))
    print(f"transformer model: {len(tensors)} tensors")


def dump_vae(out: pathlib.Path) -> None:
    """A doll's-house autoencoder, both ways, with weights, latents, and pixels.

    Single-frame work is the whole claim being checked here: the reference runs 3-D causal
    convolutions over a one-frame tensor, and this port replaces each with the 2-D convolution it
    reduces to. If that reduction is wrong, this fixture says so.

    The encode half adds two claims of its own. The reference skips a downsampler's `time_conv`
    for the first chunk of a sequence -- and a still image is only ever the first chunk -- so a
    port that ran it would not match. And `quant_conv` is applied inside `_encode`, before the
    diagonal Gaussian is formed, so the mode this dumps is the mode of the post-`quant_conv`
    parameters, not of the encoder's raw output.
    """
    from diffusers import AutoencoderKLQwenImage

    torch.manual_seed(17)
    vae = AutoencoderKLQwenImage(
        base_dim=8,
        z_dim=4,
        dim_mult=[1, 2],
        num_res_blocks=1,
        attn_scales=[],
        temperal_downsample=[True],
        latents_mean=[0.1, -0.2, 0.3, -0.4],
        latents_std=[1.5, 0.8, 1.2, 0.9],
    ).eval()

    latent = torch.randn(1, 4, 1, 6, 6)
    mean = torch.tensor(vae.config.latents_mean).view(1, 4, 1, 1, 1)
    std = torch.tensor(vae.config.latents_std).view(1, 4, 1, 1, 1)
    # One spatial halving for a dim_mult of length two, so the picture is twice the latent.
    picture = torch.rand(1, 3, 1, 24, 24) * 2 - 1
    with torch.no_grad():
        pixels = vae.decode(latent * std + mean, return_dict=False)[0]
        encoded = vae.encode(picture).latent_dist.mode()

    tensors = {f"vae.{k}": v.contiguous() for k, v in vae.state_dict().items()}
    tensors["vae.in.latent"] = latent.contiguous()
    tensors["vae.out.pixels"] = pixels.contiguous()
    tensors["vae.in.pixels"] = picture.contiguous()
    # Normalised the way an image-to-image pipeline normalises it, which makes this the exact
    # counterpart of `vae.in.latent`: the scale the denoising loop works in, both ways.
    tensors["vae.out.latent"] = ((encoded - mean) / std).contiguous()
    save_file(tensors, str(out / "vae.safetensors"))
    print(f"vae: {len(tensors)} tensors")


TOKENIZER_REPOSITORY = "Qwen/Qwen-Image-2512"

# Every way an assembled pre-tokenizer could disagree with Qwen2's own: hyphens and
# contractions, digits one at a time, runs of newlines and spaces, merges that begin with `#`,
# a script outside Latin, emoji, an accent as a combining mark (which NFC folds), brackets and
# quotes, and nothing at all. The wrapped template is added by `dump_tokenizer`.
TOKENIZER_CASES = [
    "high-quality, black-and-white",
    "well-known",
    "state-of-the-art",
    "it's, isn't, we've",
    "don't stop",
    "I'LL",
    "###",
    "#hashtag ### markdown",
    "12345",
    "1,024 x 768",
    "3.14159",
    "a\n\nb",
    "line one\nline two\r\nthree",
    "x  \n y",
    "  two spaces",
    "trailing space ",
    "tab\tseparated",
    "café naïve",
    "e\u0301",  # a combining acute, which NFC folds into the precomposed letter
    "日本語のテキスト",
    "emoji \U0001f3a8 test",
    '"quoted"',
    "(parenthetical) [bracketed] {braced}",
    "",
]


def dump_tokenizer(out: pathlib.Path, tokenizer_directory: pathlib.Path | None) -> None:
    """Token ids from the Hugging Face tokenizer, for the port's assembled one to reproduce.

    Not a doll's house: this is the real vocabulary and merge list, because what is being
    checked is the assembly of those files into a fast tokenizer -- the pre-tokenizer's regex,
    the normalizer, and which lines of `merges.txt` are merges. The template and
    `prefix_count` come from the pipeline itself (`prompt_template_encode` and the `drop_idx`
    it throws away), so the Swift side's copy of both is checked against the reference's.
    """
    from importlib.metadata import version

    from diffusers.pipelines.qwenimage.pipeline_qwenimage import QwenImagePipeline
    from transformers import AutoTokenizer

    if tokenizer_directory is not None:
        tokenizer = AutoTokenizer.from_pretrained(str(tokenizer_directory))
        revision = "local"
    else:
        tokenizer = AutoTokenizer.from_pretrained(TOKENIZER_REPOSITORY, subfolder="tokenizer")
        revision = "hub"
    pipeline = QwenImagePipeline(
        scheduler=None, vae=None, text_encoder=None, tokenizer=tokenizer, transformer=None
    )
    template = pipeline.prompt_template_encode

    def ids(text: str) -> list[int]:
        return tokenizer(text, add_special_tokens=False)["input_ids"]

    prefix_count = len(ids(template.split("{}")[0]))
    assert prefix_count == pipeline.prompt_template_encode_start_idx, prefix_count
    cases = TOKENIZER_CASES + [template.format("a red cube")]
    header = {
        "transformers": version("transformers"),
        "tokenizers": version("tokenizers"),
        "revision": revision,
        "template": template,
        "prefix_count": prefix_count,
    }
    # One case per line, so a change to the reference reads as one line in a diff.
    body = ",\n".join(
        "    " + json.dumps({"text": text, "ids": ids(text)}, ensure_ascii=False)
        for text in cases
    )
    fields = "".join(
        f"  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},\n"
        for key, value in header.items()
    )
    (out / "tokenizer_ids.json").write_text(
        "{\n" + fields + '  "cases": [\n' + body + "\n  ]\n}\n", encoding="utf-8"
    )
    print(f"tokenizer: {len(cases)} cases, prefix {prefix_count}")


def write_versions(out: pathlib.Path) -> None:
    """Records which versions of the reference stack wrote the fixtures beside it."""
    import json
    from importlib.metadata import version

    packages = ["torch", "diffusers", "transformers", "tokenizers", "safetensors", "numpy"]
    (out / "versions.json").write_text(
        json.dumps({name: version(name) for name in packages}, indent=2) + "\n"
    )
    print("versions: " + ", ".join(f"{name} {version(name)}" for name in packages))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--only", nargs="*", default=None)
    parser.add_argument(
        "--tokenizer",
        type=pathlib.Path,
        default=None,
        help="a directory holding Qwen-Image's tokenizer files; fetched from the hub when absent",
    )
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)

    torch.manual_seed(0)
    dumpers = {
        "rope": dump_rope,
        "scheduler": dump_scheduler,
        "latent_packing": dump_latent_packing,
        "text_encoder": dump_text_encoder,
        "transformer": dump_transformer,
        "vae": dump_vae,
        "tokenizer": lambda out: dump_tokenizer(out, arguments.tokenizer),
    }
    for name, dumper in dumpers.items():
        if arguments.only and name not in arguments.only:
            continue
        dumper(arguments.out)
    write_versions(arguments.out)


if __name__ == "__main__":
    main()
