# Third-Party Notices

Zephra is proprietary software, copyright James Brink, all rights reserved. It
incorporates the following third-party components. Each is used under its own license. The
copyright notices required by those licenses are listed per component, the
NOTICE file that Apache-2.0 requires reproducing follows, and the full license
texts appear once per license type at the end of this file.

## Components

### zimage.swift

- **Source:** https://github.com/mzbac/zimage.swift
- **Copyright:** Copyright (c) 2025 mzbac
- **License:** MIT
- **Used as:** vendored into `Packages/ZImageKit` at commit `970f83e4`,
  providing the Z-Image diffusion pipeline, with modifications marked
  `ZEPHRA-PATCH`. See `Packages/ZImageKit/VENDORED.md` for the vendoring and
  patch log.
- **Note:** the upstream repository has no `LICENSE` file. Its `README.md`
  states the project is released under the MIT License; that statement is
  relied on here as the basis for the MIT text below.

### mlx-swift

- **Source:** https://github.com/ml-explore/mlx-swift
- **Copyright:** Copyright (c) 2023 ml-explore
- **License:** MIT
- **Used as:** the Metal/MLX runtime every pipeline is built on, a dependency
  of `ZImageKit`, `QwenImageKit`, `Flux2Kit`, `LTX2Kit`, `ZephraMLXKit`, the four
  backend packages, and `ZephraUpscaleRealESRGAN`. It compiles the following libraries
  into the same binary:
  - **mlx** — https://github.com/ml-explore/mlx — Copyright © 2023 Apple
    Inc. — MIT
  - **mlx-c** — https://github.com/ml-explore/mlx-c — Copyright (c) 2023
    ml-explore — MIT
  - **metal-cpp** — https://developer.apple.com/metal/cpp/ — Copyright
    Apple Inc. — Apache License 2.0
  - **{fmt}** — https://github.com/fmtlib/fmt — Copyright (c) 2012 - present,
    Victor Zverovich and {fmt} contributors — MIT
  - **JSON for Modern C++** — https://github.com/nlohmann/json — Copyright
    (c) 2013-2022 Niels Lohmann — MIT
  - **pocketfft** — https://gitlab.mpcdf.mpg.de/mtr/pocketfft — Copyright
    (C) 2010-2022 Max-Planck-Society, Copyright (C) 2019-2020 Peter Bell; the
    odd-sized DCT-IV transforms Copyright (C) 2003, 2007-14 Matteo Frigo and
    Massachusetts Institute of Technology — BSD 3-Clause. Header-only, included
    by mlx's CPU FFT (`mlx/backend/cpu/fft.cpp`), which is compiled on macOS.

### Qwen-Image port (`Packages/QwenImageKit`)

`Packages/QwenImageKit` is Zephra's own code, not a vendored copy of anything.
It is a clean-room MLX Swift implementation of Qwen-Image-2512, written from
the model's published configuration files and from these references, and it is
covered by Zephra's own license:

- **diffusers** — https://github.com/huggingface/diffusers — Copyright 2024
  The HuggingFace Team — Apache License 2.0 — the reference implementation the
  port's behaviour is defined against. `QwenImageKit`'s test fixtures are
  tensors dumped from it (see `Packages/QwenImageKit/Tools/dump_reference.py`).
- **mlx-gen** — https://github.com/lpalbou/mlx-gen — Copyright (c) lpalbou —
  MIT License — one finding, not code: that packing a Qwen-Image
  transformer's modulation layers at four bits costs coherent structure. It is
  why `QwenImageQuantizationPlan` holds them at eight.

No code was taken from `mzbac/qwen.image.swift`, which is GPL-3.0. See
`PROVENANCE.md` for what that means and how the boundary was kept.

One file follows an approach taken from the vendored MIT-licensed
`ZImageKit`: `Tokenizer/QwenImageTokenizer+Assembly.swift` assembles a byte-level BPE
tokenizer from `vocab.json` and `merges.txt`, because Qwen-Image ships no
`tokenizer.json` either. The assembly now follows `transformers`'
`Qwen2Tokenizer` (its own pre-tokenizer and every merge) rather than that copy's
GPT-2 configuration, but the approach is still ZImageKit's, and the zimage.swift
copyright notice above covers it.

### FLUX.2 port (`Packages/Flux2Kit`)

`Packages/Flux2Kit` is Zephra's own code, an MLX Swift implementation of
FLUX.2 klein 4B written in the same style as `QwenImageKit` and covered by
Zephra's own license. Unlike `QwenImageKit` it is not clean-room: it was
translated with attribution from two MIT-licensed Swift ports and the
Apache-2.0 reference, none of which restricts proprietary use. Its behaviour
is pinned against `diffusers`, not against either port, which is what makes
the places it deliberately departs from them checkable (see `PROVENANCE.md`).

- **flux2-klein-swift** — https://github.com/xocialize/flux2-klein-swift —
  Copyright (c) 2026 Xocialize — MIT License — the shape of the transformer:
  the modulation shared across blocks, the single-stream block's fused
  projection, and the four-axis rotary layout. Its scheduler, its query-key
  norm epsilon, and its handling of reference pictures were not followed.
- **flux-2-swift-mlx** — https://github.com/VincentGourbin/flux-2-swift-mlx —
  Copyright (c) 2025 Vincent Gourbin — MIT License — the schedule with the
  reference pipeline's empirical shift, the autoencoder's two towers, and how
  a reference picture is fitted and placed after the image being made.
- **mflux** — https://github.com/mflux-community/mflux — Copyright (c) 2026
  Filip Strand — MIT License — a third reading of the same architecture in
  Python; no code was taken.
- **diffusers** — https://github.com/huggingface/diffusers — Copyright 2024
  The HuggingFace Team — Apache License 2.0 — the reference implementation
  the port's behaviour is defined against. `Flux2Kit`'s test fixtures are
  tensors dumped from it (see `Packages/Flux2Kit/Tools/dump_reference.py`).

