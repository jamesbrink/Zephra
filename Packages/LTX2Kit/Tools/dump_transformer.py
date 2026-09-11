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
"""Dump reference tensors for the LTX-2 video transformer: its rotary tables, its timestep
modulation, one block, and the whole model, all video lane only.

The reference is diffusers' `LTX2VideoTransformer3DModel`, which always carries an audio lane.
The block and model fixtures are dumped with `use_a2v_cross_attention=False` (block) and
`isolate_modalities=True` (model), so the video output owes nothing to the dummy audio it is
handed and equals the official model's `audio=None` forward, which is the one a video-only
pack runs. Only the video outputs are kept.

Weights are saved under the names the `mlx-community` pack uses (`patchify_proj`,
`adaln_single`, `attn1.q_norm`, `ff.proj_in`, `to_out`), which are this port's module paths;
`_pack_name` is the whole of that translation. The first latent frame's tokens carry the
keyframe embedding, as the official pipeline adds it unconditionally (`_MarkedPatchify`).
"""

import pathlib

import torch
from safetensors.torch import save_file

# A doll's house: two heads of sixteen, so the rotary ladder is five per axis and pads by one.
# The text width equals the stream's, as in the real model: the prompt table is `[2, dim]` and
# is applied to the text directly, so the two cannot differ.
VIDEO = dict(
    in_channels=8, out_channels=8, num_attention_heads=2, attention_head_dim=16,
    cross_attention_dim=32, num_layers=2, gated_attn=True, cross_attn_mod=True,
    rope_type="split", ff_bias=False, use_prompt_adaln_single=True,
    use_keyframes_abs_pos_embedding=True, use_prompt_embeddings=False,
    rope_double_precision=True, norm_eps=1e-6, caption_channels=16,
)
AUDIO = dict(
    audio_in_channels=8, audio_out_channels=8, audio_num_attention_heads=2,
    audio_attention_head_dim=8, audio_cross_attention_dim=16, audio_gated_attn=True,
    audio_cross_attn_mod=True, audio_ff_bias=True,
)
FRAMES, HEIGHT, WIDTH, FPS = 3, 2, 4, 24.0
TOKENS = FRAMES * HEIGHT * WIDTH
TEXT_TOKENS = 5
PREFIX_RENAMES = [
    ("proj_in.", "patchify_proj."),
    ("time_embed.", "adaln_single."),
    ("prompt_adaln.", "prompt_adaln_single."),
]
INFIX_RENAMES = [
    (".linear_1.", ".linear1."),
    (".linear_2.", ".linear2."),
    (".norm_q.", ".q_norm."),
    (".norm_k.", ".k_norm."),
    (".to_out.0.", ".to_out."),
    (".ff.net.0.proj.", ".ff.proj_in."),
    (".ff.net.2.", ".ff.proj_out."),
]
AUDIO_MARKERS = ("audio", "a2v", "v2a", "av_cross")


def _pack_name(key: str) -> str | None:
    """A diffusers parameter name as the pack spells it, or None for the audio lane."""
    if any(marker in key for marker in AUDIO_MARKERS):
        return None
    for before, after in PREFIX_RENAMES:
        if key.startswith(before):
            key = after + key[len(before):]
    padded = "." + key
    for before, after in INFIX_RENAMES:
        padded = padded.replace(before, after)
    return padded[1:]


def _weights(module: torch.nn.Module, prefix: str) -> dict[str, torch.Tensor]:
    tensors = {}
    for name, value in module.state_dict().items():
        packed = _pack_name(name)
        if packed is not None:
            tensors[prefix + packed] = value.float().contiguous()
    return tensors


def _model():
    from diffusers.models.transformers.transformer_ltx2 import LTX2VideoTransformer3DModel

    torch.manual_seed(0)
    model = LTX2VideoTransformer3DModel(**VIDEO, **AUDIO).eval()
    with torch.no_grad():
        # Zero-initialised in the reference; randomised so a port that skips it is caught.
        model.keyframes_abs_pos_embedding.normal_()
        for block in model.transformer_blocks:
            block.scale_shift_table.normal_()
            block.prompt_scale_shift_table.normal_()
            for attn in (block.attn1, block.attn2):
                attn.to_gate_logits.weight.normal_()
                attn.to_gate_logits.bias.normal_()
                attn.norm_q.weight.normal_()
                attn.norm_k.weight.normal_()
    return model


