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
axis; for a text-only prompt the three axes are equal and the difference hides, so the fixture
has to carry an image case too.

Written with the kit's skeleton so the seven dumpers live in one place; the doll's-house widths
are settled by the step that adds `TextEncoderParityTests`.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file

# Doll's house: the real ratios — four query heads to one key-value head, an interleaved rope
# section summing to half the head width — at a size that commits.
TEXT_CONFIG = {
    "hidden_size": 32,
    "intermediate_size": 96,
    "num_hidden_layers": 2,
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

TOKENS = [1, 2, 3, 4, 5, 6, 7]


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
