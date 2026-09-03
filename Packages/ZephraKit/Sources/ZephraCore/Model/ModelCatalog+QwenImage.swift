import Foundation

/// The Qwen-Image family's entries. Its numbers are in `all` beside the Z-Image ones; they
/// live here so the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// Qwen-Image-2512 at four-bit precision, distilled to four steps, built on this Mac by
    /// `make quantize-qwen`.
    ///
    /// A twenty-billion-parameter dual-stream MMDiT against Z-Image Turbo's six billion, which
    /// buys prompt adherence and text rendering in a different class for a step about a third
    /// longer (8.2 s against 6.3 s at 1024 on the same machine). Nothing publishes it in a form Zephra can load: the release is 57.7
    /// GB of bfloat16, and the four-step Lightning distillation ships separately as an adapter,
    /// so the local build is where the two are put together.
    ///
    /// The distillation is why this is usable at all. The base model wants fifty steps and real
    /// classifier-free guidance — two forward passes per step — so it presents here the way
    /// Z-Image Turbo does: four steps, no guidance, no negative prompt.
    public static let qwenImage2512_4bit = ModelDescriptor(
        id: "qwen-image-2512-4bit",
        displayName: "Qwen-Image 2512",
        variantName: "4-bit",
        backend: .qwenImage,
        source: .localDirectory(localModelsDirectory.appending(path: "qwen-image-2512-4bit")),
        quantization: .int4,
        downloadBytes: 0,
        // Measured on an M4 Max, deterministic across repetitions: 21532 MB live after a
        // generation at any size, because the weights are the whole of it — 21.6 GB on disk.
        // Peak follows the image: 26053 MB at 512, 30364 MB at 1024, 32520 MB at 1328.
        residentBytes: 21_530_000_000,
        peakBytes: 30_360_000_000,
        // Measured, same machine and seed, tiled at a 64-cell latent tile: 26068 MB at 1024 and
        // 26088 MB at 1328. The tiled peak barely moves with the image because the tile, not the
        // image, sets the decode's transient — what is left is the transformer.
        tiledPeakBytes: 26_070_000_000,
        // diffusers' QwenImagePipeline keeps the first 512 hidden states of the prompt
        // (`max_sequence_length`, its default); the tokenizer would allow 1024, but nothing
        // past 512 ever reaches the transformer there, so nothing past 512 does here.
        maxPromptTokens: 512,
        capabilities: qwenImage2512Capabilities,
        // Measured: what `make quantize-qwen` writes, 16.2 GB of transformer and the rest.
        builtBytes: 21_600_000_000
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
        supportsSeed: true
    )
}
