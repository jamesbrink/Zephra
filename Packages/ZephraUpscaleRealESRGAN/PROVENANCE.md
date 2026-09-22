# Provenance of `Packages/ZephraUpscaleRealESRGAN`

Zephra may ship commercially, so where this port came from is a legal question and not only a
technical one. The root `PROVENANCE.md` makes the same record for `Packages/QwenImageKit` and
`Packages/Flux2Kit`; this file is the upscaler's, because the upscaler is the first thing in the
repository that ships somebody else's **trained weights** inside the app rather than downloading
them, and that is a different claim from shipping a translation of their code.

## The short version

`Packages/ZephraUpscaleRealESRGAN` is a translation with attribution of one class,
`SRVGGNetCompact`, from `xinntao/Real-ESRGAN` (BSD-3-Clause, Copyright (c) 2021, Xintao Wang).
BSD-3-Clause permits translating with attribution, whatever the result is licensed under, so
there was no reason to pretend to a clean room. The bundled checkpoint is that repository's
own published `realesr-general-x4v3` release asset, converted to float16 safetensors by
`Tools/convert_weights.py` and by nothing else.

**`xocialize/realesrgan-mlx` has no license file and was never opened.** It is the obvious
starting point — an existing MLX Swift port of exactly this network — and that is precisely why
it is named here: unlicensed code is not permissively licensed code, and a port derived from it
would carry no grant at all.

## What was used

| Reference | License | What was taken |
|---|---|---|
| `xinntao/Real-ESRGAN`, `realesrgan/archs/srvgg_arch.py` | BSD-3-Clause | The architecture: the flat `body` list, the first convolution and PReLU, the `num_conv` repeated pairs, the last convolution widening to `num_out_ch * upscale * upscale`, the `PixelShuffle(upscale)`, and the nearest-neighbour residual added at the end. `Tools/dump_reference.py` carries a transcription of the class in torch, with the `basicsr` registry decorator and the unused activation types dropped, so the Swift port is pinned against the reference's own arithmetic rather than against our reading of it. |
| `xinntao/Real-ESRGAN` v0.2.5.0 release asset | see below | The `realesr-general-x4v3.pth` weights. |
| `pytorch/pytorch` `nn.PixelShuffle` | BSD-3-Clause (documented behaviour) | The channel-major, row, column ordering the shuffle has to reproduce. Pinned by a fixture whose values are an `arange`. |
| `ml-explore/mlx-swift` | MIT | `Conv2d`, `PReLU`, `Module`. Already a dependency of every package here. |

Nothing was taken from `xocialize/realesrgan-mlx`, and no GPL-licensed source was consulted.

## What the checkpoint is, exactly

`Tools/convert_weights.py` downloads

```
https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth
```

(4,885,111 bytes), unwraps the state dict, casts to float16, and writes
`Sources/ZephraUpscaleRealESRGAN/Resources/Weights/realesr-general-x4v3-fp16.safetensors`.

| | |
|---|---|
| Unwrapped key | **`params`** (the tool falls back to `params_ema` and prints which it used) |
| Tensors | 101 |
| Parameters | 1,213,296 |
| Written | 2,434,624 bytes |
| SHA-256 | `417badb1acc1ff609a06fb727502fd97f7c2a73c56a52647397d58848de70619` |

Both numbers are here so a re-conversion is checkable. The parameter count is what says this is
`num_feat=64, num_conv=32` — no configuration file ships with the checkpoint, and the arithmetic
(1792 + 64 + 32 x 36992 + 27696) is the only thing that names the shape. `params` versus
`params_ema` matters for the same reason: picking the wrong one is a silent swap of one trained
network for another, and nothing downstream would notice.

Nothing is renamed and nothing is transposed by the tool. The OIHW to OHWI transpose that MLX
wants happens in Swift, in `SRVGGNetWeights`, where `SRVGGNetParityTests` pins it.

## The weights' license is inherited, not granted

This is the one open point, and it is written down rather than assumed.