`xocialize/flux2-vae-mlx-swift`, which the first port takes its decoder from,
carries no license file and was never opened. The autoencoder here was
written from the second port and from `diffusers`.

### LTX-2.5 port (`Packages/LTX2Kit`)

`Packages/LTX2Kit` is Zephra's own code, an MLX Swift implementation of
LTX-2.5's video path — the distilled transformer's video stream, the Gemma 4
text encoder, the text connector and the convolutional video decoder — written
in the same style as `Flux2Kit` and covered by Zephra's own license. It was
translated with attribution from the Apache-2.0 reference implementations in
`diffusers` and `transformers`, and its behaviour is pinned against them by
tensors dumped from both (see `Packages/LTX2Kit/Tools/dump_reference.py`). Two
MLX ports were read as cross-checks; where they and the reference disagree the
reference was followed, and `PROVENANCE.md` lists the departures.

- **diffusers** — https://github.com/huggingface/diffusers — Copyright 2024
  The HuggingFace Team — Apache License 2.0 — the LTX-2 transformer block,
  the audio-video rotary embedding, the text connectors and the video
  autoencoder the port is defined against and dumps its fixtures from.
- **transformers** — https://github.com/huggingface/transformers — Copyright
  2018- The Hugging Face team — Apache License 2.0 — the Gemma 4 text model
  the encoder is defined against and dumps its fixtures from.
- **ltx-2-mlx** — https://github.com/dgrauet/ltx-2-mlx — Copyright (c) 2025
  dgrauet — MIT License — a Python MLX port read for the 2.5 pack's key
  names, its decoder's verified stage plan and its memory engineering; no
  code was taken.
- **ltx-2-mlx-swift** — https://github.com/xocialize/ltx-2-mlx-swift —
  Copyright 2026 xocialize — Apache License 2.0 — a Swift MLX port read for the Gemma 4 tokenizer's
  missing BOS, the float32 aggregate projection, the kernel-compilation
  warm-up and its measured envelopes; no code was taken.

`Lightricks/LTX-2`, the official PyTorch implementation, states no license for
its code. It was run to cross-check the audio-free forward and nothing was
copied from it.

### Wan 2.2 port (`Packages/WanKit`)

`Packages/WanKit` is Zephra's own code, an MLX Swift implementation of Wan 2.2
TI2V-5B — the video transformer, the UMT5-XXL text encoder and its tokenizer,
and the 2.2 video autoencoder — written in the same style as `LTX2Kit` and
covered by Zephra's own license. It was written from the Apache-2.0 reference
implementations in `diffusers` and `transformers` and from the release's own
configuration files, and its behaviour is pinned against them by tensors dumped
from both (see `Packages/WanKit/Tools/dump_reference.py`). No other port of Wan
was read; `PROVENANCE.md` lists the departures.

- **diffusers** — https://github.com/huggingface/diffusers — Copyright 2024
  The HuggingFace Team — Apache License 2.0 — the Wan transformer, its rotary
  embedding, the Wan autoencoder and the image-to-video pipeline's first-frame
  conditioning the port is defined against and dumps its fixtures from.
- **transformers** — https://github.com/huggingface/transformers — Copyright
  2018- The Hugging Face team — Apache License 2.0 — the UMT5 encoder the
  text encoder is defined against and dumps its fixtures from.
- **FastVideo** — https://github.com/hao-ai-lab/FastVideo — Copyright 2025
  the FastVideo team — Apache License 2.0 — the distribution-matching sampler
  read for the three timesteps, the training noise shift and the re-noising
  between steps; no code was taken.

### Real-ESRGAN upscaler (`Packages/ZephraUpscaleRealESRGAN`)

`Packages/ZephraUpscaleRealESRGAN` is Zephra's own code, an MLX Swift
implementation of the compact Real-ESRGAN network (SRVGGNetCompact) written
from the reference architecture file and covered by Zephra's own license.
It is the app's Upscale 2x / 4x, a post-process beside the image models.

