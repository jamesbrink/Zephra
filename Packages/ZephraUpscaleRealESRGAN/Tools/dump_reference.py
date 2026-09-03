# /// script
# requires-python = ">=3.11"
# dependencies = ["torch", "safetensors", "numpy"]
# ///
"""Dump reference tensors from the BSD-3-Clause SRVGGNetCompact architecture.

Every fixture this writes is a claim about what the reference does, checked in Swift by the
matching test. `SRVGGNetCompact` is defined inline in plain torch rather than imported from
`basicsr`/`realesrgan`: the class is twenty lines, it is copied here from
`realesrgan/archs/srvgg_arch.py` (Copyright (c) 2021, Xintao Wang), and depending on the package
would pull a heavy pinned tree for no gain.

The configuration is a doll's house -- eight features, two body convolutions -- because a
transposed axis, a per-tensor PReLU, or a wrong pixel-shuffle ordering shows up there exactly as
well as in the published network, and the fixture is small enough to commit. Eight features
rather than one is deliberate: eight distinct PReLU alphas is what makes a per-tensor broadcast
fail rather than pass.

Both `upscale=2` and `upscale=4` are dumped, so a hard-coded 4 in the Swift port is caught. The
input is `[1, 3, 6, 5]` -- odd and non-square, so a height-for-width swap fails too.

Run with `uv run Tools/dump_reference.py --out Tests/ZephraUpscaleRealESRGANTests/Fixtures`.
"""

import argparse
import pathlib

import torch
from safetensors.torch import save_file
from torch import nn as nn
from torch.nn import functional as F

SEED = 20_260_903


class SRVGGNetCompact(nn.Module):
    """A compact VGG-style network structure for super-resolution.

    Transcribed from `realesrgan/archs/srvgg_arch.py`, BSD-3-Clause, Copyright (c) 2021,
    Xintao Wang, with the registry decorator and the unused activation types dropped.
    """

    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=16, upscale=4):
        super().__init__()
        self.upscale = upscale

        self.body = nn.ModuleList()
        self.body.append(nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.append(nn.PReLU(num_parameters=num_feat))
        for _ in range(num_conv):
            self.body.append(nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.append(nn.PReLU(num_parameters=num_feat))
        self.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.upsampler = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = x
        for i in range(0, len(self.body)):
            out = self.body[i](out)
        out = self.upsampler(out)
        base = F.interpolate(x, scale_factor=self.upscale, mode="nearest")
        out += base
        return out


def dump_pixel_shuffle(out: pathlib.Path) -> None:
    """`nn.PixelShuffle(2)` on a tensor whose values are their own coordinates.

    An `arange` means every element names where it came from, so any of the plausible wrong
    orderings -- (r, r, C), (r, C, r), or the block axes ahead of the spatial ones -- permutes
    distinct integers and fails element-wise rather than statistically.
    """
    source = torch.arange(1 * 12 * 2 * 3, dtype=torch.float32).reshape(1, 12, 2, 3)
    shuffled = nn.PixelShuffle(2)(source)
    tensors = {"in.source": source.contiguous(), "out.shuffled": shuffled.contiguous()}
    save_file(tensors, str(out / "pixel_shuffle.safetensors"))
    print(f"pixel_shuffle: {tuple(source.shape)} -> {tuple(shuffled.shape)}")


def dump_network(out: pathlib.Path, upscale: int) -> None:
    """The doll's-house network's weights, its input, and what it produced."""
    torch.manual_seed(SEED)
    model = SRVGGNetCompact(num_feat=8, num_conv=2, upscale=upscale)
    with torch.no_grad():
        for parameter in model.parameters():
            parameter.copy_(torch.randn_like(parameter) * 0.2)
        image = torch.rand(1, 3, 6, 5)
        result = model(image)

    tensors = {f"net.{name}": value.contiguous() for name, value in model.state_dict().items()}
    tensors["net.in.image"] = image.contiguous()
    tensors["net.out.image"] = result.contiguous()
    name = f"srvgg_x{upscale}.safetensors"
    save_file(tensors, str(out / name))
    print(f"{name}: {len(tensors)} tensors, out {tuple(result.shape)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        type=pathlib.Path,
        default=pathlib.Path("Tests/ZephraUpscaleRealESRGANTests/Fixtures"),
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    dump_pixel_shuffle(args.out)
    dump_network(args.out, upscale=4)
    dump_network(args.out, upscale=2)


if __name__ == "__main__":
    main()
