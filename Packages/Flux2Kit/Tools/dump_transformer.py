# /// script
# requires-python = ">=3.11"
# dependencies = ["torch", "diffusers", "transformers", "safetensors", "numpy"]
# ///
"""Dump reference tensors for the FLUX.2 transformer, from the Apache-2.0 diffusers port.

Three fixtures, each a claim checked in Swift by `TransformerParityTests`: one dual-stream
block, one single-stream block, and a whole two-plus-two-layer model. The doll's-house widths
catch a transposed axis, a swapped modulation chunk, or a stream concatenated the wrong way
round exactly as well as the real 3072-wide model would, and they fit in a commit.

The modulation tensors are **inputs** to the block fixtures, not weights: FLUX.2 computes them
once at the top of the model and hands the same numbers to every block, so the blocks take them
as arguments. Only the whole-model fixture exercises the three shared projections.
"""

import pathlib

import torch
from safetensors.torch import save_file

# Doll's house: two heads of sixteen, so the four rope axes of four each fill one head.
DIM = 32
HEADS = 2
HEAD_DIM = 16
MLP_RATIO = 3.0
EPS = 1e-6
ROPE_THETA = 2000
AXES_DIM = [4, 4, 4, 4]

TEXT_TOKENS = 5
GRID = (3, 4)


def _ids() -> torch.Tensor:
    """Text ids then image ids, which is the order the transformer attends in."""
    text = torch.tensor([[0, 0, 0, position] for position in range(TEXT_TOKENS)])
    image = torch.tensor(
        [[0, row, column, 0] for row in range(GRID[0]) for column in range(GRID[1])]
    )
    return torch.cat([text, image]).float()


def _rope() -> tuple[torch.Tensor, torch.Tensor]:
    """The concatenated table, de-interleaved to one angle per rotated pair.

    The reference repeats each cosine twice so it lines up with interleaved channels; the port
    keeps one per pair and pairs the channels itself, so the dump keeps one per pair too, after
    asserting the two halves really were equal.
    """
    from diffusers.models.transformers.transformer_flux2 import Flux2PosEmbed

    cos, sin = Flux2PosEmbed(theta=ROPE_THETA, axes_dim=AXES_DIM)(_ids())
    assert torch.equal(cos[:, 0::2], cos[:, 1::2]), "the reference interleaves pairs"
    return cos[:, 0::2].float().contiguous(), sin[:, 0::2].float().contiguous()


def _state(module, prefix: str) -> dict[str, torch.Tensor]:
    return {f"{prefix}{key}": value.float().contiguous() for key, value in module.state_dict().items()}


