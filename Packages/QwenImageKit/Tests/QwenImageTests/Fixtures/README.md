Reference tensors dumped from the Apache-2.0 `diffusers` implementation, used to check this
port's arithmetic against it. Each file holds a module's inputs and the outputs those produce,
with random weights where the module has any, at a doll's-house size — small enough to commit, large enough to catch a
transposed axis or a swapped modulation chunk.

Regenerate with `Tools/dump_reference.py`.
