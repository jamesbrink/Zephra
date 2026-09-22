# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "torch==2.14.0",
#     "diffusers @ git+https://github.com/huggingface/diffusers@6256aa7666cedd47443adc8f82da9a10e110b09c",
#     "transformers==5.17.0",
#     "tokenizers==0.23.2",
#     "safetensors==0.8.0",
#     "numpy==2.5.2",
#     "pillow",
#     "torchvision",
# ]
# ///
"""Dump reference tensors from the Apache-2.0 diffusers implementation of Qwen-Image 2.1.

Every fixture this writes is a claim about what the reference does, checked in Swift by the
matching test. Files are tiny on purpose: a doll's-house configuration catches a transposed axis
or a swapped modulation chunk exactly as well as a real one, and can be committed.

The pins above are **not** the other three kits' pins, and the difference is deliberate:
Qwen-Image 2.1 landed in diffusers after 0.40.0 was cut, so diffusers comes from the commit the
port was read at; and Qwen3-VL needs transformers 5.17. See `Tests/QwenImage21Tests/Fixtures/README.md`.

Every dumper here is also runnable on its own — `uv run Tools/dump_scheduler.py` — since the
ones that need a snapshot are useless without one and the ones that do not should not wait for
a 33 GB download.

Run with `uv run Tools/dump_reference.py --out Tests/QwenImage21Tests/Fixtures`.
"""

import argparse
import json
import os
import pathlib
import sys

import torch

# Each component's dumper lives beside this script in a module of its own, so a component can
# be regenerated alone with --only and its dumper read next to its Swift test.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import dump_pipeline  # noqa: E402
import dump_rope  # noqa: E402
import dump_scheduler  # noqa: E402
import dump_text_encoder  # noqa: E402
import dump_tokenizer  # noqa: E402
import dump_transformer  # noqa: E402
import dump_vae  # noqa: E402
import dump_vision  # noqa: E402

PACKAGES = ["torch", "diffusers", "transformers", "tokenizers", "safetensors", "numpy"]


def default_out() -> pathlib.Path:
    """The fixtures directory this kit's tests read, relative to this script."""
    return pathlib.Path(__file__).resolve().parent.parent / "Tests" / "QwenImage21Tests" / "Fixtures"


def snapshot() -> pathlib.Path:
    """The Qwen-Image 2.1 release on this Mac, named by QWEN_IMAGE_21_SNAPSHOT."""
    path = os.environ.get("QWEN_IMAGE_21_SNAPSHOT", "")
    if not path:
        raise SystemExit("QWEN_IMAGE_21_SNAPSHOT is not set; it must name the release directory.")
    directory = pathlib.Path(path)
    if not directory.is_dir():
        raise SystemExit(f"QWEN_IMAGE_21_SNAPSHOT names {directory}, which is not a directory.")
    return directory


def write_versions(out: pathlib.Path) -> None:
    """Records which versions of the reference stack wrote the fixtures beside it."""
    from importlib.metadata import version

    (out / "versions.json").write_text(
        json.dumps({name: version(name) for name in PACKAGES}, indent=2) + "\n"
    )
    print("versions: " + ", ".join(f"{name} {version(name)}" for name in PACKAGES))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=default_out())
    parser.add_argument("--only", nargs="*", default=None)
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)

    torch.manual_seed(0)
    dumpers = {
        "scheduler": dump_scheduler.dump,
        "tokenizer": dump_tokenizer.dump,
        "rope": dump_rope.dump,
        "transformer": dump_transformer.dump,
        "text_encoder": dump_text_encoder.dump,
        "vision": dump_vision.dump,
        "vae": dump_vae.dump,
        # Last, and the only one that loads the release whole: the pipeline end to end.
        "pipeline": dump_pipeline.dump,
    }
    for name, dumper in dumpers.items():
        if arguments.only and name not in arguments.only:
            continue
        torch.manual_seed(0)
        dumper(arguments.out)
    write_versions(arguments.out)


if __name__ == "__main__":
    main()
