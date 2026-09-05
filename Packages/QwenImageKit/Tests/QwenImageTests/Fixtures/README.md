Reference tensors dumped from the Apache-2.0 `diffusers` implementation, used to check this
port's arithmetic against it. Each file holds a module's inputs and the outputs those produce,
with random weights where the module has any, at a doll's-house size — small enough to commit, large enough to catch a
transposed axis or a swapped modulation chunk.

`tokenizer_ids.json` is the one fixture that is not a doll's house: the ids the Hugging Face
`Qwen2Tokenizer` produces for twenty-five prompts from the real `vocab.json` and `merges.txt`,
with the pipeline's own prompt template and the count of tokens it drops. Regenerating it
needs those files: `--tokenizer <snapshot>/tokenizer`, or nothing, and they are fetched from
`Qwen/Qwen-Image-2512`. The file records the `transformers` and `tokenizers` versions that
wrote it.

Regenerate with `Tools/dump_reference.py`; its inline metadata pins the versions of the
reference stack it runs under, so `uv run Tools/dump_reference.py --out
Tests/QwenImageTests/Fixtures --tokenizer <snapshot>/tokenizer` reproduces them, and every
run writes `versions.json` beside the fixtures with the versions it actually used. The
tokenizer fixture was dumped under those pins and records them itself; the safetensors
fixtures predate the pin, and the `versions.json` committed with them is the pinned set
until the first regeneration under it. Bump the pins and regenerate every fixture in the
same commit.