def dump_rope(out: pathlib.Path) -> None:
    """Cosine and sine tables for the doll's-house clip, and for a one-axis sequence the way the
    text connector positions its tokens."""
    model = _model()
    coords = model.rope.prepare_video_coords(1, FRAMES, HEIGHT, WIDTH, "cpu", fps=FPS)
    cos, sin = model.rope(coords)
    midpoints = ((coords[..., 0] + coords[..., 1]) / 2)[0]  # [3, tokens]
    from diffusers.models.transformers.transformer_ltx2 import LTX2AudioVideoRotaryPosEmbed

    one_axis = LTX2AudioVideoRotaryPosEmbed(
        dim=32, base_num_frames=4096, theta=10000.0, modality="video", rope_type="split",
        num_attention_heads=2, double_precision=True)
    starts = torch.arange(6, dtype=torch.float32)
    line = torch.stack([starts, starts + 1], dim=-1)[None, None]  # [1, 1, 6, 2]
    cos1, sin1 = one_axis(line)
    save_file(
        {
            "video.midpoints": midpoints.contiguous(),
            "video.cos": cos.float().contiguous(), "video.sin": sin.float().contiguous(),
            "line.positions": ((line[..., 0] + line[..., 1]) / 2)[0].contiguous(),
            "line.cos": cos1.float().contiguous(), "line.sin": sin1.float().contiguous(),
        },
        str(out / "rope.safetensors"),
    )
    print("rope: 6 tensors")


def dump_timestep(out: pathlib.Path) -> None:
    """The nine-row adaLN-single head on three noise levels."""
    model = _model()
    sigma = torch.tensor([1.0, 0.725, 0.421875])
    with torch.no_grad():
        modulation, embedded = model.time_embed(sigma * 1000, batch_size=3, hidden_dtype=torch.float32)
    tensors = _weights(model.time_embed, "model.")
    tensors.update({"in.sigma": sigma, "out.modulation": modulation.contiguous(), "out.embedded": embedded.contiguous()})
    save_file(tensors, str(out / "timestep.safetensors"))
    print(f"timestep: {len(tensors)} tensors")


def _inputs():
    torch.manual_seed(1)
    return {
        "hidden": torch.randn(1, TOKENS, VIDEO["num_attention_heads"] * VIDEO["attention_head_dim"]),
        "text": torch.randn(1, TEXT_TOKENS, VIDEO["cross_attention_dim"]),
        "audio": torch.randn(1, 4, AUDIO["audio_num_attention_heads"] * AUDIO["audio_attention_head_dim"]),
        "audio_text": torch.randn(1, TEXT_TOKENS, AUDIO["audio_cross_attention_dim"]),
    }


def dump_block(out: pathlib.Path) -> None:
    """One block, video lane, with the audio-to-video cross-attention switched off."""
    model = _model()
    block = model.transformer_blocks[0]
    dim, audio_dim = 32, 16
    inputs = _inputs()
    torch.manual_seed(2)
    temb = torch.randn(1, 1, 9 * dim)
    temb_prompt = torch.randn(1, 1, 2 * dim)
    coords = model.rope.prepare_video_coords(1, FRAMES, HEIGHT, WIDTH, "cpu", fps=FPS)
    rotary = model.rope(coords)
    audio_rotary = model.audio_rope(model.audio_rope.prepare_audio_coords(1, 4, "cpu"))
    with torch.no_grad():
        video, _ = block(
            hidden_states=inputs["hidden"], audio_hidden_states=inputs["audio"],
            encoder_hidden_states=inputs["text"], audio_encoder_hidden_states=inputs["audio_text"],
            temb=temb, temb_audio=torch.randn(1, 1, 9 * audio_dim),
            temb_ca_scale_shift=torch.randn(1, 1, 4 * dim), temb_ca_audio_scale_shift=torch.randn(1, 1, 4 * audio_dim),
            temb_ca_gate=torch.randn(1, 1, dim), temb_ca_audio_gate=torch.randn(1, 1, audio_dim),
            temb_prompt=temb_prompt, temb_prompt_audio=torch.randn(1, 1, 2 * audio_dim),
            video_rotary_emb=rotary, audio_rotary_emb=audio_rotary,
            use_a2v_cross_attention=False, use_v2a_cross_attention=False,
        )
    tensors = _weights(block, "model.")
    tensors.update({
        "in.hidden": inputs["hidden"], "in.text": inputs["text"],
        "in.modulation": temb.reshape(1, 1, 9, dim).contiguous(), "in.prompt": temb_prompt.reshape(1, 1, 2, dim).contiguous(),
        "out.hidden": video.contiguous(),
    })
    save_file(tensors, str(out / "transformer_block.safetensors"))
    print(f"transformer_block: {len(tensors)} tensors")