def dump(out: pathlib.Path) -> None:
    from diffusers.models.transformers.transformer_flux2 import (
        Flux2SingleTransformerBlock,
        Flux2Transformer2DModel,
        Flux2TransformerBlock,
    )

    torch.manual_seed(0)
    cos, sin = _rope()
    rope = (cos.repeat_interleave(2, dim=-1), sin.repeat_interleave(2, dim=-1))
    image_tokens = GRID[0] * GRID[1]

    # 1. One dual-stream block. Two modulation sets per stream, supplied raw: the block calls
    # `Flux2Modulation.split(mod, 2)` on them itself.
    block = Flux2TransformerBlock(
        dim=DIM,
        num_attention_heads=HEADS,
        attention_head_dim=HEAD_DIM,
        mlp_ratio=MLP_RATIO,
        eps=EPS,
    ).eval()
    for parameter in block.parameters():
        torch.nn.init.normal_(parameter, std=0.2)
    block_image = torch.randn(1, image_tokens, DIM)
    block_text = torch.randn(1, TEXT_TOKENS, DIM)
    mod_img = torch.randn(1, 6 * DIM) * 0.2
    mod_txt = torch.randn(1, 6 * DIM) * 0.2
    with torch.no_grad():
        out_text, out_image = block(
            hidden_states=block_image,
            encoder_hidden_states=block_text,
            temb_mod_img=mod_img,
            temb_mod_txt=mod_txt,
            image_rotary_emb=rope,
        )
    tensors = _state(block, "block.")
    tensors |= {
        "block.in.image": block_image.contiguous(),
        "block.in.text": block_text.contiguous(),
        "block.in.modulation_image": mod_img.contiguous(),
        "block.in.modulation_text": mod_txt.contiguous(),
        "block.in.cos": cos,
        "block.in.sin": sin,
        "block.out.image": out_image.contiguous(),
        "block.out.text": out_text.contiguous(),
    }
    save_file(tensors, str(out / "transformer_block.safetensors"))
    print(f"transformer_block: {len(tensors)} tensors")

    # 2. One single-stream block, over the joined sequence the double blocks hand on.
    single = Flux2SingleTransformerBlock(
        dim=DIM,
        num_attention_heads=HEADS,
        attention_head_dim=HEAD_DIM,
        mlp_ratio=MLP_RATIO,
        eps=EPS,
    ).eval()
    for parameter in single.parameters():
        torch.nn.init.normal_(parameter, std=0.2)
    hidden = torch.randn(1, TEXT_TOKENS + image_tokens, DIM)
    mod_single = torch.randn(1, 3 * DIM) * 0.2
    with torch.no_grad():
        out_hidden = single(
            hidden_states=hidden,
            encoder_hidden_states=None,
            temb_mod=mod_single,
            image_rotary_emb=rope,
        )
    tensors = _state(single, "single.")
    tensors |= {
        "single.in.hidden": hidden.contiguous(),
        "single.in.modulation": mod_single.contiguous(),
        "single.in.cos": cos,
        "single.in.sin": sin,
        "single.out.hidden": out_hidden.contiguous(),
    }
    save_file(tensors, str(out / "transformer_single.safetensors"))
    print(f"transformer_single: {len(tensors)} tensors")

    # 3. The whole model, which is the only fixture that exercises the timestep embedding, the
    # three shared modulation projections, and the final AdaLN.
    model = Flux2Transformer2DModel(
        patch_size=1,
        in_channels=8,
        out_channels=8,
        num_layers=2,
        num_single_layers=2,
        attention_head_dim=HEAD_DIM,
        num_attention_heads=HEADS,
        joint_attention_dim=24,
        timestep_guidance_channels=256,
        mlp_ratio=MLP_RATIO,
        axes_dims_rope=AXES_DIM,
        rope_theta=ROPE_THETA,
        eps=EPS,
        guidance_embeds=False,
    ).eval()
    for parameter in model.parameters():
        torch.nn.init.normal_(parameter, std=0.2)
    latents = torch.randn(1, image_tokens, 8)
    text = torch.randn(1, TEXT_TOKENS, 24)
    ids = _ids()
    # The pipeline passes sigma; the model multiplies by 1000 itself.
    timestep = torch.tensor([0.7])
    with torch.no_grad():
        prediction = model(
            hidden_states=latents,
            encoder_hidden_states=text,
            timestep=timestep,
            txt_ids=ids[:TEXT_TOKENS],
            img_ids=ids[TEXT_TOKENS:],
            guidance=None,
            return_dict=False,
        )[0]
    tensors = _state(model, "model.")
    tensors |= {
        "model.in.latents": latents.contiguous(),
        "model.in.text": text.contiguous(),
        "model.in.timestep": timestep.contiguous(),
        "model.in.cos": cos,
        "model.in.sin": sin,
        "model.out.prediction": prediction.contiguous(),
    }
    save_file(tensors, str(out / "transformer_model.safetensors"))
    print(f"transformer_model: {len(tensors)} tensors")


def dump_timestep_bf16(out: pathlib.Path) -> None:
    """The conditioning vector for one sigma with the model in bfloat16, as the pipeline runs it.

    `Flux2Transformer2DModel.forward` does `timestep.to(hidden_states.dtype) * 1000` before
    anything else, so under bfloat16 the sinusoid is built from a *rounded* timestep: 0.77
    becomes 0.76953125, times 1000 is 769.53 in bfloat16 arithmetic, which is 768. Then
    `Flux2TimestepGuidanceEmbeddings.forward` casts the float32 projection back to bfloat16
    before `linear_1`. A port that keeps the sigma in float32 through the sinusoid and casts
    once at the end lands somewhere else entirely -- the top of the frequency ladder is 1 radian
    per unit, and 768 against 769.53 is a different cosine -- and `unrounded` records that
    somewhere else, so the Swift test can show the difference is one it would notice.
    """
    from diffusers.models.transformers.transformer_flux2 import Flux2TimestepGuidanceEmbeddings

    torch.manual_seed(0)
    embed = Flux2TimestepGuidanceEmbeddings(
        in_channels=256, embedding_dim=DIM, bias=False, guidance_embeds=False
    ).eval()
    for parameter in embed.parameters():
        torch.nn.init.normal_(parameter, std=0.2)
    wide = embed  # float32, the old port's arithmetic
    embed = Flux2TimestepGuidanceEmbeddings(
        in_channels=256, embedding_dim=DIM, bias=False, guidance_embeds=False
    ).eval()
    embed.load_state_dict(wide.state_dict())
    embed = embed.to(torch.bfloat16)

    sigma = torch.tensor([0.77])
    rounded = sigma.to(torch.bfloat16) * 1000
    with torch.no_grad():
        projection = embed.time_proj(rounded).to(torch.bfloat16)
        conditioning = embed(rounded, None)
        unrounded = wide(sigma * 1000, None).to(torch.bfloat16)
    assert rounded.item() == 768.0, rounded
    tensors = {
        f"temb.{key}": value.contiguous()
        for key, value in embed.timestep_embedder.state_dict().items()
    }
    tensors |= {
        "temb.in.sigma": sigma.contiguous(),
        "temb.out.projection": projection.contiguous(),
        "temb.out.conditioning": conditioning.contiguous(),
        "temb.out.unrounded": unrounded.contiguous(),
    }
    save_file(tensors, str(out / "timestep_bf16.safetensors"))
    print(f"timestep_bf16: {len(tensors)} tensors")
