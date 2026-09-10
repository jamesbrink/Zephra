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
"""Dump reference tensors for Wan 2.2's text side: the UMT5-XXL encoder and its tokenizer.

One doll's-house module and one real tokenizer. The UMT5 stack keeps every structural choice
of the 24-layer model -- a relative position bias table in every layer, unscaled attention
logits, T5's scale-only RMS norm, the gated GELU with the tanh approximation -- at a width where
a transposed axis is as visible as at 4096. Weights are saved under the checkpoint's own names,
`shared.weight` for the token table as the release stores it, so the Swift test loads them the
way the app does. The bucket function is pinned twice: through layer 0's bias on the doll's
house, and on its own over every relative position a 512-token prompt can produce at the real
model's 32 buckets and 128 distance.

The tokenizer ids are what `transformers` 5.16.1's `T5Tokenizer` produces on the release's
files, which is the class `WanPipeline` loads. That class builds its own backend from the
vocabulary rather than reading `tokenizer.json`'s pipeline: no normalizer, a whitespace split
before the Metaspace step, and `</s>` appended after truncation to 511. `cleaned` beside each
prompt is `pipeline_wan.prompt_clean` without ftfy, which is not installed here and which the
port leaves out.
"""

import json
import pathlib

import torch
from safetensors.torch import save_file

RELEASE = pathlib.Path(
    "/Volumes/ExternalStorage/Models/ZephraModels/Downloads/FastVideo--FastWan2.2-TI2V-5B-FullAttn-Diffusers"
)
MAX_LENGTH = 512

PROMPTS = [
    "a tin robot reading a newspaper on a park bench, morning light",
    "A red kite over a beach at dusk.",
    "The year 2024 has 366 days; 12:30pm, 3.14159, 1,000,000.",
    "Wait... what?! Really?!?! -- no; (yes) [maybe] {ok} <hmm> \"quoted\" 'single'",
    "well-known state-of-the-art, don't, can't, o'clock, rock 'n' roll",
    "multiple   spaces    between     words",
    "line one\nline two\n\nline four\ttabbed",
    "  leading and trailing space  ",
    "café résumé naïve façade Zürich",
    "cafe\u0301 with a combining accent",
    "日本語のプロンプト、桜の木の下で猫が眠る",
    "中文提示词：一只猫在阳光下睡觉",
    "Привет, мир! Кошка спит на солнце.",
    "a cat 🐈 and a camera 🎥 with sparkles ✨",
    "Tom &amp; Jerry &lt;3 &quot;quoted&quot; &#39;apos&#39; &nbsp;space &amp;amp; twice",
    " ".join(["the quick brown fox jumps over the lazy dog"] * 80),
    "",
    "x▁y literal metaspace",
    "CamelCase and UPPERCASE and lowercase and MiXeD",
    "email me@example.com or visit https://example.com/path?q=1&r=2",
    "hyphen-ated words, em—dash, en–dash, ellipsis…",
    "Deutsch: Straße, Größe; Español: ñandú, ¿qué?; Français: où",
    "한국어 프롬프트: 고양이가 잔다",
    "العربية: قطة تنام في الشمس",
    "मराठी: मांजर झोपली आहे",
    "\u00a0nbsp\u00a0separated\u3000ideographic space\u2003em space",
    "1girl, solo, masterpiece, best quality, ultra-detailed, 8k",
    "A" * 300,
    "<extra_id_0> and </s> typed literally",
    "🐈‍⬛ zwj sequence and 👩🏽‍💻 skin tone",
    "\U0001F9FF nazar and ☃ snowman and \U00013000 hieroglyph",
]


