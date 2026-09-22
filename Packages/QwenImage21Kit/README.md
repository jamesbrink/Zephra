# QwenImage21Kit

Zephra's port of **Qwen-Image 2.1** to Swift and MLX. Ours, clean-room from the release's own
configuration files and the Apache-2.0 `diffusers` and `transformers` sources, pinned by dumped
fixtures. Nothing was read from `mzbac/qwen.image.swift`, which is GPL-3.0, or from any other
port of this model.

The reference is `diffusers` at commit `6256aa7666cedd47443adc8f82da9a10e110b09c` and
`transformers` 5.17.0. Both differ from the pins the other three kits use, and the reason is in
`Tests/QwenImage21Tests/Fixtures/README.md`.

## What this kit is, in one paragraph

A 7.1-billion-parameter rectified-flow transformer over a 64-channel, **four-channel-picture**
autoencoder — 2.1 carries alpha — conditioned on the penultimate hidden states of a Qwen3-VL
that reads the prompt and any reference pictures together. Three things about it are unlike
Qwen-Image 2512 and each of them loads cleanly and then makes noise: there is **one shared
modulation table** for all 32 blocks rather than a table per block; `patch_size` is **1**, so one
transformer token is one latent cell and nothing is patchified anywhere; and there are **no
biases** in the transformer at all.

## Layout

```
Sources/QwenImage21/
  Model/        the transformer, the text encoder and the autoencoder
  Pipeline/     the schedule, the packing, the prompt templates and the denoising loop
  Tokenizer/    Qwen2's byte-level BPE, over the release's own tokenizer.json
  Util/         sizes, fitting, pixels
  Weights/      every published config, read and checked before a weight is touched
Tests/QwenImage21Tests/
  Fixtures/     what the reference produced, and the README that says how
Tools/          the eight dumpers and their driver, PEP 723 scripts run with uv
```

## Running the tests

```
cd Packages/QwenImage21Kit
xcodebuild test -scheme QwenImage21Kit -destination 'platform=macOS' \
  -skipPackagePluginValidation -parallel-testing-enabled NO
```

`-parallel-testing-enabled NO` is not optional here, and it is the flag `make test-mlx` already
passes every MLX package for the same reason: in parallel, an autoencoder parity suite that
lands beside a heavy one reads a tensor back off by whole units, and the same suite passes
alone. `PipelineParityTests` is that heavy one, and with it in the suite
`TiledDecodeTests` fails in parallel and passes serially.

`swift test` does not work here: the package links mlx-swift, whose Metal kernels need
`xcodebuild`.

The suites that read a real release skip without one. They look at
`QWEN_IMAGE_21_SNAPSHOT` — spelled `TEST_RUNNER_QWEN_IMAGE_21_SNAPSHOT` under `xcodebuild` —
then the app's own models folder, then `/Volumes/ExternalStorage/Models/Qwen-Image-2.1`, then a
hub cache holding exactly one snapshot.

**Two of those do load weights**, which is a departure from the repository's rule and is stated
in `PROVENANCE.md`: five autoencoder suites read `vae/*.safetensors` (1.35 GB, a second to
run), and `PipelineParityTests` loads the whole release streamed and runs two steps end to end
against what `diffusers` produced for the same noise. That last one is 35 seconds streamed
against the suite's usual three, and it is the one test that says this port makes the
reference's picture. Everything else here runs on a Mac with no release at all.

## The licence

The weights are **not** under a permissive licence. The release ships its own terms, and they
are non-commercial; this kit is Zephra's code and says nothing about what the weights allow.
See `THIRD_PARTY_NOTICES.md` at the repository root, which is the disclosure that is bundled
and shown in the Acknowledgments window.

## Deliberate departures

Each one is listed in `PROVENANCE.md` beside this file, and each is there because it is a place
this port does something the reference does not, on purpose.
