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
"""Dump reference tensors for LTX-2.5's text side: Gemma 4, the feature extractor, the connector.

Three doll's-house modules and one real tokenizer. The Gemma 4 stack keeps every structural
choice of the 12B model -- sliding and full layers with different head widths and rope bases,
`k_eq_v` full layers with no value projection, q/k norms per head, scaled embeddings, the
per-layer scalar -- at a width where a transposed axis is as visible as at 3840. Weights are saved
under the names the mlx-community pack uses, so the Swift test loads them the way the app does.

Positions past the prompt are left-padded and masked. The reference's hidden states at those
positions are not checked (the connector zeroes them), which is why the fixture stores the mask.
"""

import math
import pathlib
import urllib.request

import torch
from safetensors.torch import save_file

SCRATCH = pathlib.Path(__file__).resolve().parent / ".cache"
TOKENIZER_URL = (
    "https://huggingface.co/mlx-community/ltx-2.5-mlx/resolve/main/gemma4-12b-ltx-v1/tokenizer.json"
)

PROMPTS = [
    "a tin robot reading a newspaper on a park bench, morning light",
    "A red kite over a beach at dusk.",
    "  leading and trailing spaces  ",
    "Ünïcödé — dashes, “quotes”, and ellipses…",
    "日本語のプロンプト、桜の木の下で",
    "emoji 🎥🐈‍⬛ and symbols ∑∆ ≈ π",
    "Numbers 1234567890 and code: let x = 42; // comment",
    "",
    "A" * 300,
    " ".join(["the quick brown fox jumps over the lazy dog"] * 200),
    "Tabs\tand\nnewlines\n\nare kept",
    "<bos> already here",
]


def dump_tokenizer(out: pathlib.Path) -> None:
    """Token ids for a dozen prompts from the real Gemma 4 tokenizer, BOS ensured, front kept."""
    from tokenizers import Tokenizer

    SCRATCH.mkdir(exist_ok=True)
    path = SCRATCH / "gemma4-ltx-tokenizer.json"
    if not path.exists():
        urllib.request.urlretrieve(TOKENIZER_URL, path)
    tokenizer = Tokenizer.from_file(str(path))
    bos = tokenizer.token_to_id("<bos>")
    assert bos == 2, bos
    tensors = {"bos": torch.tensor([bos], dtype=torch.int32)}
    for index, prompt in enumerate(PROMPTS):
        # The official encoder: strip, tokenize with the tokenizer's own specials, prepend
        # <bos> when the post-processor did not, clip to 1024 keeping the front.
        ids = tokenizer.encode(prompt.strip(), add_special_tokens=True).ids
        if not ids or ids[0] != bos:
            ids = [bos] + ids
        ids = ids[:1024]
        tensors[f"prompt{index}.text"] = torch.tensor(list(prompt.encode("utf-8")), dtype=torch.uint8)
        tensors[f"prompt{index}.ids"] = torch.tensor(ids, dtype=torch.int32)
    save_file(tensors, str(out / "tokenizer.safetensors"))
    print(f"tokenizer: {len(PROMPTS)} prompts")


def _gemma_config():
    from transformers import Gemma4TextConfig

    return Gemma4TextConfig(
        vocab_size=64,
        hidden_size=32,
        intermediate_size=48,
        num_hidden_layers=6,
        num_attention_heads=4,
        num_key_value_heads=2,
        head_dim=8,
        global_head_dim=16,
        num_global_key_value_heads=1,
        attention_k_eq_v=True,
        layer_types=["sliding_attention", "sliding_attention", "full_attention"] * 2,
        sliding_window=4,
        rms_norm_eps=1e-6,
        hidden_activation="gelu_pytorch_tanh",
        pad_token_id=0,
        bos_token_id=2,
        use_bidirectional_attention="vision",
        hidden_size_per_layer_input=0,
        enable_moe_block=False,
        num_kv_shared_layers=0,
        attention_bias=False,
        tie_word_embeddings=True,
    )


def dump_text_encoder(out: pathlib.Path) -> None:
    """All hidden states of a six-layer Gemma 4 over two left-padded prompts."""
    from transformers import Gemma4TextModel

    torch.manual_seed(0)
    config = _gemma_config()
    config._attn_implementation = "eager"
    model = Gemma4TextModel(config).eval()
    # Random norms and scalars: the defaults (ones) would let a port that skipped them pass.
    with torch.no_grad():
        for name, parameter in model.named_parameters():
            if "norm" in name:
                parameter.copy_(torch.rand_like(parameter) + 0.5)
        for layer in model.layers:
            layer.layer_scalar.copy_(torch.rand(1) + 0.5)
    length, batch = 12, 2
    valid = [12, 7]
    ids = torch.randint(3, 64, (batch, length))
    mask = torch.zeros(batch, length, dtype=torch.long)
    for row, count in enumerate(valid):
        ids[row, : length - count] = 0
        mask[row, length - count :] = 1
    with torch.no_grad():
        outputs = model(input_ids=ids, attention_mask=mask, output_hidden_states=True)
    states = torch.stack(outputs.hidden_states, dim=0)  # [layers + 1, B, T, H]
    assert states.shape[0] == config.num_hidden_layers + 1
    tensors = {
        f"text_encoder.model.language_model.{name}": value.detach().float().contiguous()
        for name, value in model.state_dict().items()
    }
    tensors["in.input_ids"] = ids.to(torch.int32).contiguous()
    tensors["in.attention_mask"] = mask.to(torch.int32).contiguous()
    tensors["out.hidden_states"] = states.float().contiguous()
    save_file(tensors, str(out / "text_encoder.safetensors"))
    print(f"text_encoder: {len(tensors)} tensors")


