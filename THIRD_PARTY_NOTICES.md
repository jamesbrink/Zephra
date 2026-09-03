# Third-Party Notices

Zephra is proprietary software (see `LICENSE`) that incorporates the
following third-party components. Each is used under its own license. The
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
  of `ZImageKit`, `QwenImageKit`, `ZephraMLXKit`, and both backend packages.
  It compiles the following libraries into the same binary:
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

### Qwen-Image port (`Packages/QwenImageKit`)

`Packages/QwenImageKit` is Zephra's own code, not a vendored copy of anything.
It is a clean-room MLX Swift implementation of Qwen-Image-2512, written from
the model's published configuration files and from these references, and it is
covered by Zephra's own `LICENSE`:

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
`ZImageKit`: `Tokenizer/QwenImageTokenizer.swift` assembles a byte-level BPE
tokenizer from `vocab.json` and `merges.txt` the same way, because Qwen-Image
ships no `tokenizer.json` either. The zimage.swift copyright notice above
covers it.

### FLUX.2 port (`Packages/Flux2Kit`)

`Packages/Flux2Kit` is Zephra's own code, an MLX Swift implementation of
FLUX.2 klein 4B written in the same style as `QwenImageKit` and covered by
Zephra's own `LICENSE`. Unlike `QwenImageKit` it is not clean-room: it was
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

### Real-ESRGAN upscaler (`Packages/ZephraUpscaleRealESRGAN`)

`Packages/ZephraUpscaleRealESRGAN` is Zephra's own code, an MLX Swift
implementation of the compact Real-ESRGAN network (SRVGGNetCompact) written
from the reference architecture file and covered by Zephra's own `LICENSE`.
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
- **Used as:** tokenizer and Hugging Face Hub model resolution, a dependency
  of `ZImageKit`, of `QwenImageKit`, and of `Flux2Kit`, which also downloads
  through it.

### swift-log

- **Source:** https://github.com/apple/swift-log
- **Copyright:** Copyright 2018, 2019 The SwiftLog Project
- **License:** Apache License 2.0 (NOTICE reproduced below)
- **Used as:** structured logging, pulled in as a dependency of `ZImageKit`.

### Jinja

- **Source:** https://github.com/huggingface/swift-jinja
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

Not redistributed with the app. The default model is downloaded on first run
from Hugging Face into `~/.cache/huggingface/hub`; the others are fetched by
`make quantize` and `make prefetch-qwen` and built into a local variant on the
user's own machine.

- **Tongyi-MAI/Z-Image-Turbo** — https://huggingface.co/Tongyi-MAI/Z-Image-Turbo
  — License: Apache License 2.0
- **mzbac/Z-Image-Turbo-8bit** — https://huggingface.co/mzbac/Z-Image-Turbo-8bit
  — License: Apache License 2.0
- **Qwen/Qwen-Image-2512** — https://huggingface.co/Qwen/Qwen-Image-2512
  — License: Apache License 2.0
- **lightx2v/Qwen-Image-2512-Lightning** — https://huggingface.co/lightx2v/Qwen-Image-2512-Lightning
  — License: Apache License 2.0 — the four-step distillation adapter.
- **black-forest-labs/FLUX.2-klein-4B** — https://huggingface.co/black-forest-labs/FLUX.2-klein-4B
  — License: Apache License 2.0 — the transformer, the autoencoder, and the
  text encoder. The text encoder is Qwen3-4B (Alibaba Cloud, Apache License
  2.0), shipped inside this repository byte for byte. The autoencoder's
  configuration names `black-forest-labs/FLUX.2-dev` as its origin, and that
  repository is under a non-commercial license; Zephra reads the autoencoder
  only from the klein-4B repository, which Black Forest Labs publishes whole
  under Apache 2.0, and never resolves FLUX.2-dev.

None of the locally built variants is downloaded and none is redistributed.
`make quantize` derives the Z-Image one on the user's own Mac from
**Tongyi-MAI/Z-Image-Turbo** above; `make quantize-qwen` derives the Qwen-Image
one from **Qwen/Qwen-Image-2512** with the **Lightning** adapter merged into its
transformer; the app itself derives the FLUX.2 klein variants from
**black-forest-labs/FLUX.2-klein-4B** the first time one is loaded. All are
written to `~/Library/Application Support/Zephra/Models`. Each is a modified
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
Jinja, flux2-klein-swift, and flux-2-swift-mlx, each with the copyright notice
listed for it above.

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
swift-argument-parser, metal-cpp, diffusers, and the Z-Image and Qwen-Image
model weights.

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
`realesr-general-x4v3` weights).

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
