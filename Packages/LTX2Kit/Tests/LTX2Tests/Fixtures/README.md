Reference tensors dumped from the Apache-2.0 `diffusers` (LTX-2 transformer, connectors and
video autoencoder) and `transformers` (Gemma 4) implementations, used to check this port's
arithmetic against them. Each file holds a module's inputs and the outputs those produce, with
random weights where the module has any, at a doll's-house size: small enough to commit, large
enough to catch a transposed axis or a swapped modulation chunk.

The transformer fixtures are dumped with the audio-to-video cross-attention switched off, which
is the official model's `audio=None` forward and the only path a video-only pack runs.
`transformer_conditioned` is the same model handed a per-token `timestep`, which is how a held
first frame reaches it; the audio lane keeps the scalar there, as the reference's own
image-to-video pipeline passes it.

Three files are not doll's-house dumps: `tokenizer.safetensors` is ids from the real Gemma 4
tokenizer, which `Tools/dump_text_encoder.py` fetches from the ungated
`mlx-community/ltx-2.5-mlx` pack into a gitignored `Tools/.cache`; and `vae_decoder_keys.json`
and `vae_encoder_keys.json` are the real pack's key lists with shapes for the two halves of the
autoencoder, read once from each file's header (the same way `WeightKeyCoverageTests` reads them
live) and committed so `VAEWeightKeyTests` and `VAEEncoderWeightKeyTests` run without the pack.

Regenerate with `uv run Tools/dump_reference.py --out Tests/LTX2Tests/Fixtures`; `--only
<name>` regenerates one fixture. The script's
inline metadata pins the versions of the reference stack it runs under, and every run writes
`versions.json` beside the fixtures with the versions it actually used, so a fixture says what
produced it. Bump the pins and regenerate every fixture in the same commit.
