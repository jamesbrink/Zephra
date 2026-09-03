"""How the klein pipeline lays out the image being made and the pictures it edits from.

The claim checked here is ordering: the target's tokens come first, each reference's after,
every reference on its own image index ten apart, and the schedule's shift counts the target
alone. Values name their coordinates so the token order can be read off in Swift.
"""

import pathlib

import torch
from safetensors.torch import save_file


def dump(out: pathlib.Path) -> None:
    from diffusers.pipelines.flux2.pipeline_flux2_klein import Flux2KleinPipeline, compute_empirical_mu

    def coordinate_valued(channels, height, width, offset):
        return (offset + torch.arange(channels * height * width, dtype=torch.float32)).reshape(
            1, channels, height, width)

    # Packed already: 8 channels stand in for 128, at a 3x4 target and two references of
    # different shapes.
    target = coordinate_valued(8, 3, 4, 0)
    references = [coordinate_valued(8, 2, 3, 1000), coordinate_valued(8, 4, 2, 2000)]

    target_tokens = Flux2KleinPipeline._pack_latents(target)
    target_ids = Flux2KleinPipeline._prepare_latent_ids(target)
    reference_tokens = torch.cat([Flux2KleinPipeline._pack_latents(r) for r in references], dim=1)
    reference_ids = Flux2KleinPipeline._prepare_image_ids(references)
    combined_tokens = torch.cat([target_tokens, reference_tokens], dim=1)
    combined_ids = torch.cat([target_ids, reference_ids], dim=1)

    tensors = {
        "target.packed": target.contiguous(),
        "reference0.packed": references[0].contiguous(),
        "reference1.packed": references[1].contiguous(),
        "combined.tokens": combined_tokens.contiguous(),
        "combined.ids": combined_ids.to(torch.int32).contiguous(),
        # Only the target's tokens set the shift, references or not.
        "mu": torch.tensor(compute_empirical_mu(target_tokens.shape[1], 4), dtype=torch.float32),
    }
    save_file(tensors, str(out / "reference_conditioning.safetensors"))
    print(f"reference conditioning: {len(tensors)} tensors")
