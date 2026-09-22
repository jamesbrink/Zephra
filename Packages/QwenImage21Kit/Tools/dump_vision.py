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
# ]
# ///
"""Qwen3-VL's vision tower at doll's-house size, DeepStack taps included, and the tower's
preprocessing pinned at the published numbers.

What this pins that nothing else would catch. The patch embedding is a Conv3d over a temporal
patch of **two**, which a still picture is repeated to fill, so a patch vector is
`3 * 2 * 16 * 16`; the learned position table is **interpolated** onto this picture's patch grid
rather than sliced, `align_corners=True` and bilinear, and emitted in the same block-major order
as the patches; the tower's own rotary is axial 2-D whose **theta is in no shipped config** —
transformers supplies 10,000 through `rope_parameters`, and `vision.invFreq` here is that
number's only written-down form, since the buffer is non-persistent and so is in none of the
750 published tensors; and the **DeepStack taps**, the outputs of the blocks
`deepstack_visual_indexes` names, are added into the decoder's own stream at layers 0, 1 and 2
and are invisible in the tower's final output — a port that dropped them would produce a
plausible picture of the wrong reference.

`uv run Tools/dump_vision.py`. No snapshot is read: every number here is decided by a
configuration, and the published ones are written into the `REAL_*` constants below from
`text_encoder/config.json` and `processor/preprocessor_config.json`.
"""

import argparse
import pathlib

import numpy as np
import torch
from safetensors.torch import save_file

# Doll's house: the real ratios at a size that commits. Four blocks with three DeepStack taps,
# because the decoder adds one per layer into its first three and the fourth decoder layer is
# what says the injection stopped.
VISION_CONFIG = {
    "depth": 4,
    "hidden_size": 32,
    "num_heads": 2,
    "intermediate_size": 64,
    "in_channels": 3,
    "patch_size": 4,
    "temporal_patch_size": 2,
    "spatial_merge_size": 2,
    "num_position_embeddings": 64,
    "out_hidden_size": 32,
    "deepstack_visual_indexes": [1, 2, 3],
    "hidden_act": "gelu_pytorch_tanh",
}

TEXT_CONFIG = {
    "hidden_size": 32,
    "intermediate_size": 96,
    "num_hidden_layers": 4,
    "num_attention_heads": 4,
    "num_key_value_heads": 1,
    "head_dim": 8,
    "rms_norm_eps": 1e-6,
    "rope_theta": 5_000_000,
    "rope_scaling": {"mrope_interleaved": True, "mrope_section": [2, 1, 1], "rope_type": "default"},
    "vocab_size": 64,
    "hidden_act": "silu",
    "attention_bias": False,
}

# The published vision shape, for the rotary frequencies and the interpolation alone.
REAL_VISION_CONFIG = dict(
    VISION_CONFIG,
    depth=27,
    hidden_size=1152,
    num_heads=16,
    intermediate_size=4304,
    patch_size=16,
    num_position_embeddings=2304,
    out_hidden_size=4096,
    deepstack_visual_indexes=[8, 16, 24],
)

# Patch grid: one temporal patch, four rows, four columns, which merges to four image slots.
GRID = (1, 4, 4)

# The ids the doll's-house decoder reads with one picture in them: two text tokens, the picture's
# four slots, two more text tokens. 60 stands in for `<|image_pad|>` inside a 64-token vocabulary.
IMAGE_TOKEN_ID = 60
IDS = [1, 2, IMAGE_TOKEN_ID, IMAGE_TOKEN_ID, IMAGE_TOKEN_ID, IMAGE_TOKEN_ID, 3, 4]
TOKEN_TYPES = [0, 0, 1, 1, 1, 1, 0, 0]

# The published processor's own pixel bounds, for `smart_resize`: factor is patch * merge = 32,
# and the two bounds are 256 squared and 4096 squared.
REAL_FACTOR = 32
REAL_MIN_PIXELS = 65536
REAL_MAX_PIXELS = 16777216

# Shapes `smart_resize` is asked about: two that are already fitted and so pass through, one far
# too small, one far too large, one that rounds, and one that ties on the round-half-to-even the
# reference's `round` performs.
RESIZE_CASES = [(1024, 1024), (1344, 768), (64, 64), (8000, 6000), (1000, 700), (1040, 1040)]

# The picture the patchify is pinned over: a multiple of the factor and past the smallest bound
# once the bounds are relaxed, so `smart_resize` is the no-op the pipeline's own fit makes it.
PATCH_IMAGE = (64, 96)  # height, width