def dump_tokenizer_ids(out: pathlib.Path) -> None:
    """Ids for every prompt from the real tokenizer, truncated, `</s>` appended, not padded."""
    from diffusers.pipelines.wan.pipeline_wan import prompt_clean
    from diffusers.utils import is_ftfy_available
    from transformers import AutoTokenizer

    assert not is_ftfy_available(), "ftfy would change `cleaned`; the port leaves it out"
    tokenizer = AutoTokenizer.from_pretrained(RELEASE / "tokenizer")
    assert tokenizer.eos_token_id == 1 and tokenizer.pad_token_id == 0, "not UMT5's ids"
    prompts = []
    for prompt in PROMPTS:
        encoded = tokenizer(
            prompt,
            padding="max_length",
            max_length=MAX_LENGTH,
            truncation=True,
            add_special_tokens=True,
        )
        length = sum(encoded["attention_mask"])
        ids = encoded["input_ids"][:length]
        assert ids[-1] == 1 and len(ids) <= MAX_LENGTH
        # The reference hands an unknown character the hard-coded id 2, which is `<s>` in this
        # vocabulary; the port uses the file's `<unk>`, so no prompt here may reach that path.
        assert 2 not in ids, f"unknown character in {prompt!r}"
        prompts.append({"text": prompt, "ids": ids, "cleaned": prompt_clean(prompt)})
    truncated = [p for p in prompts if len(p["ids"]) == MAX_LENGTH]
    assert truncated, "no prompt long enough to pin truncation"
    (out / "tokenizer_ids.json").write_text(
        json.dumps(
            {
                "eos_token_id": 1,
                "pad_token_id": 0,
                "unk_token_id": 3,
                "max_length": MAX_LENGTH,
                "prompts": prompts,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n"
    )
    print(f"tokenizer_ids: {len(prompts)} prompts, {len(truncated)} truncated")


def _umt5_config():
    from transformers import UMT5Config

    return UMT5Config(
        vocab_size=64,
        d_model=32,
        d_kv=8,
        d_ff=48,
        num_layers=2,
        num_decoder_layers=2,
        num_heads=4,
        relative_attention_num_buckets=8,
        relative_attention_max_distance=16,
        dropout_rate=0.0,
        layer_norm_epsilon=1e-6,
        feed_forward_proj="gated-gelu",
        is_encoder_decoder=False,
        pad_token_id=0,
        eos_token_id=1,
        tie_word_embeddings=False,
    )


def dump_text_encoder(out: pathlib.Path) -> None:
    """The last hidden state of a two-layer UMT5 encoder over one full and one padded prompt."""
    from transformers import UMT5EncoderModel

    torch.manual_seed(0)
    config = _umt5_config()
    assert config.dense_act_fn == "gelu_new" and config.is_gated_act
    config._attn_implementation = "eager"
    model = UMT5EncoderModel(config).eval()
    # Random norms and bias tables: the defaults would let a port that skipped them pass.
    with torch.no_grad():
        for name, parameter in model.named_parameters():
            if "layer_norm" in name:
                parameter.copy_(torch.rand_like(parameter) + 0.5)
            if "relative_attention_bias" in name:
                parameter.copy_(torch.randn_like(parameter))
    length, batch = 12, 2
    valid = [12, 7]
    ids = torch.randint(4, 64, (batch, length))
    mask = torch.zeros(batch, length, dtype=torch.long)
    for row, count in enumerate(valid):
        ids[row, count:] = 0
        mask[row, :count] = 1
    with torch.no_grad():
        hidden = model(input_ids=ids, attention_mask=mask).last_hidden_state
        bias = model.encoder.block[0].layer[0].SelfAttention.compute_bias(length, length)
        # The real model's bucket function over every distance a 512-token prompt can hold.
        real = model.encoder.block[0].layer[0].SelfAttention
        real.relative_attention_num_buckets = 32
        real.relative_attention_max_distance = 128
        positions = torch.arange(-600, 601)
        buckets = real._relative_position_bucket(positions)
    tensors = {
        f"text_encoder.{name}": value.detach().float().contiguous()
        for name, value in model.state_dict().items()
        # The release stores the token table once, as `shared.weight`.
        if name != "encoder.embed_tokens.weight"
    }
    assert "text_encoder.shared.weight" in tensors
    tensors["in.input_ids"] = ids.to(torch.int32).contiguous()
    tensors["in.attention_mask"] = mask.to(torch.int32).contiguous()
    tensors["out.last_hidden_state"] = hidden.float().contiguous()
    tensors["out.position_bias"] = bias.float().contiguous()
    tensors["in.bucket_relative_positions"] = positions.to(torch.int32).contiguous()
    tensors["out.buckets"] = buckets.to(torch.int32).contiguous()
    save_file(tensors, str(out / "text_encoder.safetensors"))
    print(f"text_encoder: {len(tensors)} tensors")


DUMPERS = {
    "tokenizer_ids": dump_tokenizer_ids,
    "text_encoder": dump_text_encoder,
}
