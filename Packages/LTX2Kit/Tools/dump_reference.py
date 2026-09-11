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
"""Dump reference tensors from the Apache-2.0 diffusers and transformers implementations of LTX-2.5.

Every fixture this writes is a claim about what the reference does, checked in Swift by the
matching test. Files are tiny on purpose: a doll's-house configuration catches a transposed axis
or a swapped modulation chunk exactly as well as a real one, and can be committed.

The video path is dumped with the audio stream's contribution switched off (the official model's
`audio=None` forward, which is what a video-only pack runs), so a fixture states what this port
is meant to compute and not what the full audio-video model computes.

The dependency versions above are pinned so a fixture says what produced it; bump them together
and regenerate every fixture in the same commit. `versions.json` beside the fixtures records what
the last run used.

Run with `uv run Tools/dump_reference.py --out Tests/LTX2Tests/Fixtures`.
"""

import argparse
import pathlib
import sys

import torch

# Each component's dumper lives beside this script in a module of its own, so a component can
# be regenerated alone with --only and its dumper read next to its Swift test.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import dump_audio  # noqa: E402
import dump_text_encoder  # noqa: E402
import dump_transformer  # noqa: E402
import dump_upsampler  # noqa: E402
import dump_vae  # noqa: E402


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
    dumpers = {}
    dumpers.update(dump_text_encoder.DUMPERS)
    dumpers.update(dump_transformer.DUMPERS)
    dumpers.update(dump_vae.DUMPERS)
    dumpers.update(dump_upsampler.DUMPERS)
    dumpers.update(dump_audio.DUMPERS)
    selected = arguments.only or list(dumpers)
    unknown = [name for name in selected if name not in dumpers]
    if unknown:
        parser.error(f"unknown fixture(s) {unknown}; known: {sorted(dumpers)}")
    for name in selected:
        dumpers[name](arguments.out)
    write_versions(arguments.out)


if __name__ == "__main__":
    main()
