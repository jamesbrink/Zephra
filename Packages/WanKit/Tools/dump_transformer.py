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
"""Dump reference tensors for the Wan 2.2 transformer: its rotary tables, its condition
embedder, one block, the whole model with a scalar and with a per-token timestep, and the
three-step distilled schedule.

The reference is diffusers' `WanTransformer3DModel` in the TI2V-5B configuration, shrunk to a
doll's house: two heads of twelve, eight latent channels, a sixteen-wide text stream, two
blocks. The scale-shift tables and every norm's weight and bias are randomised, since the
reference initialises them near zero or at one and a port that skipped one would otherwise
pass; the linears keep their scaled default initialisation so the activations stay of order
one. Weights are saved under the checkpoint's own parameter names with a `model.` prefix;
`WanTransformerWeights` in Swift is the whole of the translation to the module tree, and the
fixtures are what pin it.

The per-token timestep is the path an image-to-video run takes: diffusers'
`WanImageToVideoPipeline` with `expand_timesteps` hands the first latent frame's tokens
timestep 0 and every other token the step's, as `transformer_conditioned` does here.
"""

import pathlib

import torch
from safetensors.torch import save_file

# The TI2V-5B configuration at doll's-house size: patch (1, 2, 2), the across-heads qk norm and
# the affine cross-attention norm are the real model's; the widths are not.
CONFIG = dict(
    patch_size=(1, 2, 2), num_attention_heads=2, attention_head_dim=12, in_channels=8,
    out_channels=8, text_dim=16, freq_dim=32, ffn_dim=32, num_layers=2, cross_attn_norm=True,
    qk_norm="rms_norm_across_heads", eps=1e-6, rope_max_seq_len=32,
)
DIM = CONFIG["num_attention_heads"] * CONFIG["attention_head_dim"]
FRAMES, HEIGHT, WIDTH = 3, 4, 4
TOKENS = FRAMES * (HEIGHT // 2) * (WIDTH // 2)
FIRST_FRAME_TOKENS = (HEIGHT // 2) * (WIDTH // 2)
TEXT_TOKENS = 5
STEP_TIMESTEPS = [1000.0, 757.0, 522.0]


def _model():
    from diffusers.models.transformers.transformer_wan import WanTransformer3DModel

    torch.manual_seed(0)
    model = WanTransformer3DModel(**CONFIG).eval()
    with torch.no_grad():
        # The linears keep their scaled default initialisation, so activations stay of order
        # one and a float32 tolerance means something; what the reference initialises to a
        # constant is randomised, so a port that skipped it would be caught.
        model.scale_shift_table.normal_()
        for block in model.blocks:
            block.scale_shift_table.normal_()
            block.norm2.weight.normal_()
            block.norm2.bias.normal_()
            for attn in (block.attn1, block.attn2):
                attn.norm_q.weight.normal_()
                attn.norm_k.weight.normal_()
    return model


def _weights(module: torch.nn.Module, prefix: str) -> dict[str, torch.Tensor]:
    return {prefix + name: value.float().contiguous() for name, value in module.state_dict().items()}


def _inputs():
    torch.manual_seed(1)
    return {
        "latent": torch.randn(1, CONFIG["in_channels"], FRAMES, HEIGHT, WIDTH),
        "text": torch.randn(1, TEXT_TOKENS, CONFIG["text_dim"]),
    }


def _apply_rotary_emb(hidden_states, freqs_cos, freqs_sin):
    """`WanAttnProcessor.__call__`'s inner `apply_rotary_emb`, which is not importable on its
    own; the block and model fixtures run the original through the attention."""
    x1, x2 = hidden_states.unflatten(-1, (-1, 2)).unbind(-1)
    cos = freqs_cos[..., 0::2]
    sin = freqs_sin[..., 1::2]
    out = torch.empty_like(hidden_states)
    out[..., 0::2] = x1 * cos - x2 * sin
    out[..., 1::2] = x1 * sin + x2 * cos
    return out.type_as(hidden_states)


def dump_rope(out: pathlib.Path) -> None:
    """The rotary tables for the doll's-house grid and a query rotated by them."""
    model = _model()
    latent = _inputs()["latent"]
    cos, sin = model.rope(latent)
    torch.manual_seed(2)
    query = torch.randn(1, TOKENS, CONFIG["num_attention_heads"], CONFIG["attention_head_dim"])
    save_file(
        {
            "in.query": query.contiguous(),
            "out.cos": cos.float().contiguous(), "out.sin": sin.float().contiguous(),
            "out.query": _apply_rotary_emb(query, cos, sin).contiguous(),
        },
        str(out / "rope.safetensors"),
    )
    print("rope: 4 tensors")


def dump_timestep(out: pathlib.Path) -> None:
    """The condition embedder on a scalar timestep and on a per-token one."""
    model = _model()
    embedder = model.condition_embedder
    text = _inputs()["text"]
    scalar = torch.tensor([757.0])
    per_token = torch.full((1, TOKENS), 757.0)
    per_token[:, :FIRST_FRAME_TOKENS] = 0.0
    with torch.no_grad():
        temb, proj, encoded, _ = embedder(scalar, text)
        temb_tokens, proj_tokens, _, _ = embedder(per_token.flatten(), text, timestep_seq_len=TOKENS)
    tensors = _weights(embedder, "model.")
    tensors.update({
        "in.timestep": scalar, "in.timestep_tokens": per_token, "in.text": text,
        "out.temb": temb.contiguous(), "out.timestep_proj": proj.contiguous(),
        "out.temb_tokens": temb_tokens.contiguous(), "out.timestep_proj_tokens": proj_tokens.contiguous(),
        "out.encoder_hidden_states": encoded.contiguous(),
    })
    save_file(tensors, str(out / "timestep.safetensors"))
    print(f"timestep: {len(tensors)} tensors")


def dump_block(out: pathlib.Path) -> None:
    """One block on a per-token modulation, `[1, seq, 6, dim]`."""
    model = _model()
    block = model.blocks[0]
    latent = _inputs()["latent"]
    cos, sin = model.rope(latent)
    torch.manual_seed(3)
    hidden = torch.randn(1, TOKENS, DIM)
    text = torch.randn(1, TEXT_TOKENS, DIM)
    temb = torch.randn(1, TOKENS, 6, DIM)
    with torch.no_grad():
        output = block(hidden, text, temb, (cos, sin))
    tensors = _weights(block, "model.")
    tensors.update({
        "in.hidden_states": hidden, "in.encoder_hidden_states": text, "in.temb": temb,
        "in.rotary_cos": cos.float().contiguous(), "in.rotary_sin": sin.float().contiguous(),
        "out.hidden_states": output.contiguous(),
    })
    save_file(tensors, str(out / "transformer_block.safetensors"))
    print(f"transformer_block: {len(tensors)} tensors")


def _dump_model(out: pathlib.Path, name: str, timestep: torch.Tensor) -> None:
    model = _model()
    inputs = _inputs()
    with torch.no_grad():
        output = model(
            hidden_states=inputs["latent"], timestep=timestep,
            encoder_hidden_states=inputs["text"], return_dict=False,
        )[0]
    tensors = _weights(model, "model.")
    tensors.update({
        "in.hidden_states": inputs["latent"], "in.timestep": timestep,
        "in.encoder_hidden_states": inputs["text"], "out.hidden_states": output.contiguous(),
    })
    save_file(tensors, str(out / f"{name}.safetensors"))
    print(f"{name}: {len(tensors)} tensors")


def dump_model(out: pathlib.Path) -> None:
    """The whole model on a scalar timestep, `[1]`: the text-to-video path."""
    _dump_model(out, "transformer_model", torch.tensor([757.0]))


def dump_conditioned(out: pathlib.Path) -> None:
    """The whole model on a per-token timestep, `[1, seq]`, with the first latent frame's
    tokens at 0 and the rest at the step's, as the image-to-video pipeline hands it."""
    timestep = torch.full((1, TOKENS), 757.0)
    timestep[:, :FIRST_FRAME_TOKENS] = 0.0
    _dump_model(out, "transformer_conditioned", timestep)


def dump_schedule(out: pathlib.Path) -> None:
    """The shift-8 flow-matching grid and the three distilled steps walked on it.

    `FlowMatchEulerDiscreteScheduler(shift=8)` builds its grid in `__init__`: a thousand sigmas
    from 1 down to 1/1000, shifted `8s / (1 + 7s)`, timesteps a thousand times that. FastWan
    runs at timesteps 1000, 757 and 522, which are not all on the grid, so each step's sigma is
    the grid entry whose timestep is nearest. The re-noising between steps is the scheduler's
    own `scale_noise`, called at the exact grid timestep it matched.
    """
    from diffusers import FlowMatchEulerDiscreteScheduler

    scheduler = FlowMatchEulerDiscreteScheduler(shift=8.0)
    sigmas, timesteps = scheduler.sigmas, scheduler.timesteps
    indices = [int((timesteps - t).abs().argmin()) for t in STEP_TIMESTEPS]
    matched = sigmas[indices]

    torch.manual_seed(4)
    tensors = {
        "sigmas": sigmas.contiguous(), "timesteps": timesteps.contiguous(),
        "step_timesteps": torch.tensor(STEP_TIMESTEPS), "step_sigmas": matched.contiguous(),
    }
    x = torch.randn(1, CONFIG["in_channels"], FRAMES, HEIGHT, WIDTH)
    tensors["in.x"] = x
    for step, index in enumerate(indices):
        velocity = torch.randn_like(x)
        denoised = x - matched[step] * velocity
        tensors[f"in.velocity.{step}"] = velocity
        tensors[f"out.denoised.{step}"] = denoised.contiguous()
        if step + 1 < len(indices):
            noise = torch.randn_like(x)
            x = scheduler.scale_noise(denoised, timesteps[indices[step + 1]].reshape(1), noise)
            tensors[f"in.noise.{step}"] = noise
            tensors[f"out.next.{step}"] = x.contiguous()
    save_file(tensors, str(out / "schedule.safetensors"))
    print(f"schedule: {len(tensors)} tensors")


DUMPERS = {
    "rope": dump_rope,
    "timestep": dump_timestep,
    "transformer_block": dump_block,
    "transformer_model": dump_model,
    "transformer_conditioned": dump_conditioned,
    "schedule": dump_schedule,
}
