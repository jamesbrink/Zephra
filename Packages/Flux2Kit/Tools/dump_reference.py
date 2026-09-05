# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "torch==2.14.0",
#     "diffusers==0.40.0",
#     "transformers==5.16.1",
#     "tokenizers==0.23.2",
#     "safetensors==0.8.0",
#     "numpy==2.5.2",
# ]
# ///
"""Dump reference tensors from the Apache-2.0 diffusers implementation of FLUX.2.

Every fixture this writes is a claim about what the reference does, checked in Swift by the
matching test. Files are tiny on purpose: a doll's-house configuration catches a transposed axis
or a swapped modulation chunk exactly as well as a real one, and can be committed.

The dependency versions above are pinned so a fixture says what produced it; bump them
together and regenerate every fixture in the same commit. `versions.json` beside the fixtures
records what the last run used.

Run with `uv run Tools/dump_reference.py --out Tests/Flux2Tests/Fixtures`.
"""

import argparse
import pathlib
import sys

import torch
from safetensors.torch import save_file

# Each component's dumper lives beside this script in a module of its own, so a component can
# be regenerated alone with --only and its dumper read next to its Swift test.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import dump_reference_conditioning  # noqa: E402
import dump_text_encoder  # noqa: E402
import dump_transformer  # noqa: E402
import dump_vae  # noqa: E402


def _ids(t, h, w, l):
    """Position ids the way the pipeline builds them: the cartesian product of the four axes."""
    return torch.cartesian_prod(torch.arange(t), torch.arange(h), torch.arange(w), torch.arange(l))


def dump_rope(out: pathlib.Path) -> None:
    """Flux2PosEmbed's tables for three id layouts, de-interleaved to one angle per pair.

    The reference repeats each cosine twice so it lines up with the interleaved channels; the
    port keeps one per pair and pairs the channels itself, so the dump keeps one per pair too,
    after asserting the two halves were equal.
    """
    from diffusers.models.transformers.transformer_flux2 import Flux2PosEmbed

    rope = Flux2PosEmbed(theta=2000, axes_dim=[4, 4, 4, 4])
    layouts = {
        "text": _ids(1, 1, 1, 5),
        "image": _ids(1, 3, 4, 1),
        # A 2x3 target followed by a 3x2 reference at image index 10.
        "edit": torch.cat([_ids(1, 2, 3, 1), _ids(1, 3, 2, 1) + torch.tensor([10, 0, 0, 0])]),
    }
    tensors = {}
    for label, ids in layouts.items():
        cos, sin = rope(ids)
        assert torch.equal(cos[:, 0::2], cos[:, 1::2]), "the reference interleaves pairs"
        tensors[f"{label}.ids"] = ids.to(torch.int32).contiguous()
        tensors[f"{label}.cos"] = cos[:, 0::2].float().contiguous()
        tensors[f"{label}.sin"] = sin[:, 0::2].float().contiguous()
    save_file(tensors, str(out / "rope.safetensors"))
    print(f"rope: {len(tensors)} tensors")


def dump_patchify(out: pathlib.Path) -> None:
    """The pipeline's own patchify and flatten, on a tensor whose values name their coordinates."""
    from diffusers.pipelines.flux2.pipeline_flux2_klein import Flux2KleinPipeline

    latent = torch.arange(1 * 8 * 6 * 4, dtype=torch.float32).reshape(1, 8, 6, 4)
    packed = Flux2KleinPipeline._patchify_latents(latent)
    tokens = Flux2KleinPipeline._pack_latents(packed)
    assert torch.equal(Flux2KleinPipeline._unpatchify_latents(packed), latent)
    save_file(
        {"latent": latent.contiguous(), "packed": packed.contiguous(), "tokens": tokens.contiguous()},
        str(out / "patchify.safetensors"),
    )
    print("patchify: 3 tensors")


def dump_scheduler(out: pathlib.Path) -> None:
    """The sigma ladder and shift the klein pipeline uses, at several sizes and step counts."""
    import numpy as np
    from diffusers import FlowMatchEulerDiscreteScheduler
    from diffusers.pipelines.flux2.pipeline_flux2_klein import compute_empirical_mu

    config = {
        "num_train_timesteps": 1000,
        "shift": 3.0,
        "use_dynamic_shifting": True,
        "base_shift": 0.5,
        "max_shift": 1.15,
        "base_image_seq_len": 256,
        "max_image_seq_len": 4096,
        "shift_terminal": None,
        "time_shift_type": "exponential",
    }
    tensors = {}
    # 4400 and 9216 cross the branch the fit changes at; one step guards the step term.
    for steps, tokens in [(4, 4096), (4, 1024), (8, 4096), (28, 4096), (4, 9216), (4, 4400), (1, 4096)]:
        scheduler = FlowMatchEulerDiscreteScheduler.from_config(config)
        mu = compute_empirical_mu(tokens, steps)
        # The pipeline passes its own ladder, linspace(1, 1/steps, steps), and its own mu.
        scheduler.set_timesteps(sigmas=np.linspace(1.0, 1 / steps, steps), mu=mu)
        tensors[f"steps{steps}.tokens{tokens}.sigmas"] = scheduler.sigmas.float().contiguous()
        tensors[f"steps{steps}.tokens{tokens}.mu"] = torch.tensor(mu, dtype=torch.float32)
    save_file(tensors, str(out / "scheduler.safetensors"))
    print(f"scheduler: {len(tensors)} tensors")


def write_versions(out: pathlib.Path) -> None:
    """Records which versions of the reference stack wrote the fixtures beside it."""
    import json
    from importlib.metadata import version

    packages = ["torch", "diffusers", "transformers", "tokenizers", "safetensors", "numpy"]
    (out / "versions.json").write_text(
        json.dumps({name: version(name) for name in packages}, indent=2) + "\n"
    )
    print("versions: " + ", ".join(f"{name} {version(name)}" for name in packages))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--only", nargs="*", default=None)
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)

    torch.manual_seed(0)
    dumpers = {
        "rope": dump_rope,
        "patchify": dump_patchify,
        "scheduler": dump_scheduler,
        "reference_conditioning": dump_reference_conditioning.dump,
        "text_encoder": dump_text_encoder.dump,
        "transformer": dump_transformer.dump,
        "timestep_bf16": dump_transformer.dump_timestep_bf16,
        "vae": dump_vae.dump,
    }
    for name, dumper in dumpers.items():
        if arguments.only and name not in arguments.only:
            continue
        dumper(arguments.out)
    write_versions(arguments.out)


if __name__ == "__main__":
    main()
