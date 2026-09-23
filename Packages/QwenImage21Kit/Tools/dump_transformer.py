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
"""`QwenImage21Transformer2DModel` at doll's-house size: the modulation, one block, and a model.

What this pins, and every one of them is a way 2.1 differs from 2512 that loads cleanly and
then makes noise: the **single shared modulation table** every block reads rather than a table
per block; the `causal_condition` row, which is that table evaluated at `t = 0` and given to the
text and condition tokens ahead of the target; the sinusoid's cosines-first ordering;
`patch_size = 1`, so the image projection takes the latent's channels straight; the zero-centre
RMS norm in the text projection, which stores `scale - 1`; the block-causal prefill decomposed
into one attention call per prefix segment; the prefix KV cache, extracted on the first step and
read on every later one; and the fact that there are no biases anywhere.

Three files:

- `modulation.safetensors` — the timestep sinusoid at several timesteps, the projection behind
  it, the shared table, and `_select_modulation_rows` with and without a target mask.
- `transformer_block.safetensors` — one block's weights, its prefill over an edit layout, and
  the cached step that follows, beside the same step run fresh.
- `transformer_model.safetensors` — a whole model over three layouts: text-only, one reference
  image inside the prompt, and a right-padded prompt, which is the only thing that exercises the
  joint key-valid mask.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

# Doll's house: two heads of sixteen, three rope axes filling one head exactly, and a text
# stream the model's own width, which is the real config's `context_in_dim == inner_dim`.
CONFIG = {
    "attention_head_dim": 16,
    "axes_dims_rope": [4, 6, 6],
    "context_in_dim": 32,
    "in_channels": 8,
    "num_attention_heads": 2,
    "num_layers": 2,
    "out_channels": 8,
    "patch_size": 1,
    "mlp_ratio": 3,
    "eps": 1e-6,
    "causal_condition": True,
}

TIMESTEPS = [1.0, 0.75, 0.5, 0.125, 0.0]

# Vision-language image-slot runs and the latent grids they stand for. One slot is four latent
# tokens, so every grid's token count is a multiple of four.
LAYOUTS = {
    "textOnly": ([(False, 5), (True, 3)], [(1, 3, 4)]),
    "oneReference": ([(False, 4), (True, 2), (False, 3), (True, 3)], [(1, 2, 4), (1, 3, 4)]),
}


def img_mask(runs) -> torch.Tensor:
    values = [flag for flag, count in runs for _ in range(count)]
    return torch.tensor(values, dtype=torch.bool)[None]


def inputs(model, runs, shapes):
    """One forward's inputs: the latents for every block, the prompt, and the slot mask."""
    mask = img_mask(runs)
    tokens = sum(height * width for _, height, width in shapes)
    text_tokens = mask.shape[1] - (shapes[-1][1] * shapes[-1][2]) // 4
    hidden = torch.randn(1, tokens, CONFIG["in_channels"])
    encoder = torch.randn(1, text_tokens, CONFIG["context_in_dim"])
    return hidden, encoder, mask


def dump_modulation(out: pathlib.Path, model) -> None:
    from diffusers.models.transformers.transformer_qwenimage21 import _select_modulation_rows

    timestep = torch.tensor(TIMESTEPS)
    with torch.no_grad():
        projected = model.time_text_embed.time_proj(timestep)
        temb = model.time_text_embed(timestep, torch.zeros(1, dtype=torch.float32))
        modulation = model.modulation(temb)
        target_mask = torch.tensor([False, False, True, True, True])
        selected = _select_modulation_rows(modulation[:, : model.inner_dim], target_mask)
        broadcast = _select_modulation_rows(modulation[:, : model.inner_dim], None)

    rows = {
        "in.timestep": timestep.contiguous(),
        "out.projected": projected.float().contiguous(),
        "out.temb": temb.float().contiguous(),
        "out.modulation": modulation.float().contiguous(),
        "select.in.mask": target_mask.to(torch.int32).contiguous(),
        "select.out.masked": selected.float().contiguous(),
        "select.out.broadcast": broadcast.float().contiguous(),
    }
    save_file(rows, str(out / "modulation.safetensors"))
    print(f"modulation: {len(rows)} tensors")