class _MarkedPatchify(torch.nn.Module):
    """`proj_in` followed by the keyframe embedding on the first latent frame's tokens.

    diffusers 0.40.0 carries the `keyframes_abs_pos_embedding` parameter but its forward has no
    way to apply it; the official pipeline adds it to the first latent frame of every clip
    unconditionally, and so does this port, so the fixture is made to match the official model.
    """

    def __init__(self, linear, embedding, marked):
        super().__init__()
        self.linear, self.embedding, self.marked = linear, embedding, marked

    def forward(self, x):
        x = self.linear(x)
        x[:, : self.marked] = x[:, : self.marked] + self.embedding
        return x


def dump_model(out: pathlib.Path) -> None:
    """The whole two-layer model with the modalities isolated and the first frame marked."""
    model = _model()
    tensors = _weights(model, "model.")
    inputs = _inputs()
    latent = torch.randn(1, TOKENS, VIDEO["in_channels"])
    sigma = torch.tensor([0.725])
    model.proj_in = _MarkedPatchify(model.proj_in, model.keyframes_abs_pos_embedding, HEIGHT * WIDTH)
    with torch.no_grad():
        video, _ = model(
            hidden_states=latent, audio_hidden_states=torch.randn(1, 4, AUDIO["audio_in_channels"]),
            encoder_hidden_states=inputs["text"], audio_encoder_hidden_states=inputs["audio_text"],
            timestep=sigma * 1000, sigma=sigma * 1000,
            num_frames=FRAMES, height=HEIGHT, width=WIDTH, fps=FPS, audio_num_frames=4,
            isolate_modalities=True, return_dict=False,
        )
    tensors.update({"in.tokens": latent, "in.text": inputs["text"], "in.sigma": sigma, "out.tokens": video.contiguous()})
    save_file(tensors, str(out / "transformer_model.safetensors"))
    print(f"transformer_model: {len(tensors)} tensors")


def dump_conditioned(out: pathlib.Path) -> None:
    """The same model with a first frame held, and the conditioning arithmetic around it.

    Holding a frame is a per-token noise level. `timestep` becomes `[1, tokens]` with the first
    latent frame's tokens at `sigma * (1 - strength)` and the rest at `sigma`, while the scalar
    `sigma` kwarg the prompt's own adaLN reads stays what it was; the reference is handed exactly
    that and decides for itself which modulation is per-token and which is not, rather than being
    fed a modulation tensor computed here.

    Two strengths: 1, where the frame is held exactly and the difference from the plain forward
    is largest, and 0.6, where the field takes two values neither of which is the plain sigma's.

    The step arithmetic beside it is `pipeline_ltx2_condition.py`'s, and it is the whole of what
    a conditioned step does around the model: `x0 = sample - v * sigma` at the **scalar** sigma,
    the blend into `x0` space (never velocity space, which is what the reference's own comment
    warns about), and the conversion back. The sampler step that follows is not dumped: the
    reference pipeline drives a `FlowMatchEulerDiscreteScheduler` and this port walks LTX-2.5's
    own ancestral Euler ladder, which `LTX2DistilledScheduleTests` pins separately, so a
    scheduler step dumped here would pin the wrong one.
    """
    model = _model()
    tensors = _weights(model, "model.")
    inputs = _inputs()
    latent = torch.randn(1, TOKENS, VIDEO["in_channels"])
    sigma = torch.tensor([0.725])
    marked = HEIGHT * WIDTH
    model.proj_in = _MarkedPatchify(model.proj_in, model.keyframes_abs_pos_embedding, marked)

    mask = torch.zeros(1, TOKENS, 1)
    mask[:, :marked] = 1.0
    for strength in (1.0, 0.6):
        timestep = (sigma[:, None] * 1000) * (1 - mask[..., 0] * strength)  # [1, tokens]
        with torch.no_grad():
            video, _ = model(
                hidden_states=latent,
                audio_hidden_states=torch.randn(1, 4, AUDIO["audio_in_channels"]),
                encoder_hidden_states=inputs["text"],
                audio_encoder_hidden_states=inputs["audio_text"],
                # The audio lane keeps the scalar, as the reference's own image-to-video
                # pipeline passes it: without that it is handed the video's per-token field and
                # tries to modulate four audio tokens with twenty-four video ones.
                timestep=timestep, audio_timestep=sigma * 1000, sigma=sigma * 1000,
                num_frames=FRAMES, height=HEIGHT, width=WIDTH, fps=FPS, audio_num_frames=4,
                isolate_modalities=True, return_dict=False,
            )
        label = f"{strength:g}".replace(".", "_")
        tensors[f"out.tokens.{label}"] = video.contiguous()

    # The blend, at the one strength that is not all-or-nothing.
    torch.manual_seed(3)
    velocity = torch.randn(1, TOKENS, VIDEO["out_channels"])
    clean = torch.randn(1, TOKENS, VIDEO["out_channels"])
    strength_mask = mask * 0.6
    scalar = float(sigma.item())
    x0 = latent - velocity * scalar
    x0_conditioned = x0 * (1 - strength_mask) + clean * strength_mask
    velocity_back = (latent - x0_conditioned) / scalar

    tensors.update({
        "in.tokens": latent, "in.text": inputs["text"], "in.sigma": sigma,
        "in.marked": torch.tensor([marked], dtype=torch.int32),
        "in.velocity": velocity, "in.clean": clean, "in.mask": strength_mask,
        "out.x0": x0.contiguous(),
        "out.x0_conditioned": x0_conditioned.contiguous(),
        "out.velocity": velocity_back.contiguous(),
    })
    save_file(tensors, str(out / "transformer_conditioned.safetensors"))
    print(f"transformer_conditioned: {len(tensors)} tensors")