def _connectors():
    from diffusers.pipelines.ltx2.connectors import LTX2TextConnectors

    torch.manual_seed(1)
    return LTX2TextConnectors(
        caption_channels=32,
        text_proj_in_factor=7,
        video_connector_num_attention_heads=4,
        video_connector_attention_head_dim=8,
        video_connector_num_layers=2,
        video_connector_num_learnable_registers=4,
        video_gated_attn=True,
        audio_connector_num_attention_heads=2,
        audio_connector_attention_head_dim=8,
        audio_connector_num_layers=1,
        audio_connector_num_learnable_registers=4,
        audio_gated_attn=True,
        connector_rope_base_seq_len=4096,
        rope_theta=10000.0,
        rope_double_precision=True,
        rope_type="split",
        per_modality_projections=True,
        video_hidden_dim=32,
        audio_hidden_dim=16,
        proj_bias=True,
    ).eval()


def _pack_name(diffusers_name: str) -> str:
    """The mlx-community pack's key for a diffusers connector parameter."""
    name = diffusers_name
    name = name.replace(
        "video_connector.transformer_blocks.", "video_embeddings_connector.transformer_1d_blocks."
    )
    name = name.replace("video_connector.learnable_registers", "video_embeddings_connector.learnable_registers")
    name = name.replace("attn1.norm_q.", "attn1.q_norm.").replace("attn1.norm_k.", "attn1.k_norm.")
    name = name.replace("video_text_proj_in.", "text_embedding_projection.video_aggregate_embed.")
    return "connector." + name


def _inputs(connectors):
    """Two left-padded prompts' worth of stacked hidden states, and the reference's projection."""
    from diffusers.pipelines.ltx2.connectors import per_token_rms_norm

    torch.manual_seed(2)
    batch, length = 2, 12
    valid = [12, 5]
    states = torch.randn(batch, length, 32, 7) * 3
    mask = torch.zeros(batch, length, dtype=torch.long)
    for row, count in enumerate(valid):
        mask[row, length - count :] = 1
    normed = per_token_rms_norm(states).flatten(2, 3)
    normed = torch.where(mask.bool().unsqueeze(-1), normed, torch.zeros_like(normed))
    features = connectors.video_text_proj_in(normed * math.sqrt(32 / 32))
    return states, mask, features


def dump_feature_extractor(out: pathlib.Path) -> None:
    """The 49-state stack normalised per token and projected, with padding zeroed."""
    connectors = _connectors()
    with torch.no_grad():
        states, mask, features = _inputs(connectors)
    tensors = {
        _pack_name(name): value.detach().float().contiguous()
        for name, value in connectors.state_dict().items()
        if name.startswith("video_text_proj_in.")
    }
    tensors["in.hidden_states"] = states.contiguous()
    tensors["in.attention_mask"] = mask.to(torch.int32).contiguous()
    tensors["out.features"] = features.float().contiguous()
    save_file(tensors, str(out / "feature_extractor.safetensors"))
    print(f"feature_extractor: {len(tensors)} tensors")


def dump_connector(out: pathlib.Path) -> None:
    """The video connector over projected features: registers, 1-D split RoPE, gated attention."""
    connectors = _connectors()
    with torch.no_grad():
        states, mask, features = _inputs(connectors)
        video, _, binary = connectors(states, mask)
    tensors = {
        _pack_name(name): value.detach().float().contiguous()
        for name, value in connectors.state_dict().items()
        if name.startswith("video_connector.")
    }
    tensors["in.features"] = features.float().contiguous()
    tensors["in.attention_mask"] = mask.to(torch.int32).contiguous()
    tensors["out.embedding"] = video.float().contiguous()
    tensors["out.mask"] = binary.to(torch.int32).contiguous()
    save_file(tensors, str(out / "connector.safetensors"))
    print(f"connector: {len(tensors)} tensors")


DUMPERS = {
    "tokenizer": dump_tokenizer,
    "text_encoder": dump_text_encoder,
    "feature_extractor": dump_feature_extractor,
    "connector": dump_connector,
}
