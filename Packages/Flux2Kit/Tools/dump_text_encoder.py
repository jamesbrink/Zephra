# /// script
# requires-python = ">=3.11"
# dependencies = ["torch", "transformers", "safetensors"]
# ///
"""Dump a doll's-house Qwen3 encoder and the tapped states FLUX.2 klein conditions on.

The reference is `transformers.Qwen3Model`, which is what the klein pipeline runs: its text
encoder is `Qwen3ForCausalLM`, bit-identical to Qwen/Qwen3-4B, and the pipeline asks it for
`output_hidden_states=True` and never touches the head.

`taps_concat` is that pipeline's own construction, copied from
`Flux2KleinPipeline._get_qwen3_prompt_embeds` in diffusers::

    out = torch.stack([output.hidden_states[k] for k in hidden_states_layers], dim=1)
    batch_size, num_channels, seq_len, hidden_dim = out.shape
    prompt_embeds = out.permute(0, 2, 1, 3).reshape(batch_size, seq_len, num_channels * hidden_dim)

with `hidden_states_layers = (9, 18, 27)` for the real model and (2, 4, 6) here. The layout that
falls out is tap-major within a position, which is the thing the Swift side has to match and the
thing shapes alone would not catch.

The input is right-padded on purpose: 7 real tokens then 5 pad ids, with an attention mask to
match. klein pads every prompt to 512 and feeds all 512 hidden states to the transformer, so the
padded positions' states are conditioning too and have to be reproduced, not just skipped.

The stack is deeper than the deepest tap on purpose too, 8 layers tapped at 6, mirroring the real
model's 36 tapped at 27. The reference's *last* `hidden_states` entry is the only one that has
been through the final norm, so a doll's house tapped at its last layer would demand a norm the
port deliberately does not build, and would fail for a reason the real model never has.
"""

import pathlib

import torch
from safetensors.torch import save_file
from transformers import Qwen3Config
from transformers.models.qwen3.modeling_qwen3 import Qwen3Model

#: Doll's-house shape. Small enough to commit, wide enough that a transposed axis shows.
LAYERS = 8
LENGTH = 12
VALID = 7
PAD_ID = 0
TAPS = (2, 4, 6)


def dump(out: pathlib.Path) -> None:
    torch.manual_seed(0)
    config = Qwen3Config(
        hidden_size=64,
        num_hidden_layers=LAYERS,
        num_attention_heads=4,
        num_key_value_heads=2,
        head_dim=16,
        intermediate_size=128,
        vocab_size=100,
        rms_norm_eps=1e-6,
        rope_theta=1e6,
        tie_word_embeddings=True,
        attn_implementation="eager",
    )
    config._attn_implementation = "eager"
    model = Qwen3Model(config).eval()

    input_ids = torch.randint(1, config.vocab_size, (1, LENGTH))
    input_ids[:, VALID:] = PAD_ID
    attention_mask = torch.zeros(1, LENGTH, dtype=torch.long)
    attention_mask[:, :VALID] = 1

    with torch.no_grad():
        output = model(
            input_ids=input_ids,
            attention_mask=attention_mask,
            output_hidden_states=True,
            use_cache=False,
        )

    hidden = output.hidden_states
    assert len(hidden) == LAYERS + 1, "hidden_states[0] is the embedding output"
    assert max(TAPS) < LAYERS, "the deepest tap must not be the post-norm final entry"

    stacked = torch.stack([hidden[k] for k in TAPS], dim=1)
    batch, channels, seq_len, hidden_dim = stacked.shape
    taps_concat = stacked.permute(0, 2, 1, 3).reshape(batch, seq_len, channels * hidden_dim)

    # The checkpoint names these under `model.`, because the published encoder is the causal
    # language model and this stack is its `model` attribute.
    tensors = {f"model.{name}": value.contiguous() for name, value in model.state_dict().items()}
    tensors["input_ids"] = input_ids.to(torch.int32).contiguous()
    tensors["attention_mask"] = attention_mask.to(torch.int32).contiguous()
    for index, state in enumerate(hidden):
        tensors[f"hidden_states.{index}"] = state.contiguous()
    tensors["taps_concat"] = taps_concat.contiguous()

    save_file(tensors, str(out / "text_encoder.safetensors"))
    print(f"text_encoder: {len(tensors)} tensors")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=pathlib.Path)
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    dump(arguments.out)
