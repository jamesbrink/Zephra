import Foundation

/// The Qwen-Image family's entries. Its numbers are in `all` beside the Z-Image ones; they
/// live here so the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// The four-step Lightning distillation, downloaded beside the release and merged into the
    /// transformer as it is packed.
    ///
    /// One file, named exactly. The repository also ships whole merged checkpoints of twenty
    /// gigabytes each, so taking it by pattern would cost a hundred gigabytes to get 1.7.
    static let qwenImage2512Lightning = ModelAdapter(
        repoID: "lightx2v/Qwen-Image-2512-Lightning",
        revision: "main",
        file: "Qwen-Image-2512-Lightning-4steps-V1.0-fp32.safetensors",
        // As the repository lists it.
        bytes: 1_698_951_104
    )

    /// Qwen-Image-2512 at four-bit precision, distilled to four steps, built on this Mac from
    /// the bf16 release and the adapter the first time it is loaded.
    ///
    /// A twenty-billion-parameter dual-stream MMDiT against Z-Image Turbo's six billion, which
    /// buys prompt adherence and text rendering in a different class for a step about a third
    /// longer (8.2 s against 6.3 s at 1024 on the same machine). Nothing publishes it in a form
    /// Zephra can load: the release is 57.7 GB of bfloat16, and the four-step Lightning
    /// distillation ships separately as an adapter, so the local build is where the two are put
    /// together. `make quantize-qwen` is the same build by hand.
    ///
    /// The distillation is why this is usable at all. The base model wants fifty steps and real
    /// classifier-free guidance — two forward passes per step — so it presents here the way
    /// Z-Image Turbo does: four steps, no guidance, no negative prompt.
    public static let qwenImage2512_4bit = ModelDescriptor(
        id: "qwen-image-2512-4bit",
        displayName: "Qwen-Image 2512",
        variantName: "4-bit",
        backend: .qwenImage,
        source: .huggingFace(
            repoID: "Qwen/Qwen-Image-2512",
            revision: "main",
            // The whole release but its README and `.gitattributes`: the two components the
            // packer packs and the three it copies across whole.
            filePatterns: [
                "model_index.json", "scheduler/*", "text_encoder/*", "tokenizer/*",
                "transformer/*", "vae/*",
            ]
        ),
        quantization: .int4,
        // As the repository lists it, with those patterns: transformer 40,861,027,880, text
        // encoder 16,584,414,544, autoencoder 253,806,966, tokenizer 5,063,591, and the configs
        // — 57,704,574,910 in all. The adapter's 1.7 GB is counted by `transferBytes` beside it.
        downloadBytes: 57_700_000_000,
        // Measured on an M4 Max, deterministic across repetitions: 21532 MB live after a
        // generation at any size, because the weights are the whole of it — 21.6 GB on disk.
        // Peak follows the image: 26053 MB at 512, 30364 MB at 1024, 32520 MB at 1328.
        //
        // Taken before the autoencoder's encoder was ported, which adds 107 MB of always-loaded
        // weights — inside this figure's own rounding, so it is left as measured rather than
        // adjusted by arithmetic. Due a rerun on an idle machine either way: every figure in
        // this entry, the streamed ones below included, was measured while the stream ran in
        // float32 by accident (float32 noise, uncast float32 scales, raw nodes on every
        // streamed pass); it runs in bfloat16 since the 2026-09-05 audit.
        residentBytes: 21_530_000_000,
        peakBytes: 30_360_000_000,
        // Measured, same machine and seed, tiled at a 64-cell latent tile: 26068 MB at 1024 and
        // 26088 MB at 1328. The tiled peak barely moves with the image because the tile, not the
        // image, sets the decode's transient — what is left is the transformer.
        tiledPeakBytes: 26_070_000_000,
        // Measured with the weights streamed (`make bench ARGS="--stream"`), same seed, tiled
        // at 64, on an M4 Max: 10243 MB peak at 1024 against 30473 MB resident in the same
        // session, 1409 MB live between runs, 16.15 GB read per step, and the image byte for
        // byte the resident one. The peak is the text encoder's pass, the transformer's
        // three-block window with its activations, and the decode's tile, none of which
        // depends on the machine. On the 16 GB M4 mini this is for (12.7 GB working set):
        // 7954 MB peak and 29.7 s a step at 1024, 5447 MB and 7.1 s a step at 512, the
        // latter read-bound at 2.3 GB/s from its SSD; swap did not move. The larger figure
        // is kept, since the peak is what the budget is checked against.
        streamedPeakBytes: 10_250_000_000,
        // diffusers' QwenImagePipeline keeps the first 512 hidden states of the prompt
        // (`max_sequence_length`, its default); the tokenizer would allow 1024, but nothing
        // past 512 ever reaches the transformer there, so nothing past 512 does here.
        maxPromptTokens: 512,
        capabilities: qwenImage2512Capabilities,
        // Measured: what `make quantize-qwen` writes, 16.2 GB of transformer and the rest.
        builtBytes: 21_600_000_000,
        adapters: [qwenImage2512Lightning],
        mirror: mirror
    )

    /// What the distilled Qwen-Image variant accepts.
    ///
    /// The step and guidance bounds are the distillation's, not the architecture's: four steps
    /// and no guidance is what the Lightning adapter merged into these weights was trained to
    /// produce. A future entry built from the undistilled release would be the opposite —
    /// fifty steps, guidance 1 to 10, negative prompts live — which is what `ModelCapabilities`
    /// being per-descriptor is for.
    ///
    /// Sizes are the model's own aspect ratios, aligned to 16: a 2x2 patch over an 8x
    /// autoencoder. 1024 is the default rather than the native 1328 because it is half the
    /// seconds for an image that still renders legible text; 1328 is one preset away.
    static let qwenImage2512Capabilities = ModelCapabilities(
        sizeAlignment: 16,
        sizePresets: [
            ImageSize(width: 1024, height: 1024),
            // A quick size, a little over half the default's pixels, for a draft of a prompt.
            ImageSize(width: 768, height: 768),
            ImageSize(width: 1328, height: 1328),
            ImageSize(width: 1664, height: 928),
            ImageSize(width: 928, height: 1664),
            ImageSize(width: 1472, height: 1136),
            ImageSize(width: 1136, height: 1472),
        ],
        sizeBounds: 512...1664,
        defaultSize: ImageSize(width: 1024, height: 1024),
        // Chosen, not measured: Lightning ships four- and eight-step adapters, and twelve
        // leaves room to try more without offering the fifty the undistilled model wants.
        stepBounds: 1...12,
        defaultSteps: 4,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        // As for Z-Image: SDEdit wants an image encoder and a linear schedule, and the
        // quantizer copies the autoencoder's encoder into the local build verbatim, so the
        // weights are already on disk. Not to be confused with Qwen-Image-Edit, which
        // conditions the transformer on a picture and is a different model, not a setting.
        supportsReferenceImage: true,
        referenceStrengthBounds: 0.1...0.9,
        defaultReferenceStrength: 0.6
    )
}
