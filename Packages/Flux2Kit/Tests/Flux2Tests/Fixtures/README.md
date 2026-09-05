Reference tensors dumped from the Apache-2.0 `diffusers` implementation of FLUX.2 klein, used
to check this port's arithmetic against it. Each file holds a module's inputs and the outputs
those produce, with random weights where the module has any, at a doll's-house size — small
enough to commit, large enough to catch a transposed axis or a swapped modulation chunk.
`timestep_bf16.safetensors` is the one dumped in bfloat16, because the two roundings it pins
are invisible in float32.

Regenerate with `uv run Tools/dump_reference.py --out Tests/Flux2Tests/Fixtures`. The script's
inline metadata pins the versions of the reference stack it runs under, and every run writes
`versions.json` beside the fixtures with the versions it actually used, so a fixture says what
produced it. The pins were added on 2026-09-05, after the fixtures here were dumped; the
`versions.json` committed with them is the pinned set, and the first regeneration under it
is what will make the two provably one and the same. Bump the pins and regenerate every
fixture in the same commit.
