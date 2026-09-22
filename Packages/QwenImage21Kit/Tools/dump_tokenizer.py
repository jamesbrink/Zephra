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
"""The ids Hugging Face's own tokenizer gives 25 prompts, both templates, and the drop index.

The drop index is the point of the file. The pipeline renders the system turn through the chat
template once, in `__init__`, counts its tokens and throws that many hidden states away before
the transformer sees anything; a count that is one out shifts every conditioning vector by a
token. It comes to 14 for this checkpoint, and the Swift side asserts that against the real
tokenizer rather than trusting the constant.

`uv run Tools/dump_tokenizer.py`, with QWEN_IMAGE_21_SNAPSHOT naming the release.
"""

import argparse
import json
import pathlib

SYS_PROMPT = "Comprehend and analyze the provided prompt."

TEMPLATE_T2I = (
    f"<|im_start|>system\n{SYS_PROMPT}<|im_end|>\n"
    "<|im_start|>user\n{}<|im_end|>\n"
    "<|im_start|>assistant\n"
)

TEMPLATE_TI2I = (
    f"<|im_start|>system\n{SYS_PROMPT}<|im_end|>\n"
    "<|im_start|>user\n<image1><|vision_start|><|image_pad|><|vision_end|>{}<|im_end|>\n"
    "<|im_start|>assistant\n"
)

# Twenty-five prompts: plain ASCII, punctuation and hyphenation (where Qwen2's pre-tokenizer
# regex differs from GPT-2's), digits (taken one at a time), CJK, emoji and combining marks,
# every flavour of whitespace, and one very long one for the truncation rule.
PROMPTS = [
    "",
    " ",
    "a red door",
    "A cat.",
    "high-quality, black-and-white photograph of a lighthouse",
    "###",
    "12345",
    "3.14159 and 2.71828",
    "a photo of a cat sitting on a mat, 4k, ultra-detailed, cinematic lighting",
    "CAPS LOCK SHOUTING",
    "trailing space ",
    " leading space",
    "double  space  between  words",
    "line\nbreak",
    "tab\tseparated",
    "\n\n\n",
    "mixed\r\nnewlines",
    "一只红色的狐狸坐在雪地里",
    "日本語のテキストとひらがな",
    "한국어 텍스트",
    "Здравствуй, мир",
    "emoji: a cat and a rocket",
    "café vs café",
    "emoji \U0001F431 \U0001F680 \U0001F469‍\U0001F4BB",
    " ".join(["lantern"] * 900),
]


def load_tokenizer(snapshot: pathlib.Path):
    """The release's own tokenizer, through the processor when transformers will build one."""
    from transformers import AutoProcessor, AutoTokenizer

    directory = str(snapshot / "processor")
    try:
        processor = AutoProcessor.from_pretrained(directory)
        return processor.tokenizer, processor
    except Exception as error:  # noqa: BLE001 - the fallback is the point
        print(f"AutoProcessor refused {directory} ({error}); falling back to AutoTokenizer")
        return AutoTokenizer.from_pretrained(directory), None


def drop_index(tokenizer, processor) -> tuple[int, list[int]]:
    """`_drop_idx`: the tokens the rendered system turn costs, and what those tokens are."""
    message = [{"role": "system", "content": [{"type": "text", "text": SYS_PROMPT}]}]
    source = processor if processor is not None else tokenizer
    ids = source.apply_chat_template(message, tokenize=True, return_dict=False)
    # transformers returns a batch of one, and sometimes a tensor; normalise to a list of ints.
    while isinstance(ids, (list, tuple)) and len(ids) == 1 and isinstance(ids[0], (list, tuple)):
        ids = ids[0]
    ids = [int(value) for value in ids]
    return len(ids), ids


def dump(out: pathlib.Path) -> None:
    import dump_reference

    snapshot = dump_reference.snapshot()
    tokenizer, processor = load_tokenizer(snapshot)
    count, system_ids = drop_index(tokenizer, processor)

    fixture = {
        "sysPrompt": SYS_PROMPT,
        "templateT2I": TEMPLATE_T2I,
        "templateTI2I": TEMPLATE_TI2I,
        "dropIndex": count,
        "systemTurnIDs": system_ids,
        "templateT2IEmptyPromptIDs": tokenizer.encode(TEMPLATE_T2I.replace("{}", "")),
        "templateTI2IEmptyPromptIDs": tokenizer.encode(TEMPLATE_TI2I.replace("{}", "")),
        "prompts": [
            {"text": prompt, "ids": tokenizer.encode(prompt)} for prompt in PROMPTS
        ],
        "wrapped": [
            {"text": prompt, "ids": tokenizer.encode(TEMPLATE_T2I.replace("{}", prompt))}
            for prompt in PROMPTS[:5]
        ],
        "specialIDs": {
            token: tokenizer.convert_tokens_to_ids(token)
            for token in [
                "<|endoftext|>",
                "<|im_start|>",
                "<|im_end|>",
                "<|vision_start|>",
                "<|vision_end|>",
                "<|vision_pad|>",
                "<|image_pad|>",
                "<|video_pad|>",
            ]
        },
    }
    (out / "tokenizer_ids.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + "\n")
    print(f"tokenizer: {len(PROMPTS)} prompts, drop index {count}")


def main() -> None:
    import dump_reference

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=dump_reference.default_out())
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    dump(arguments.out)
    dump_reference.write_versions(arguments.out)


if __name__ == "__main__":
    import sys

    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    main()