def tower_dump(out_tensors: dict) -> None:
    """The doll's-house tower over one picture, with every DeepStack tap."""
    from transformers.models.qwen3_vl.configuration_qwen3_vl import Qwen3VLVisionConfig
    from transformers.models.qwen3_vl.modeling_qwen3_vl import Qwen3VLVisionModel

    config = Qwen3VLVisionConfig(**VISION_CONFIG)
    model = Qwen3VLVisionModel(config).eval()
    patch = config.in_channels * config.temporal_patch_size * config.patch_size**2
    pixels = torch.randn(GRID[0] * GRID[1] * GRID[2], patch)
    grid = torch.tensor([list(GRID)])

    with torch.no_grad():
        output = model(pixels, grid_thw=grid, return_dict=True)

    for name, value in model.state_dict().items():
        out_tensors[f"visual.{name}"] = value.float().contiguous()
    out_tensors["tower.in.pixels"] = pixels.contiguous()
    out_tensors["tower.in.grid"] = grid.to(torch.int32).contiguous()
    out_tensors["tower.out.slots"] = output.pooler_output.float().clone().contiguous()
    out_tensors["tower.out.patches"] = output.last_hidden_state.float().clone().contiguous()
    for index, tap in enumerate(output.deepstack_features):
        out_tensors[f"tower.out.deepstack{index}"] = tap.float().clone().contiguous()


def rotary_and_interpolation(out_tensors: dict) -> None:
    """The tower's inverse frequencies and its position-table resampling, doll and published."""
    from transformers.models.qwen3_vl.configuration_qwen3_vl import Qwen3VLVisionConfig
    from transformers.models.qwen3_vl.modeling_qwen3_vl import Qwen3VLVisionRotaryEmbedding
    from transformers.vision_utils import (
        get_vision_interpolation_indices_and_weights,
        get_vision_position_ids,
    )

    for label, settings, grids in [
        ("doll", VISION_CONFIG, [GRID]),
        ("real", REAL_VISION_CONFIG, [(1, 6, 8), (1, 32, 32)]),
    ]:
        config = Qwen3VLVisionConfig(**settings)
        inv_freq, scaling = Qwen3VLVisionRotaryEmbedding.compute_axial_rope_parameters(config)
        out_tensors[f"rope.{label}.invFreq"] = inv_freq.float().contiguous()
        out_tensors[f"rope.{label}.theta"] = torch.tensor(
            float(config.rope_parameters["rope_theta"]), dtype=torch.float32)
        assert scaling == 1.0, scaling

        side = int(config.num_position_embeddings**0.5)
        for grid in grids:
            key = f"{label}.{grid[1]}x{grid[2]}"
            grid_thw = torch.tensor([list(grid)])
            positions = get_vision_position_ids(grid_thw, config.spatial_merge_size)
            out_tensors[f"vision.positions.{key}"] = positions.to(torch.int32).contiguous()

            rotary = Qwen3VLVisionRotaryEmbedding(config)
            cos, sin = rotary(torch.zeros(1, dtype=torch.float32), positions)
            out_tensors[f"vision.rope.{key}.cos"] = cos.float().contiguous()
            out_tensors[f"vision.rope.{key}.sin"] = sin.float().contiguous()

            indices, weights = get_vision_interpolation_indices_and_weights(
                grid_thw, num_grid_per_side=side, mode="bilinear", align_corners=True,
                spatial_merge_size=config.spatial_merge_size)
            out_tensors[f"vision.interp.{key}.indices"] = indices.to(torch.int32).contiguous()
            out_tensors[f"vision.interp.{key}.weights"] = weights.float().contiguous()