def dump_block(out: pathlib.Path, model) -> None:
    from diffusers.models.transformers.transformer_qwenimage21 import (
        _IMG_TOKENS_PER_SLOT,
        QwenImage21KVLayerCache,
        _qwenimage21_prefix_segments,
    )

    runs, shapes = LAYOUTS["oneReference"]
    mask = img_mask(runs)
    repeats = torch.where(mask, _IMG_TOKENS_PER_SLOT, 1)[0]
    image_pad_mask = torch.repeat_interleave(mask[0], repeats)
    image_ids, target_token_mask = model.build_token_metadata(image_pad_mask, shapes)
    prefix_len = int((~target_token_mask).sum())
    segments = _qwenimage21_prefix_segments(image_ids, prefix_len)
    rotary = model.pos_embed(shapes, image_pad_mask, torch.device("cpu"))

    block = model.transformer_blocks[0]
    hidden = torch.randn(1, image_pad_mask.shape[0], model.inner_dim)
    cache = QwenImage21KVLayerCache()

    def table(value: float) -> torch.Tensor:
        timestep = torch.cat([torch.tensor([value]), torch.zeros(1)])
        return model.modulation(model.time_text_embed(timestep, hidden))

    with torch.no_grad():
        first, second = table(0.75), table(0.5)
        prefill = block(
            hidden_states=hidden,
            modulation=first,
            rotary_emb=rotary,
            target_token_mask=target_token_mask,
            layer_cache=cache,
            kv_cache_mode="extract",
            cache_write_slice=slice(0, prefix_len),
            segments=segments,
        )
        cached = block(
            hidden_states=hidden[:, prefix_len:],
            modulation=second,
            rotary_emb=rotary[prefix_len:],
            target_token_mask=target_token_mask[prefix_len:],
            layer_cache=cache,
            kv_cache_mode="cached",
        )
        fresh = block(
            hidden_states=hidden,
            modulation=second,
            rotary_emb=rotary,
            target_token_mask=target_token_mask,
            segments=segments,
        )

    rows = {f"block.{name}": value.float().contiguous() for name, value in block.state_dict().items()}
    rows.update(
        {
            "in.hidden": hidden.contiguous(),
            "in.cos": rotary.real.float().contiguous(),
            "in.sin": rotary.imag.float().contiguous(),
            "in.modulationFirst": first.float().contiguous(),
            "in.modulationSecond": second.float().contiguous(),
            "in.targetTokenMask": target_token_mask.to(torch.int32).contiguous(),
            "in.segments": torch.tensor(
                [[start, end, int(is_text)] for start, end, is_text in segments], dtype=torch.int32
            ),
            "in.prefixLength": torch.tensor([prefix_len], dtype=torch.int32),
            "out.prefill": prefill.float().contiguous(),
            "out.cached": cached.float().contiguous(),
            "out.fresh": fresh[:, prefix_len:].float().contiguous(),
            "cache.key": cache.k.float().contiguous(),
            "cache.value": cache.v.float().contiguous(),
        }
    )
    save_file(rows, str(out / "transformer_block.safetensors"))
    print(f"transformer_block: {len(rows)} tensors")


