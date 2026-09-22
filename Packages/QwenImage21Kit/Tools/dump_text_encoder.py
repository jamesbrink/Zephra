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
"""Qwen3-VL's decoder stack at doll's-house size, with the hook the pipeline installs.

Two things this pins that nothing else would catch. The conditioning is the output of the
**last decoder layer before the stack's final RMS norm**, which from transformers 5.0 is not
what `hidden_states[-1]` returns on its own — the pipeline hooks `model.language_model.norm` to
hand back its input, and this dump does the same, so the fixture is the tensor the transformer
was trained on rather than the normalised one. And the rotary is **interleaved** multimodal
rope over `mrope_section`, not the sectioned kind, which changes which channel carries which
axis; for a text-only prompt the three axes are equal and the difference hides, so the rotary
tables here are dumped at the **published** width and section, over a text-only run of
positions and over a three-axis run, and the doll's house is only the decoder's own parity.

`uv run Tools/dump_text_encoder.py`. No snapshot is read: every number here is decided by a
configuration, and the published configuration's own numbers are written into
`REAL_TEXT_CONFIG` below from `text_encoder/config.json` (`QwenImage21ConfigurationTests`
checks that file against the same numbers).
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

# Doll's house: the real ratios — four query heads to one key-value head, an interleaved rope
# section summing to half the head width — at a size that commits. Four layers, because
# DeepStack is added into the first three and the fourth is what says the injection stopped.
TEXT_CONFIG = {
    "hidden_size": 32,
    "intermediate_size": 96,
    "num_hidden_layers": 4,
    "num_attention_heads": 4,
    "num_key_value_heads": 1,
    "head_dim": 8,
    "rms_norm_eps": 1e-6,
    "rope_theta": 5_000_000,
    "rope_scaling": {"mrope_interleaved": True, "mrope_section": [2, 1, 1], "rope_type": "default"},
    "vocab_size": 64,
    "hidden_act": "silu",
    "attention_bias": False,
}

# The published shape, for the rotary tables alone: no weight of this size is ever built here.
REAL_TEXT_CONFIG = dict(
    TEXT_CONFIG,
    hidden_size=4096,
    intermediate_size=12288,
    num_hidden_layers=36,
    num_attention_heads=32,
    num_key_value_heads=8,
    head_dim=128,
    vocab_size=151936,
    rope_scaling={"mrope_interleaved": True, "mrope_section": [24, 20, 20], "rope_type": "default"},
)

TOKENS = [1, 2, 3, 4, 5, 6, 7]

# A three-axis run the way `get_rope_index` lays one out: three text tokens, then a two-by-three
# image whose rows and columns each start at the position the text reached, then two more text
# tokens resuming past the picture. Only the rows differing is what makes interleaved MRoPE
# anything other than plain 1-D rope.
THREE_AXIS_POSITIONS = [
    [0, 1, 2, 3, 3, 3, 3, 3, 3, 6, 7],
    [0, 1, 2, 3, 3, 3, 4, 4, 4, 6, 7],
    [0, 1, 2, 3, 4, 5, 3, 4, 5, 6, 7],
]


def rotary_tables(config: dict, positions: list[list[int]]) -> tuple[torch.Tensor, torch.Tensor]:
    """The cos and sin `Qwen3VLTextRotaryEmbedding` answers for `positions`, `[3, S]`."""
    from transformers.models.qwen3_vl.configuration_qwen3_vl import Qwen3VLTextConfig
    from transformers.models.qwen3_vl.modeling_qwen3_vl import Qwen3VLTextRotaryEmbedding

    rotary = Qwen3VLTextRotaryEmbedding(Qwen3VLTextConfig(**config))
    ids = torch.tensor(positions).unsqueeze(1)  # [3, 1, S]
    cos, sin = rotary(torch.zeros(1, ids.shape[-1], 1, dtype=torch.float32), ids)
    return cos[0].float().contiguous(), sin[0].float().contiguous()


def dump(out: pathlib.Path) -> None:
    from transformers.models.qwen3_vl.configuration_qwen3_vl import Qwen3VLTextConfig
    from transformers.models.qwen3_vl.modeling_qwen3_vl import Qwen3VLTextModel

    model = Qwen3VLTextModel(Qwen3VLTextConfig(**TEXT_CONFIG)).eval()
    ids = torch.tensor([TOKENS])

    # The pipeline's own hook: the final norm hands back its input, so `hidden_states[-1]` is
    # the last decoder layer's output rather than the normalised one.
    handle = model.norm.register_forward_hook(lambda module, args, output: args[0])
    try:
        with torch.no_grad():
            outputs = model(input_ids=ids, output_hidden_states=True)
    finally:
        handle.remove()

    tensors = {f"model.{name}": value.float().contiguous() for name, value in model.state_dict().items()}
    tensors["in.ids"] = ids.to(torch.int32).contiguous()
    tensors["out.hidden"] = outputs.hidden_states[-1].float().contiguous()

    # The same run with the hook off, which from transformers 5.0 returns the **normalised**
    # state at `hidden_states[-1]` — a third of the signal the transformer reads. It is in the
    # fixture so the Swift suite can show the two differ, and that the port answers the one the
    # transformer was trained on. With the hook installed the two entries are the same tensor,
    # which is why this needs a second forward rather than reading `last_hidden_state`.
    with torch.no_grad():
        normed = model(input_ids=ids, output_hidden_states=True).hidden_states[-1]
    tensors["out.normed"] = normed.float().clone().contiguous()

    # Text-only positions: all three rows the same index, which is the case interleaved MRoPE
    # collapses to plain 1-D rope in.
    flat = [list(range(len(TOKENS)))] * 3
    for label, config, positions in [
        ("doll.text", TEXT_CONFIG, flat),
        ("doll.threeAxis", TEXT_CONFIG, THREE_AXIS_POSITIONS),
        ("real.text", REAL_TEXT_CONFIG, [list(range(11))] * 3),
        ("real.threeAxis", REAL_TEXT_CONFIG, THREE_AXIS_POSITIONS),
    ]:
        cos, sin = rotary_tables(config, positions)
        tensors[f"rope.{label}.cos"] = cos
        tensors[f"rope.{label}.sin"] = sin
        tensors[f"rope.{label}.positions"] = torch.tensor(positions, dtype=torch.int32).contiguous()

    save_file(tensors, str(out / "text_encoder.safetensors"))
    print(f"text_encoder: {len(tensors)} tensors")


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