def dump_conditioned_span(out: pathlib.Path) -> None:
    """The model holding a run of latent frames rather than one: a clip carried on from the
    end of another.

    `pipeline_ltx2_condition.py` writes a multi-frame condition in place over the first
    `k + 1` latent frames' tokens and sets the conditioning mask over all of them, so the
    per-token timestep covers every held frame. The keyframe embedding stays on the first latent
    frame alone (`_MarkedPatchify` over `HEIGHT * WIDTH`): it marks the frame that encodes a
    single picture, which a held run has exactly one of, whatever its length. Two of the three
    latent frames are held here, so the marked and the held token sets differ and a port that
    conflates them is caught.
    """
    model = _model()
    tensors = _weights(model, "model.")
    inputs = _inputs()
    latent = torch.randn(1, TOKENS, VIDEO["in_channels"])
    sigma = torch.tensor([0.725])
    marked = HEIGHT * WIDTH
    held_frames = 2
    held = held_frames * HEIGHT * WIDTH
    model.proj_in = _MarkedPatchify(model.proj_in, model.keyframes_abs_pos_embedding, marked)

    mask = torch.zeros(1, TOKENS, 1)
    mask[:, :held] = 1.0
    for strength in (1.0, 0.6):
        timestep = (sigma[:, None] * 1000) * (1 - mask[..., 0] * strength)  # [1, tokens]
        with torch.no_grad():
            video, _ = model(
                hidden_states=latent,
                audio_hidden_states=torch.randn(1, 4, AUDIO["audio_in_channels"]),
                encoder_hidden_states=inputs["text"],
                audio_encoder_hidden_states=inputs["audio_text"],
                timestep=timestep, audio_timestep=sigma * 1000, sigma=sigma * 1000,
                num_frames=FRAMES, height=HEIGHT, width=WIDTH, fps=FPS, audio_num_frames=4,
                isolate_modalities=True, return_dict=False,
            )
        label = f"{strength:g}".replace(".", "_")
        tensors[f"out.tokens.{label}"] = video.contiguous()
    tensors.update({
        "in.tokens": latent, "in.text": inputs["text"], "in.sigma": sigma,
        "in.marked": torch.tensor([marked], dtype=torch.int32),
        "in.held_frames": torch.tensor([held_frames], dtype=torch.int32),
    })
    save_file(tensors, str(out / "transformer_conditioned_span.safetensors"))
    print(f"transformer_conditioned_span: {len(tensors)} tensors")


DUMPERS = {
    "rope": dump_rope,
    "timestep": dump_timestep,
    "transformer_block": dump_block,
    "transformer_model": dump_model,
    "transformer_conditioned": dump_conditioned,
    "transformer_conditioned_span": dump_conditioned_span,
}


if __name__ == "__main__":
    # Runnable alone while the sibling dumpers are still being written: the shared entry point
    # imports all three and would stop at the first one missing.
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=pathlib.Path)
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    for dumper in DUMPERS.values():
        dumper(arguments.out)
