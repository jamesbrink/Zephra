# QwenImageKit

An MLX Swift implementation of [Qwen-Image](https://huggingface.co/Qwen/Qwen-Image-2512)
(Apache 2.0), written for Zephra.

## Provenance

This package is **first-party, clean-room**, written from the model's own
`config.json` files and the Apache-2.0 `diffusers` reference implementation, and
checked against tensors dumped from `diffusers` by `Tools/dump_reference.py`. No
Swift source was copied from `mzbac/qwen.image.swift`, which is GPL-3.0 and would
make Zephra GPL-3.0; nobody working on this package should open it, including to
"check" something. The repository's `PROVENANCE.md` is the full record of what was
and was not consulted, and `THIRD_PARTY_NOTICES.md` the disclosure; the one idea
taken from the vendored `Packages/ZImageKit` (assembling a byte-level BPE tokenizer
from `vocab.json` and `merges.txt`) is noted at the top of the file that uses it.

## What it implements

Text-to-image only. Qwen-Image's text-to-image path feeds the text encoder token
ids and an attention mask and never touches Qwen2.5-VL's vision tower, so the ViT
is deliberately not ported and its weights are not loaded. Image editing would
need it; that is a later problem.