`xinntao/Real-ESRGAN` carries a BSD-3-Clause `LICENSE` at its root, and the `.pth` is published
as a release asset of that repository. There is **no separate license statement attached to the
weights themselves** — no model card, no LICENSE beside the asset, no explicit grant. So the
BSD-3-Clause status of the checkpoint Zephra bundles is inherited from the repository that
publishes it, and `THIRD_PARTY_NOTICES.md` says so in those words rather than claiming a grant
that was never made.

The related open question is the training data. `realesr-general-x4v3` is a general-purpose
model trained, per the repository's own documentation, on DIV2K and similar academic datasets,
several of which are published for research use. Whether those terms reach a commercial
redistribution of the trained weights is not settled by the repository's LICENSE, and it is not
a question this port can answer. `ROADMAP.md` lists the check as a prerequisite of any
commercial release; until then the exposure is 2.4 MB of bundled weights that can be removed and
replaced with a download, which is the alternative the plan costed and deliberately did not take.

## Where this port departs from the reference, on purpose

- **NHWC throughout.** MLX convolutions are channels-last, so the pixel shuffle and the
  nearest residual are written against the last axis rather than against axis 1. The ordering
  is identical; only where the axis sits differs. `PixelShuffleTests` checks that against a
  torch fixture rather than trusting the argument.
- **RGB, not BGR.** The reference command-line tool reads images with OpenCV, which is BGR, and
  swaps back on the way out. That is an artifact of the tool, not of the model: the channel
  order the network was trained on is whatever `cv2.imread` produced consistently, and the two
  swaps cancel. This port reads and writes RGB and never swaps.
- **Alpha, the reference tool's way.** The reference tool has an RGBA path that upscales the
  alpha channel separately, and this port does the same: `UpscalePixelBuffer.pixels` splits a
  transparent picture into its straight colour and its alpha, `RealESRGANUpscaler` runs the
  colour through the network as itself and the alpha through as a grey triplet whose three
  outputs are meaned back into one plane, and the result is recombined as straight RGBA. The
  network never learned a fourth channel, but it did learn to enlarge a grey picture, and an
  alpha plane is one. A picture with no alpha channel runs one lane and is byte for byte what
  it always was; its matte is white now rather than the black an uncleared buffer gave, which
  it never sees.
- **2x is 4x then an exact 2x2 box mean.** There is no 2x checkpoint in this family worth
  carrying beside the 4x one, and a box mean over a whole number of pixels is the one downsample
  with no filter design to defend. It means 2x costs what 4x costs plus the mean, which the
  interface should say rather than imply the opposite.
- **Tiled by default, at 512 input pixels.** The reference tool tiles only when asked. Here the
  tiler is `ZephraMLX.TiledDecode`, the same one the autoencoders use, because the peak of an
  untiled 2048-pixel input is set by the picture rather than by the model.
- **The denoise blend is not implemented.** `realesr-general-wdn-x4v3` is a second checkpoint of
  the same shape, and the reference's denoise strength is a linear interpolation between the two
  weight sets rather than a change to the network. `SRVGGNetWeights.sanitized` already takes the
  second dictionary and a fraction, so adding it is an argument rather than a rewrite. v1 never
  passes it and the second checkpoint is not bundled.

## How the boundary is kept honest

`Tools/dump_reference.py` runs the transcribed torch class at a doll's-house size — eight
features, two body convolutions, both `upscale=2` and `upscale=4`, a `[1, 3, 6, 5]` input that
is odd and non-square — and writes the weights, the input, and the output to
`Tests/ZephraUpscaleRealESRGANTests/Fixtures`. The Swift suites assert against those, to 1e-4.
Eight features rather than one is deliberate: eight distinct PReLU alphas is what makes a
per-tensor broadcast fail where a per-channel one passes.

Every tolerance is against those **float32** fixtures. The bundled float16 checkpoint is never
compared by value — only by name, shape, and parameter count — because float16 rounding would
swamp a 1e-4 claim and turn a real regression into noise.