- **Real-ESRGAN** — https://github.com/xinntao/Real-ESRGAN — Copyright (c)
  2021, Xintao Wang — BSD 3-Clause License — the network's shape
  (`realesrgan/archs/srvgg_arch.py`): the convolution and PReLU stack, the
  pixel shuffle, and the nearest-neighbour residual, translated with
  attribution from that file into MLX Swift and pinned by fixtures dumped from
  a plain PyTorch re-statement of it (see `Packages/ZephraUpscaleRealESRGAN/Tools`
  and the package's `PROVENANCE.md`).

`xocialize/realesrgan-mlx`, the Python MLX port a Hugging Face mirror points
at, carries no license file and was never opened.

### swift-transformers

- **Source:** https://github.com/huggingface/swift-transformers
- **Copyright:** Copyright 2022 Hugging Face SAS
- **License:** Apache License 2.0
- **Used as:** tokenizers, a dependency of `ZImageKit`, of `QwenImageKit`, and
  of `Flux2Kit`; `LTX2Kit` wrote its own encoder and does not link it. Zephra downloads model weights with its own client in
  `ZephraSnapshot` and no longer resolves or fetches anything through this
  package; `ZImageKit`'s vendored resolver still links it.

### swift-log

- **Source:** https://github.com/apple/swift-log
- **Copyright:** Copyright 2018, 2019 The SwiftLog Project
- **License:** Apache License 2.0 (NOTICE reproduced below)
- **Used as:** structured logging, pulled in as a dependency of `ZImageKit`.

### Jinja

- **Source:** https://github.com/johnmai-dev/Jinja
- **Copyright:** Copyright (c) 2024 John Mai
- **License:** MIT
- **Used as:** template rendering for tokenizer chat templates, pulled in
  transitively via `swift-transformers`.

### swift-collections

- **Source:** https://github.com/apple/swift-collections
- **Copyright:** Apple Inc. and the Swift project authors
- **License:** Apache License 2.0
- **Used as:** additional data structures, pulled in transitively.

### swift-numerics

- **Source:** https://github.com/apple/swift-numerics
- **Copyright:** Apple Inc. and the Swift project authors
- **License:** Apache License 2.0
- **Used as:** numeric protocols and algorithms, pulled in transitively.

### swift-argument-parser

- **Source:** https://github.com/apple/swift-argument-parser
- **Copyright:** Apple Inc. and the Swift project authors
- **License:** Apache License 2.0
- **Used as:** command-line argument parsing, pulled in transitively.

## Model weights

Not redistributed with the app. Every one of them is downloaded from Hugging
Face, on first use of the model that needs it, into the folder Settings > Models
names — `~/Library/Application Support/Zephra/Models` unless the user changes
it. Some are loaded as they are; the rest are built into a local variant on the
user's own machine, which the `make quantize*` targets also do by hand.

- **Tongyi-MAI/Z-Image-Turbo** — https://huggingface.co/Tongyi-MAI/Z-Image-Turbo
  — Copyright Alibaba Group (Tongyi Lab) — License: Apache License 2.0. The
  text encoder inside it is Qwen3-4B (Alibaba Cloud, Apache License 2.0).
- **mzbac/Z-Image-Turbo-8bit** — https://huggingface.co/mzbac/Z-Image-Turbo-8bit
  — Copyright (c) 2025 mzbac, a repacking of the Tongyi-MAI weights above —
  License: Apache License 2.0
- **Qwen/Qwen-Image-2512** — https://huggingface.co/Qwen/Qwen-Image-2512
  — Copyright Alibaba Cloud (Qwen team) — License: Apache License 2.0 — the
  transformer, the autoencoder, and the text encoder. The text encoder is
  Qwen2.5-VL-7B (Alibaba Cloud, Apache License 2.0), shipped inside this
  repository; Zephra loads its language layers and never its vision tower.
- **lightx2v/Qwen-Image-2512-Lightning** — https://huggingface.co/lightx2v/Qwen-Image-2512-Lightning
  — Copyright lightx2v — License: Apache License 2.0 — the four-step
  distillation adapter.
- **black-forest-labs/FLUX.2-klein-4B** — https://huggingface.co/black-forest-labs/FLUX.2-klein-4B
  — Copyright Black Forest Labs Inc. — License: Apache License 2.0 — the transformer, the autoencoder, and the
  text encoder. The text encoder is Qwen3-4B (Alibaba Cloud, Apache License
  2.0), shipped inside this repository byte for byte. The autoencoder's
  configuration names `black-forest-labs/FLUX.2-dev` as its origin, and that
  repository is under a non-commercial license; Zephra reads the autoencoder
  only from the klein-4B repository, which Black Forest Labs publishes whole
  under Apache 2.0, and never resolves FLUX.2-dev.

- **mlx-community/ltx-2.5-mlx** — https://huggingface.co/mlx-community/ltx-2.5-mlx
  — Copyright Lightricks Ltd. — License: LTX-2.x Community License Agreement
  (dated August 11, 2026; the pack ships it as `LICENSE.md`, and the packed
  variant carries that file beside its weights) — the distilled transformer,
  the text connector, the video decoder and the Gemma 4 text encoder, as bf16
  safetensors converted by the mlx-community from Lightricks' release. The
  text encoder is Google's Gemma 4 12B, fine-tuned by Lightricks: Google
  publishes Gemma 4 under the Apache License 2.0 (Copyright 2026 Google LLC;
  https://ai.google.dev/gemma/docs/gemma_4_license — Gemma 3 and earlier were
  under the Gemma Terms of Use, Gemma 4 is not), and Lightricks' fine-tuned
  weights are a derivative of both, so Apache's notice and the LTX-2.x license
  travel with them together.
  The LTX-2.x license is not a permissive one: entities with annual revenue
  of ten million dollars or more (measured with their affiliates, section 1.6)
  need a paid commercial agreement (section 2.1); Attachment A forbids, among
  other uses, training competing models (item 18), circumventing the model's
  provenance and watermarking features (item 19), and use in a product that
  directly competes with Lightricks' own (item 20); and a quantized pack is a
  "Derivative" (section 1.5) that must carry the license. Lightricks' own
  repositories are gated behind a click-through of the same license, which
  Zephra cannot perform, so the catalog names this redistribution.

- **FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers** —
  https://huggingface.co/FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers —
  Copyright 2025 the FastVideo team — License: Apache License 2.0 — the
  three-step distilled Wan 2.2 TI2V-5B transformer, the Wan 2.2 autoencoder
  and the UMT5-XXL text encoder with its tokenizer, in Diffusers layout.
  FastVideo distilled it from **Wan-AI/Wan2.2-TI2V-5B-Diffusers**
  (Copyright 2025 Alibaba Wan Team — Apache License 2.0), whose text encoder
  is Google's UMT5-XXL (Copyright Google LLC — Apache License 2.0), so one
  license covers every file the build reads.

None of the locally built variants is downloaded and none is redistributed. The
app derives each of them on the user's own Mac, the first time one is loaded:
the 4-bit Z-Image variant from **Tongyi-MAI/Z-Image-Turbo** above, the
Qwen-Image variant from **Qwen/Qwen-Image-2512** with the **Lightning** adapter
merged into its transformer, the two FLUX.2 klein variants from
**black-forest-labs/FLUX.2-klein-4B**, the LTX-2.5 variant from
**mlx-community/ltx-2.5-mlx**, and the Wan 2.2 variant from
**FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers**. The `make quantize`,
`make quantize-qwen`, `make quantize-flux2`, `make quantize-ltx2` and
`make quantize-wan` targets do the same builds by hand. All are written to
the folder Settings > Models names. Each is a modified
form of Apache-2.0 weights — for the Qwen build, of two sets of them — so the
Apache License 2.0 that covers those covers the result too.

One set of weights is redistributed with the app, because it is 2.4 MB and an
upscaler that needs a download is not worth having:

- **realesr-general-x4v3** — https://github.com/xinntao/Real-ESRGAN/releases/tag/v0.2.5.0
  — Copyright (c) 2021, Xintao Wang — BSD 3-Clause License — the compact
  Real-ESRGAN checkpoint, converted once to float16 safetensors by
  `Packages/ZephraUpscaleRealESRGAN/Tools/convert_weights.py` and bundled as a
  package resource. The release publishes the weights as assets of a
  BSD-3-Clause repository with no separate license of their own; the BSD terms
  are taken to cover them on that basis, and `PROVENANCE.md` in the package
  records that reading and the conversion's checksum.

---

## NOTICE files

### swift-log

```
                            The SwiftLog Project
                            ========================

Please visit the SwiftLog web site for more information:

  * https://github.com/apple/swift-log

Copyright 2018, 2019 The SwiftLog Project

The SwiftLog Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

-------------------------------------------------------------------------------

This product contains a derivation of the lock implementation and various
scripts from SwiftNIO.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-nio
```

---

## License texts

### MIT License

Applies to: zimage.swift, mlx-swift, mlx, mlx-c, {fmt}, JSON for Modern C++,
Jinja, flux2-klein-swift, flux-2-swift-mlx, and ltx-2-mlx, each with the
copyright notice listed for it above.

```
MIT License

Copyright (c) 2025 mzbac
Copyright (c) 2023 ml-explore
Copyright (c) 2023 Apple Inc.
Copyright (c) 2012 - present, Victor Zverovich and {fmt} contributors
Copyright (c) 2013-2022 Niels Lohmann
Copyright (c) 2024 John Mai
Copyright (c) 2026 Xocialize
Copyright (c) 2025 Vincent Gourbin
Copyright (c) 2025 dgrauet

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Apache License, Version 2.0

Applies to: swift-transformers, swift-log, swift-collections, swift-numerics,
swift-argument-parser, metal-cpp, diffusers, transformers, ltx-2-mlx-swift,
Google's Gemma 4 12B (inside the LTX-2.5 text encoder), and the model weights
listed above: Z-Image-Turbo and its 8-bit repacking, Qwen-Image-2512 with its
Qwen2.5-VL-7B text encoder, the Qwen-Image-2512-Lightning adapter, and
FLUX.2-klein-4B with its Qwen3-4B text encoder.

```
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing
      the origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS
```

### BSD 3-Clause License

Applies to: Real-ESRGAN (the network's architecture and the
`realesr-general-x4v3` weights), and pocketfft (compiled into mlx). Each
holder's own notice follows; the license conditions are the same text.

```
Copyright (c) 2021, Xintao Wang
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

```
pocketfft

Copyright (C) 2010-2022 Max-Planck-Society
Copyright (C) 2019-2020 Peter Bell

For the odd-sized DCT-IV transforms:
  Copyright (C) 2003, 2007-14 Matteo Frigo
  Copyright (C) 2003, 2007-14 Massachusetts Institute of Technology

Authors: Martin Reinecke, Peter Bell

All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this
  list of conditions and the following disclaimer in the documentation and/or
  other materials provided with the distribution.
* Neither the name of the copyright holder nor the names of its contributors may
  be used to endorse or promote products derived from this software without
  specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### LTX-2.x Community License Agreement

Applies to: the LTX-2.5 weights in mlx-community/ltx-2.5-mlx and the variant Zephra
packs from them. Reproduced from the pack's `LICENSE.md`, headings flattened.

```
LTX-2.x Community License Agreement

*License date: August 11, 2026*

**By downloading, using, accessing or distributing any portion or element of LTX-2.x, you agree that you have read and accepted to be bound by this Agreement.**

**1. Definitions.**

> **1.1** **“Agreement”** means the terms and conditions for this LTX-2.x Community License Agreement and the exhibits, attachments, and Complementary Materials, as specified in this document.

> **1.2** **“Complementary Materials”** means the accompanying documentation, tutorials, examples, configuration files and other materials made available by Licensor together with the LTX-2.x model weights and parameters, in each case as distributed by Licensor.

> **1.3** **“Control”** means the direct or indirect ownership of more than fifty percent (50%) of the voting securities or other ownership interests, or the power to direct the management and policies of such Entity through voting rights, contract, or otherwise.

> **1.4** **“Data”** means a collection of information and/or content extracted from the dataset used with LTX-2.x, including to train, pretrain, or otherwise evaluate LTX-2.x. The Data is not licensed under this Agreement.

> **1.5** **“Derivatives of LTX-2.x”** means all modifications to LTX-2.x, works based on LTX-2.x, or any other model which is created or initialized by transfer of patterns of the weights, parameters, activations or output of LTX-2.x, to the other model, in order to cause the other model to perform similarly to LTX-2.x, including – but not limited to - distillation methods entailing the use of intermediate data representations or methods based on the generation of synthetic data by LTX-2.x for training the other model. For clarity, Derivatives of LTX-2.x include: (i) any fine-tuned or adapted weights, parameters, or checkpoints derived from LTX-2.x; (ii) derivative model architectures that incorporate or are based upon LTX-2.x’s architecture; and (iii) any modified or extended versions of the Complementary Materials.

> **1.6** **“Entity”** means any individual, corporation, partnership, limited liability company, or other legal entity. For purposes of this Agreement, an Entity shall be deemed to include, on an aggregative basis, all subsidiaries, affiliates, and other companies under common Control with such Entity. When determining whether an Entity meets any threshold under this Agreement (including revenue thresholds in Section 2.1), all subsidiaries, affiliates, and companies under common Control shall be considered collectively.

> **1.7** **“Harm”** includes but is not limited to physical, mental, psychological, financial and reputational damage, pain, or loss.

> **1.8** **“Licensor”** or **“LTX”** means the owner that is granting the license under this Agreement. For the purposes of this Agreement, the Licensor is Lightricks Ltd.

> **1.9** **“LTX-2.x”** means the large generative models, text/image/video/audio/3D generation models, and multimodal large language models and their software and algorithms, including trained model weights, parameters (including optimizer states), machine-learning model code, inference-enabling code, training-enabling code, fine-tuning enabling code, accompanying source code, scripts, and all other elements of the foregoing distributed and made publicly available by LTX (including, for example, at [https://github.com/Lightricks/LTX-2](https://github.com/Lightricks/LTX-2)). This license is applicable to all LTX-2.5 versions released since August 11, 2026, and all future releases of LTX-2.x under this license.

> **1.10** **“Output”** means the results of operating LTX-2.x as embodied in informational content resulting therefrom.

> **1.11** **“you”** (or **“your”**) means an individual or legal Entity licensing LTX-2.x in accordance with this Agreement and/or otherwise downloading, accessing, distributing or using LTX-2.x for whichever purpose and in any field of use, including usage of LTX-2.x in an end-use application - e.g. chatbot, translator, image generator.

**2. Grant of License.**

> **2.1** Subject to your compliance with the terms and conditions of this Agreement, you are granted a non-exclusive, worldwide, non-transferable and royalty-free limited license under Licensor’s intellectual property or other rights owned by Licensor embodied in LTX-2.x to use, reproduce, prepare, distribute, publicly display, publicly perform, sublicense, copy, create derivative works of, and make modifications to LTX-2.x, for any purpose, subject to the restrictions set forth in Attachment A; **provided however, that Entities with annual revenues of at least $10,000,000 (the “Commercial Entities”) are required to obtain a paid license for any use (excluding use solely for a Non-Commercial Purpose as set forth in Section 2.2) of LTX-2.x and Derivatives of LTX-2.x (such paid license referred to herein as a “Commercial Use Agreement”), as will be provided by the Licensor. Commercial Entities interested in such a commercial license are required to [contact Licensor](mailto:ltxv-licensing@lightricks.com). Any use of LTX-2.x or Derivatives of LTX-2.x by Commercial Entities not in accordance with this Agreement and/or the Commercial Use Agreement is strictly prohibited and shall be deemed a material breach of this Agreement. In the event of such material breach, and without limiting Licensor’s right to terminate the Agreement or to pursue any other remedies available at law or in equity, you shall pay Licensor the license fees owed for the period such Commercial Entity used LTX-2.x (calculated at Licensor’s standard commercial license fees, in effect during the relevant period or, absent published standard fees, a reasonable market rate for a comparable license), within thirty (30) days of Licensor’s written demand.**

> **2.2** Notwithstanding the foregoing or anything to the contrary in this Agreement, a Commercial Entity may download and use LTX-2.x and Derivatives of LTX-2.x without obtaining the Commercial Use Agreement solely for a Non-Commercial Purpose. **“Non-Commercial Purpose”** means any of the following uses, but only so far as such Commercial Entity does not receive any direct or indirect payment arising from the use of LTX-2.x or Derivatives of LTX-2.x: (i) use by an individual acting in a personal capacity for research, experimentation, learning, private study, hobby or recreational projects, or personal entertainment, in each case where such use is not connected, directly or indirectly, to any commercial activity, business operation, or the performance of duties for an employer or any other Entity; and (ii) use by a Commercial Entity for testing, evaluation, or non-commercial research and development in a non-production or development environment. For clarity, use (a) for revenue-generating activity in any manner, whether direct or indirect, (b) in direct interactions with or that has impact on end users, or (c) to train, fine-tune, or distill any model (including any Derivative of LTX-2.x) for commercial use, in each case, is not a Non-Commercial Purpose and requires all Commercial Entities to obtain a paid license under the Commercial Use Agreement prior to such use. For the avoidance of doubt, the permission granted under this Section 2.2 is a limited right of use only and does not convey or transfer any ownership right, title, or interest in or to LTX-2.x or any Derivatives of LTX-2.x, and all Derivatives of LTX-2.x created or used pursuant to this Section 2.2 remain subject to the terms of this Agreement, including Section 1.5.

**3. Distribution and Redistribution.** You may host for third parties remote access purposes (e.g. software-as-a-service), reproduce and distribute copies of LTX-2.x or Derivatives of LTX-2.x thereof in any medium, with or without modifications, provided that you meet the following conditions:

> **3.1** Use-based restrictions as referenced in Section 4 and all provisions of Attachment A MUST be included as an enforceable provision by you in any type of legal agreement (e.g. a license) governing the use and/or distribution of LTX-2.x or Derivatives of LTX-2.x, and you shall give notice to subsequent users you distribute to, that LTX-2.x or Derivatives of LTX-2.x are subject to Section 4 and Attachment A in their entirety, including all use restrictions and acceptable use policies;

> **3.2** You must provide any third-party recipients of LTX-2.x or Derivatives of LTX-2.x a copy of this Agreement, including all attachments and use policies. Any Derivative of LTX-2.x (as defined in Section 1.5, including but not limited to fine-tuned weights, modified training code, models trained on Outputs, or any other derivative) must be distributed exclusively under the terms of this Agreement, subject to Section 3.6, with a complete copy of this Agreement included;

> **3.3** You must cause any modified files to carry prominent notices stating that you changed the files;

> **3.4** You must retain all copyright, patent, trademark, and attribution notices excluding those notices that do not pertain to any part of LTX-2.x, Derivatives of LTX-2.x.

> **3.5** Transfer of Derivatives. No transfer of any Derivative of LTX-2.x (including any fine-tuned weights, LoRA adapters, or similar adaptations) to a third party shall grant such third party any right, title, license, or authorization to access, use, reproduce, distribute, or exploit LTX-2.x, or any Derivative of LTX-2.x beyond the rights granted under this Agreement. If the transferee is a Commercial Entity (as defined in Section 2), it must obtain a paid license from Licensor prior to any use of any Derivative of LTX-2.x, regardless of who created such Derivative. Prior to or at the time of any such transfer, you shall notify the transferee in writing that (i) use of such Derivative of LTX-2.x is subject to the terms of this Agreement, and (ii) if the transferee is a Commercial Entity, it must obtain a separate paid license to LTX-2.x from Licensor. You shall not transfer any Derivative of LTX-2.x to a Commercial Entity unless such Commercial Entity has obtained the required paid license from Licensor prior to any use, and unless the proposed transferee has been so informed. You and the transferee shall each be responsible for ensuring the transferee obtains the required license from Licensor prior to any use of LTX-2.x or Derivative of LTX-2.x. Nothing in this Section 3.5 shall require a Commercial Entity to obtain a paid license for use solely for a Non-Commercial Purpose as permitted under Section 2.2.

> **3.6** You may add your own copyright statement to your modifications and may provide additional license terms and conditions - **respecting Section 3.1** - for use, reproduction, or distribution of your modifications, or for any such Derivatives of LTX-2.x as a whole, provided your use, reproduction, and distribution of LTX-2.x otherwise complies with the conditions stated in this Agreement, and you provide a complete copy of this Agreement with any such use, reproduction and distribution of LTX-2.x and any Derivatives thereof; provided that any such additional terms shall be additive only and shall not derogate from, conflict with, waive, or purport to modify any term of this Agreement, and this Agreement shall govern in the event of any conflict.

**4. Use-based restrictions.** The restrictions set forth in Attachment A are considered Use-based restrictions. Therefore, you cannot use LTX-2.x and the Derivatives of LTX-2.x in violation of the specified restricted uses. You may use LTX-2.x subject to this Agreement, only for lawful purposes and in accordance with the Agreement. **“Use”** may include creating any content with, fine-tuning, updating, running, training, evaluating and/or re-parametrizing LTX-2.x. You shall require all of your users who use LTX-2.x or a Derivative of LTX-2.x to comply with the terms of this Section 4.

**5. The Output You Generate.** Except as set forth herein, Licensor claims no rights in the Output you generate using LTX-2.x. You are accountable for input you insert into LTX-2.x, the Output you generate and its subsequent uses. No use of the Output can contravene any provision as stated in the Agreement.

**6. Updates and Runtime Restrictions; AI Regulations.** To the maximum extent permitted by law, Licensor reserves the right to restrict (remotely or otherwise) usage of LTX-2.x in violation of this Agreement, update LTX-2.x through electronic means, or modify the Output of LTX-2.x based on updates. You shall undertake reasonable efforts to use the latest version of LTX-2.x. Any use of the non-current version of LTX-2.x is done solely at your risk. To the extent applicable to you, you shall comply with all laws and regulations governing artificial intelligence that apply to your use, deployment, or distribution of LTX-2.x, Derivatives of LTX-2.x, or Outputs, including Regulation (EU) 2024/1689 (the “EU AI Act”) and the California AI Transparency Act (Cal. Bus. & Prof. Code § 22757 et seq.), each as amended from time to time and any other applicable laws, regulations, or binding guidance relating to artificial intelligence, transparency, content provenance, or synthetic media, together with any documentation made available by Licensor regarding compliance with the same (collectively, “AI Regulations”). You shall maintain (including within any application or service through which LTX-2.x, any Derivative of LTX-2.x, or any Output is made available), and shall not remove, disable, alter, or circumvent, any safety or security measures, disclosures, metadata, watermarking, content provenance, latent disclosure, or other transparency features or functionalities included or embedded within LTX-2.x or any Derivative of LTX-2.x, or applied to any Output, in furtherance of AI Regulations, including any capability of LTX-2.x to include latent disclosures in Outputs, and you shall include equivalent obligations in any agreement governing your distribution of LTX-2.x or any Derivative of LTX-2.x. You are solely responsible for any transparency, disclosure, marking, or labeling obligations applicable to you under AI Regulations as a provider or deployer of LTX-2.x, any Derivative of LTX-2.x, or any system incorporating any of the foregoing, including any obligation to disclose that content is artificially generated or manipulated. If Licensor knows or reasonably believes that you have modified LTX-2.x or any Derivative of LTX-2.x such that it is no longer capable of including any disclosure required by AI Regulations in Outputs, or that you have otherwise removed, disabled, or circumvented any feature or functionality described in this Section, Licensor may in its sole discretion revoke the license granted under this Agreement effective immediately upon notice to you, and upon such revocation you shall immediately cease all use of LTX-2.x and Derivatives of LTX-2.x. Licensor makes no representation or warranty that LTX-2.x, any Derivative of LTX-2.x, or any Output complies with any AI Regulations applicable to your specific use case or deployment, and you are solely responsible for determining the applicability of, and ensuring your compliance with, all AI Regulations. You shall indemnify, defend, and hold harmless Licensor and its affiliates from and against any and all claims, liabilities, losses, damages, costs, and expenses (including reasonable attorneys’ fees) arising out of or relating to your use, deployment, distribution, or modification of LTX-2.x, any Derivative of LTX-2.x, or any Output in violation of, or your other failure to comply with, any AI Regulations.

> For purposes of the EU AI Act, Licensor makes LTX-2.x openly available under this community license and intends that LTX-2.x be treated as a free and open-source general purpose AI model within the meaning of Article 53(2) of the EU AI Act. You acknowledge and agree that (a) to the extent the free and open source derogations under Article 53(2) of the EU AI Act apply, Licensor’s obligations under the EU AI Act with respect to LTX-2.x are limited to those applicable to providers of free and open source general purpose AI models (it being acknowledged that such derogations do not extend to the obligations under Article 53(1)(c) and (d)), (b) you acknowledge that LTX-2.x is not intended to be integrated into a high risk AI system, and shall be fully and solely responsible for any obligation resulting from such integration, (c) if you integrate LTX-2.x or any Derivative of LTX-2.x into a high-risk AI system you shall be solely responsible for all provider obligations that would otherwise apply to Licensor under the EU AI Act, and (d) you shall not take any action, or omit to take any action, that would cause Licensor to lose the benefit of the free and open source derogations under the EU AI Act, and you shall indemnify and hold Licensor harmless from any liability, costs, or expenses arising from your breach of this Section.

**7. Export Controls and Sanctions Compliance.** You acknowledge that LTX-2.x, Derivatives of LTX-2.x may be subject to export control laws and regulations, including but not limited to the U.S. Export Administration Regulations and sanctions programs administered by the Office of Foreign Assets Control (OFAC). You represent and warrant that you and any users of LTX-2.x are not (i) located in, organized under the laws of, or ordinarily resident in any country or territory subject to comprehensive sanctions; (ii) identified on any U.S. government restricted party list, including the Specially Designated Nationals and Blocked Persons List; or (iii) otherwise prohibited from receiving LTX-2.x under applicable law. You shall not export, re-export, or transfer LTX-2.x, directly or indirectly, in violation of any applicable export control or sanctions laws or regulations. You agree to comply with all applicable trade control laws and shall indemnify and hold Licensor harmless from any claims arising from your failure to comply with such laws.

**8. Trademarks; Reservation of Rights.** Nothing in this Agreement permits you to make use of Licensor’s trademarks, trade names, logos or to otherwise suggest endorsement or misrepresent the relationship between the parties; and any rights not expressly granted herein are reserved by the Licensor. Except as expressly set forth in this Agreement, Licensor does not grant, directly or by implication, estoppel, statute or otherwise, any right or license in its, or its affiliates’, intellectual property rights or other proprietary rights. For avoidance of doubt, all intellectual property rights in Derivatives of LTX-2.x shall be subject to the terms of this Agreement, and you acquire no right, title, or interest in or to LTX-2.x itself, which is and remains the exclusive property of Licensor. You shall not assert any ownership or other right in LTX-2.x or any Derivative of LTX-2.x in any manner that restricts, encumbers, or is inconsistent with the rights retained by Licensor or granted to other licensees under this Agreement.

**9. Disclaimer of Warranty.** Unless required by applicable law or agreed to in writing, Licensor provides LTX-2.x on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, including, without limitation, any warranties or conditions of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE. You are solely responsible for determining the appropriateness of using or redistributing LTX-2.x and Derivatives of LTX-2.x and assume any risks associated with your exercise of permissions under this Agreement.

**10. Limitation of Liability.** To the fullest extent permitted by applicable law, in no event and under no legal theory, whether in tort (including negligence), contract, or otherwise, unless required by applicable law (such as deliberate and grossly negligent acts) or agreed to in writing, shall Licensor be liable to you or any other individual or Entity for damages, including any direct, indirect, special, incidental, or consequential damages of any character arising as a result of this Agreement or out of the use of, or inability to use LTX-2.x or any Derivative of LTX-2.x (including but not limited to damages for loss of goodwill, work stoppage, computer failure or malfunction, or any and all other commercial damages or losses), even if Licensor has been advised of the possibility of such damages.

**11. Accepting Warranty or Additional Liability.** While redistributing LTX-2.x and Derivatives of LTX-2.x, you may, provided you do not violate the terms of this Agreement, choose to offer and charge a fee for, acceptance of support, warranty, indemnity, or other liability obligations. However, in accepting such obligations, you may act only on your own behalf and on your sole responsibility, not on behalf of Licensor, and only if you agree to indemnify, defend, and hold Licensor harmless for any liability incurred by, or claims asserted against Licensor, by reason of your accepting any such warranty or additional liability.

**12. Governing Law.** This Agreement and all relations, disputes, claims and other matters arising hereunder (including non-contractual disputes or claims) will be governed exclusively by, and construed exclusively in accordance with, the laws of the State of New York and applicable U.S. federal law. To the extent permitted by law, choice of laws rules and the United Nations Convention on Contracts for the International Sale of Goods will not apply. The prevailing party in any claim or dispute between the parties under this Agreement will be entitled to reimbursement of its reasonable attorneys’ fees and costs.

**13. Term and Termination.** This Agreement is effective upon your acceptance and continues until terminated. Licensor may terminate this Agreement immediately upon written notice to you if you breach any provision of this Agreement, including but not limited to violations of the use restrictions in Attachment A or unauthorized commercial use. This Agreement also terminates immediately and automatically, without notice, upon any material breach of this Agreement, including any use in violation of applicable AI Regulations or any unauthorized commercial use of LTX-2.x or Derivatives of LTX-2.x by a Commercial Entity. Upon termination: (a) all rights granted to you under this Agreement will immediately cease; (b) you must immediately cease all use of LTX-2.x and Derivatives of LTX-2.x; (c) you must delete or destroy all copies of LTX-2.x and Derivatives of LTX-2.x in your possession or control; and (d) you must notify any third parties to whom you distributed LTX-2.x or Derivatives of LTX-2.x of the termination. Sections 2, 3, 4, 6-16 and Attachment A shall survive termination of this Agreement. Termination does not relieve you of any obligations incurred prior to termination, including payment obligations under Section 2 and adhering to the restrictions under Section 3. In addition, if You commence a lawsuit or other proceedings (including a cross-claim or counterclaim in a lawsuit) against Licensor or any person or entity alleging that LTX-2.x or any Output, or any portion of any of the foregoing, infringe any intellectual property or other right owned or licensable by you, then all licenses granted to you under this Agreement shall terminate as of the date such lawsuit or other proceeding is filed.

**14. Disputes and Arbitration; Waiver of Jury Trial; Class Action Waiver.** **IF YOU ARE NOT ACTING AS A CONSUMER UNDER APPLICABLE LAW, YOU HEREBY WAIVE THE RIGHT TO A TRIAL BY JURY, TO PARTICIPATE IN A CLASS OR REPRESENTATIVE ACTION (INCLUDING IN ARBITRATION), OR TO COMBINE INDIVIDUAL PROCEEDINGS IN COURT OR IN ARBITRATION WITHOUT THE CONSENT OF ALL PARTIES.** All disputes arising in connection with this Agreement shall be finally settled by arbitration under the Rules of Arbitration of the International Chamber of Commerce (“ICC Rules”), by one (1) arbitrator appointed in accordance with the ICC Rules. The seat of arbitration shall be New York, NY, USA, and the proceedings shall be conducted in English. The arbitrator shall be empowered to grant any relief that a court could grant. Judgment on the arbitration award may be entered by any court having jurisdiction thereof. Notwithstanding the foregoing, either party may seek injunctive or other equitable relief in respect of any actual or threatened breach of the license restrictions under this Agreement (including Attachment A and the Acceptable Use Policy) or any actual or threatened infringement, misappropriation, or violation of Licensor’s intellectual property rights, in the state or federal courts located in the County of New York, State of New York, and each party irrevocably consents to the jurisdiction of, and venue in, such courts for that limited purpose. The foregoing waivers do not apply to, and are not enforceable against, any licensee acting as a consumer under the mandatory consumer-protection laws of its jurisdiction of residence (including, without limitation, the European Union, the United Kingdom, and the State of California), and nothing in this Agreement limits any rights under such laws that cannot be waived or limited by contract. If any waiver in this Section is held invalid or unenforceable as to a particular licensee or dispute, such waiver shall be severed to that extent only and shall not affect the validity or enforceability of the remainder of this Section.

**15.** In the event of any exception to the application of binding arbitration, all disputes, claims, and other matters arising hereunder shall be brought exclusively in the state or federal courts located in the County of New York, State of New York. You waive all defenses of lack of personal jurisdiction and forum non conveniens with respect to venue and jurisdiction in such courts, and consent to their exclusive jurisdiction and venue.

**16. Severability.** If any provision of this Agreement is held to be invalid, illegal or unenforceable, the remaining provisions shall be unaffected thereby and remain valid as if such provision had not been set forth herein.

**END OF TERMS AND CONDITIONS**

Attachment A

*Use Restrictions*

When using the Outputs, LTX-2.x and any Derivatives thereof, you agree to comply with the [Acceptable Use Policy](https://static.lightricks.com/legal/ltx-acceptable-use-policy.pdf) which is hereby incorporated into and made part of this Agreement by reference. Licensor may update it from time to time, and the version in effect at the time of your use governs; continued use after an update constitutes acceptance. Licensor shall post each version of the Acceptable Use Policy with its effective date, and no update shall apply retroactively to use occurring before that effective date. In addition, you agree not to use the Outputs, LTX-2.x or its Derivatives in any of the following ways:

> **1)** In any way that violates any applicable national, federal, state, local or international law or regulation;

> **2)** For the purpose of exploiting, Harming or attempting to exploit or Harm minors in any way;

> **3)** Knowingly generate or disseminate verifiably false information and/or content with the intent to deceive, defraud, or otherwise unlawfully Harm others;

> **4)** To generate or disseminate personal identifiable information that can be used to Harm an individual;

