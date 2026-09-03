# Roadmap

What Zephra should build next, in order, and what was deliberately left out of the
work already done. The order was set on 3 September 2026 after FLUX.2 klein and
reference-picture editing landed; the survey behind it lives in the session notes.

Standing decisions: no CI for now (`make test` and `make test-mlx` are the gate, run
locally before every merge), and no release or distribution work until the app is
ready to ship.

## Next steps, in order

1. **Upscale with Real-ESRGAN** (in progress on `feat/upscale`). A post-process beside
   the backends; see `Packages/ZephraUpscaleRealESRGAN`.
2. **Several reference pictures at once.** klein assigns each picture its own image
   index on the rotary embedding, so this is mostly plumbing: `referenceImage` becomes
   a list capped by a new capability, the well beside the prompt becomes a row, and the
   record stores every picture. Measure the peak first; one 512 reference already lifts
   a 1024 edit to 19.2 GB.
3. **Qwen-Image-Edit-2511 with Lightning.** The strongest editor with a clean license,
   on the transformer the clean-room port already runs. Needs the Qwen2.5-VL vision
   tower the port skips today. 32 GB Macs only. Reference from mflux or mlx-gen (MIT),
   never `mzbac/qwen.image.swift` (GPL-3.0).
4. **Z-Image base**, for guidance and a negative prompt. One to three days, but 28 to
   50 steps with two passes each is about eight minutes per 1024 image on an M4 Max:
   a quality mode, not a daily one. Do it when those controls matter as features.
5. **Runtime LoRA.** Adapters are merged at build time today. A low-rank delta at
   matmul time on the quantized transformer, an adapter slot on the settings and in
   the record, a picker in the capsule. Start with klein, the smallest transformer.
6. **Hygiene.** Rerun `make bench` idle for every catalog entry and refresh the figures
   (the Qwen entry has not been re-measured since its VAE encoder was added). Try 6-bit
   or mxfp8 on Qwen-Image's 6.8B modulation weights, which cost 3.4 GB at 8-bit.

Deferred: **ERNIE-Image-Turbo** (eight to twelve days for legible in-image text at
16 GB; the Mistral3 encoder is the new work), **Boogu-Image-0.1-Turbo** (a credible
Qwen-Image successor for 32 GB Macs, still at a few hundred downloads), and
**Z-Image-Edit** (unreleased; would share the Z-Image backend).

## Upscaler follow-ups

Left out of the first pass on purpose, each a small change to one file unless noted:

- The **wdn denoise blend** and a strength slider. The weight loader already takes a
  second state dict and a blend weight; bundle `realesr-general-wdn-x4v3` and add the
  control to the inspector.
- **Download-on-demand weights** instead of the bundled 2.4 MB, if the bundle ever
  needs to shrink. Needs an availability state and a host for a converted safetensors.
- **Lanczos 2x** instead of the exact 2x2 box mean, which is what the reference tool
  does with `--outscale`. Slightly sharper, one more code path.
- **Alpha carried through.** The network is run on RGB only and the result is written
  opaque, which loses nothing for the library's own PNGs.
- **Upscaling a multi-selection**, one after another on the inference queue.
- **A sidebar timeline entry** for an upscale, beside the runs.
- **Float16 compute** if a 2048 input is measurably slow; the switch is one cast at
  load and one on the input.
- **Row-by-row joining in `TiledDecode`** for 4096 inputs, so the peak stops growing
  with the output.
- **A bench flag**, `make bench ARGS="--upscale IMAGE"`, for the same measurements the
  models get.
- **The DIV2K training-data terms.** Real-ESRGAN's repository is BSD-3-Clause and the
  weights are taken to inherit it, but the training set's own terms were not verified.
  Check before any commercial release.
