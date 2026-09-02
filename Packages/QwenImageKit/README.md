# QwenImageKit

An MLX Swift implementation of [Qwen-Image](https://huggingface.co/Qwen/Qwen-Image-2512)
(Apache 2.0), written for Zephra.

## Provenance

This package is **first-party, clean-room**. It was implemented from the published
architecture — the model's own `config.json` files, the Apache-2.0 `diffusers`
reference implementation, and the MIT-licensed `mflux` and `mlx-gen` Python
projects. No Swift source was copied from `mzbac/qwen.image.swift`, which is
GPL-3.0 and would make Zephra GPL-3.0; nobody working on this package should
open it, including to "check" something.

Some generic infrastructure — safetensors reading, hub resolution, tokenizer
loading, the tiled-decode algorithm — is copied from `Packages/ZImageKit`, which
is MIT (`mzbac/zimage.swift` at `970f83e4`). Every such file says so at the top
and has an entry in the repository's `THIRD_PARTY_NOTICES.md`.

## What it implements

Text-to-image only. Qwen-Image's text-to-image path feeds the text encoder token
ids and an attention mask and never touches Qwen2.5-VL's vision tower, so the ViT
is deliberately not ported and its weights are not loaded. Image editing would
need it; that is a later problem.