> **5)** To generate or disseminate information and/or content (e.g. images, code, posts, articles), and place the information and/or content in any context (e.g. bot generating tweets) without expressly and intelligibly disclaiming that the information and/or content is machine generated;

> **6)** To defame others, or to engage in the unlawful harassment of others;

> **7)** To impersonate or attempt to impersonate (e.g. deepfakes) others without their consent;

> **8)** For fully automated decision making that adversely impacts an individual’s legal rights or otherwise creates or modifies a binding, enforceable obligation;

> **9)** For any use intended to or which has the effect of discriminating against or Harming individuals or groups based on online or offline social behavior or known or predicted personal or personality characteristics;

> **10)** To exploit any of the vulnerabilities of a specific group of persons based on their age, social, physical or mental characteristics, in order to materially distort the behavior of a person pertaining to that group in a manner that causes or is likely to cause that person or another person physical or psychological Harm;

> **11)** For any use intended to or which has the effect of discriminating against individuals or groups based on legally protected characteristics or categories;

> **12)** To provide medical advice and medical results interpretation;

> **13)** To generate or disseminate information for the purpose to be used for administration of justice, law enforcement, immigration or asylum processes, such as predicting an individual will commit fraud/crime commitment (e.g. by text profiling, drawing causal relationships between assertions made in documents, indiscriminate and arbitrarily-targeted use);

> **14)** To generate and/or disseminate malware (including – but not limited to – ransomware) or any other content to be used for the purpose of harming electronic systems;

> **15)** To engage in, promote, incite, or facilitate discrimination or other unlawful or harmful conduct in the provision of employment, employment benefits, credit, housing, or other essential goods and services;

> **16)** To engage in, promote, incite, or facilitate the harassment, abuse, threatening, or bullying of individuals or groups of individuals;

> **17)** For military, warfare, nuclear industries or applications, weapons development, or any use in connection with activities that may cause death, personal injury, or severe physical or environmental damage;

> **18)** For commercial use only: To train, improve, or fine-tune any other machine learning model, artificial intelligence system, or competing model, except for Derivatives of LTX-2.x as expressly permitted under this Agreement;

> **19)** To circumvent, disable, or interfere with any technical limitations, safety features, content filters, watermarking, content provenance or latent disclosure functionalities, or use restrictions implemented in LTX-2.x by Licensor;

> **20)** To use LTX-2.x or Derivatives of LTX-2.x in any product, service, or application that directly competes with Licensor’s commercial products or services, or is designed to replace or substitute Licensor’s offerings in the market, without obtaining a separate commercial license from Licensor.
```