def preprocessing_dump(out_tensors: dict) -> None:
    """`smart_resize` at the published bounds, the block-major patchify, and the white flatten."""
    from PIL import Image
    # The PIL-backed processor rather than the torchvision-backed one: the two are the same
    # arithmetic, and this one needs no torchvision in the dumper's environment.
    from transformers.models.qwen2_vl.image_processing_pil_qwen2_vl import (
        Qwen2VLImageProcessorPil,
        smart_resize,
    )

    resized = [
        list(smart_resize(h, w, factor=REAL_FACTOR, min_pixels=REAL_MIN_PIXELS, max_pixels=REAL_MAX_PIXELS))
        for h, w in RESIZE_CASES
    ]
    out_tensors["resize.in"] = torch.tensor(RESIZE_CASES, dtype=torch.int32).contiguous()
    out_tensors["resize.out"] = torch.tensor(resized, dtype=torch.int32).contiguous()

    # The patchify at the doll's patch size, with the pixel bounds relaxed so `smart_resize`
    # passes the picture through: the layout is what is pinned here, and it does not depend on
    # the size. The published bounds are pinned by `resize.*` above.
    height, width = PATCH_IMAGE
    rng = np.random.default_rng(0)
    image = rng.integers(0, 256, size=(height, width, 3), dtype=np.uint8)
    processor = Qwen2VLImageProcessorPil(
        patch_size=VISION_CONFIG["patch_size"],
        merge_size=VISION_CONFIG["spatial_merge_size"],
        temporal_patch_size=VISION_CONFIG["temporal_patch_size"],
        image_mean=[0.5, 0.5, 0.5],
        image_std=[0.5, 0.5, 0.5],
        min_pixels=16,
        max_pixels=1 << 24,
    )
    processed = processor(images=Image.fromarray(image), return_tensors="pt")
    out_tensors["patchify.in.image"] = torch.from_numpy(image.astype(np.float32)).contiguous()
    out_tensors["patchify.out.patches"] = processed["pixel_values"].float().contiguous()
    out_tensors["patchify.out.grid"] = processed["image_grid_thw"].to(torch.int32).contiguous()

    # RGBA over white, the way `_get_qwen_prompt_embeds` flattens the tower's copy: PIL pastes
    # with the alpha channel as the mask, which is integer arithmetic and not a float lerp.
    rgba = rng.integers(0, 256, size=(8, 8, 4), dtype=np.uint8)
    picture = Image.fromarray(rgba, mode="RGBA")
    white = Image.new("RGB", picture.size, (255, 255, 255))
    white.paste(picture, mask=picture.getchannel("A"))
    out_tensors["white.in.rgba"] = torch.from_numpy(rgba.astype(np.float32)).contiguous()
    out_tensors["white.out.rgb"] = torch.from_numpy(
        np.asarray(white).astype(np.float32)).contiguous()


def decoder_with_image_dump(out_tensors: dict) -> None:
    """The doll's-house decoder reading one picture: positions, DeepStack, the pre-norm state."""
    from transformers.models.qwen3_vl.configuration_qwen3_vl import Qwen3VLConfig
    from transformers.models.qwen3_vl.modeling_qwen3_vl import Qwen3VLModel

    config = Qwen3VLConfig(
        text_config=dict(TEXT_CONFIG, model_type="qwen3_vl_text"),
        vision_config=dict(VISION_CONFIG, model_type="qwen3_vl"),
        image_token_id=IMAGE_TOKEN_ID,
        video_token_id=IMAGE_TOKEN_ID - 1,
        vision_start_token_id=IMAGE_TOKEN_ID - 2,
        vision_end_token_id=IMAGE_TOKEN_ID - 3,
        tie_word_embeddings=False,
    )
    model = Qwen3VLModel(config).eval()
    patch = VISION_CONFIG["in_channels"] * VISION_CONFIG["temporal_patch_size"] * VISION_CONFIG["patch_size"] ** 2
    pixels = torch.randn(GRID[0] * GRID[1] * GRID[2], patch)
    grid = torch.tensor([list(GRID)])
    ids = torch.tensor([IDS])
    types = torch.tensor([TOKEN_TYPES], dtype=torch.int32)

    handle = model.language_model.norm.register_forward_hook(lambda module, args, output: args[0])
    try:
        with torch.no_grad():
            output = model(
                input_ids=ids, pixel_values=pixels, image_grid_thw=grid, mm_token_type_ids=types)
    finally:
        handle.remove()

    positions, _ = model.get_rope_index(ids, types, image_grid_thw=grid)
    for name, value in model.state_dict().items():
        out_tensors[f"joint.{name}"] = value.float().contiguous()
    out_tensors["joint.in.ids"] = ids.to(torch.int32).contiguous()
    out_tensors["joint.in.types"] = types.contiguous()
    out_tensors["joint.in.pixels"] = pixels.contiguous()
    out_tensors["joint.in.grid"] = grid.to(torch.int32).contiguous()
    out_tensors["joint.out.positions"] = positions.to(torch.int32).contiguous()
    out_tensors["joint.out.hidden"] = output.last_hidden_state.float().clone().contiguous()


def dump(out: pathlib.Path) -> None:
    tensors: dict = {}
    torch.manual_seed(0)
    tower_dump(tensors)
    rotary_and_interpolation(tensors)
    preprocessing_dump(tensors)
    torch.manual_seed(1)
    decoder_with_image_dump(tensors)
    save_file(tensors, str(out / "vision.safetensors"))
    print(f"vision: {len(tensors)} tensors")


def main() -> None:
    import dump_reference

    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path, default=dump_reference.default_out())
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(0)
    dump(arguments.out)


if __name__ == "__main__":
    import sys

    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    main()