def dump_model(out: pathlib.Path, model) -> None:
    from diffusers.models.transformers.transformer_qwenimage21 import QwenImage21KVCache

    rows = {f"model.{name}": value.float().contiguous() for name, value in model.state_dict().items()}
    for label, (runs, shapes) in LAYOUTS.items():
        hidden, encoder, mask = inputs(model, runs, shapes)
        timestep = torch.tensor([0.75])
        with torch.no_grad():
            velocity = model(
                hidden_states=hidden,
                encoder_hidden_states=encoder,
                timestep=timestep,
                img_shapes=[shapes],
                img_mask=mask,
                return_dict=False,
            )[0]
        rows[f"{label}.in.hidden"] = hidden.contiguous()
        rows[f"{label}.in.encoder"] = encoder.contiguous()
        rows[f"{label}.in.timestep"] = timestep.contiguous()
        rows[f"{label}.in.imgMask"] = mask[0].to(torch.int32).contiguous()
        rows[f"{label}.out.velocity"] = velocity.float().contiguous()

    # A right-padded prompt is the only thing that exercises the joint key-valid mask, which is
    # lifted onto the joint sequence at the non-image positions in order rather than sliced off
    # as a prefix.
    runs, shapes = LAYOUTS["oneReference"]
    hidden, encoder, mask = inputs(model, runs, shapes)
    prompt_mask = torch.ones(1, encoder.shape[1], dtype=torch.bool)
    prompt_mask[:, -2:] = False
    timestep = torch.tensor([0.75])
    with torch.no_grad():
        velocity = model(
            hidden_states=hidden,
            encoder_hidden_states=encoder,
            timestep=timestep,
            img_shapes=[shapes],
            img_mask=mask,
            encoder_hidden_states_mask=prompt_mask,
            return_dict=False,
        )[0]
    rows["padded.in.hidden"] = hidden.contiguous()
    rows["padded.in.encoder"] = encoder.contiguous()
    rows["padded.in.timestep"] = timestep.contiguous()
    rows["padded.in.imgMask"] = mask[0].to(torch.int32).contiguous()
    rows["padded.in.promptMask"] = prompt_mask.to(torch.int32).contiguous()
    rows["padded.out.velocity"] = velocity.float().contiguous()

    # The prefix cache across the whole model: step 0 extracts, step 1 reads, and the same step
    # run fresh over the whole sequence has to land on the same target tokens.
    runs, shapes = LAYOUTS["oneReference"]
    hidden, encoder, mask = inputs(model, runs, shapes)
    cache = QwenImage21KVCache(CONFIG["num_layers"])
    first, second = torch.tensor([0.75]), torch.tensor([0.5])
    common = dict(
        hidden_states=hidden,
        encoder_hidden_states=encoder,
        img_shapes=[shapes],
        img_mask=mask,
        return_dict=False,
    )
    with torch.no_grad():
        model(timestep=first, kv_cache=cache, kv_cache_mode="extract", **common)
        cached = model(timestep=second, kv_cache=cache, kv_cache_mode="cached", **common)[0]
        fresh = model(timestep=second, **common)[0]
    rows["cached.in.hidden"] = hidden.contiguous()
    rows["cached.in.encoder"] = encoder.contiguous()
    rows["cached.in.imgMask"] = mask[0].to(torch.int32).contiguous()
    rows["cached.in.first"] = first.contiguous()
    rows["cached.in.second"] = second.contiguous()
    rows["cached.out.velocity"] = cached.float().contiguous()
    rows["cached.out.fresh"] = fresh[:, -cached.shape[1] :].float().contiguous()

    save_file(rows, str(out / "transformer_model.safetensors"))
    print(f"transformer_model: {len(rows)} tensors")


def dump(out: pathlib.Path) -> None:
    from diffusers.models.transformers.transformer_qwenimage21 import (
        QwenImage21Transformer2DModel,
    )

    torch.manual_seed(0)
    model = QwenImage21Transformer2DModel(**CONFIG).eval()
    torch.manual_seed(1)
    dump_modulation(out, model)
    torch.manual_seed(2)
    dump_block(out, model)
    torch.manual_seed(3)
    dump_model(out, model)


def main() -> None:
    import dump_reference

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=dump_reference.default_out())
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    dump(arguments.out)


if __name__ == "__main__":
    import sys

    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    main()
