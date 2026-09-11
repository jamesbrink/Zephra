import Foundation

/// The Wan 2.2 family's entries. Its numbers are in `all` beside the others; they live here so
/// the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// The files the build reads from the FastWan Diffusers release: the transformer, the UMT5
    /// text encoder in three shards with its index, the autoencoder, the tokenizer, and the
    /// configs that name them. The scheduler's config and the README are fetched for what they
    /// say (the README carries the Apache-2.0 notice); the repository's sample pictures are not.
    static let wanPatterns = [
        "model_index.json", "README.md", "scheduler/*", "text_encoder/*", "tokenizer/*",
        "transformer/*", "vae/*",
    ]

    /// The release as the repository lists it: transformer 9,999,660,080, text encoder
    /// 11,361,851,208 in three shards, autoencoder 2,818,777,808, tokenizer 21,454,609, and
    /// the configs: 24,201,774,877 in all.
    static let wanDownloadBytes: Int64 = 24_202_000_000

    /// FastWan 2.2 TI2V-5B at four-bit precision, built on this Mac from the release the first
    /// time it is loaded.
    ///
    /// A 5-billion-parameter video DiT of 30 blocks, conditioned on the UMT5-XXL text encoder
    /// and decoded by Wan 2.2's 16x-spatial, 4x-temporal convolutional autoencoder, distilled
    /// by FastVideo with distribution matching to three steps at timesteps 1000, 757 and 522
    /// with no guidance. Frames come in fours plus one at 24 fps. A picture is held exactly as
    /// the clip's first frame, so there is no strength to offer. Apache-2.0 throughout.
    public static let wan22TI2V5B4bit = ModelDescriptor(
        id: "wan-2.2-ti2v-5b-4bit",
        displayName: "Wan 2.2",
        variantName: "5B, 4-bit",
        backend: .wan,
        source: .huggingFace(
            repoID: "FastVideo/FastWan2.2-TI2V-5B-FullAttn-Diffusers",
            revision: "main",
            filePatterns: wanPatterns
        ),
        quantization: .int4,
        downloadBytes: wanDownloadBytes,
        // Measured on an M4 Max, three steps, 832 x 480 and 49 frames, the autoencoder in
        // bfloat16 and the decoder convolving one frame at a time: 7996 MB live after a
        // generation and 15079 MB peak, the peak the decode's, not the load's (8.8 GB) and
        // not the transformer's (11.2 GB); 31.8 s a clip at 5.41 s a step, of which the decode
        // is about 15 s. Holding a first frame: 37.1 s and the same peak.
        residentBytes: 8_000_000_000,
        peakBytes: 15_080_000_000,
        // Measured the same way with the engine's 64-cell tile, 32 of this autoencoder's
        // cells, three tiles across the frame: 12374 MB peak and 49.8 s a clip, the overlap
        // paid in decode time.
        tiledPeakBytes: 12_380_000_000,
        // Measured the same way with both stacks streamed: 9708 MB peak, 2625 MB live, 36.0 s
        // a clip at 6.09 s a step on an M4 Max, whose SSD keeps up.
        streamedPeakBytes: 9_710_000_000,
        // UMT5 is padded to 512 tokens and the transformer attends to every position.
        maxPromptTokens: 512,
        capabilities: wanCapabilities,
        // Measured: 10,090,839,207 bytes written by `make quantize-wan` in 36 s — 3.18 GB of
        // transformer (blocks at four bits, the conditioning at eight, tables and head whole),
        // 4.09 GB of text encoder (blocks at four bits, the 256384-row token table at eight),
        // the 2.83 GB autoencoder copied as it is in float32, and the tokenizer.
        builtBytes: 10_100_000_000,
        mirror: mirror
    )

    /// What the distilled Wan 2.2 accepts.
    ///
    /// Steps and guidance are the distillation's: three timesteps fixed by the checkpoint and
    /// no classifier-free guidance, so neither is a choice, and a negative prompt has nothing
    /// to act on. Sizes are aligned to 32: the autoencoder's 16 times the transformer's patch
    /// of 2. The model was trained at 1280 x 704 and 121 frames and runs any size; 832 x 480
    /// is the default because a step's time grows with the token count and that frame is
    /// two fifths of the trained one's pixels. Frames run on the autoencoder's ladder of four
    /// plus one: 5 to 121 at 24 fps, 49 (two seconds) to start.
    static let wanCapabilities = ModelCapabilities(
        sizeAlignment: 32,
        sizePresets: [
            ImageSize(width: 832, height: 480),
            ImageSize(width: 480, height: 832),
            ImageSize(width: 640, height: 352),
            ImageSize(width: 352, height: 640),
            ImageSize(width: 1024, height: 576),
            ImageSize(width: 1280, height: 704),
            ImageSize(width: 704, height: 1280),
        ],
        sizeBounds: 256...1280,
        defaultSize: ImageSize(width: 832, height: 480),
        stepBounds: 3...3,
        defaultSteps: 3,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        supportsReferenceImage: true,
        // A picture is the first frame and stays it: there is no strength on this model, and
        // the single value at 1 hides the slider, as it does for klein.
        referenceStrengthBounds: 1...1,
        defaultReferenceStrength: 1,
        frameBounds: 5...121,
        defaultFrames: 49,
        frameAlignment: 4,
        frameRate: 24,
        // A clip is carried on from its last frame alone, held exactly as a first frame is:
        // the base model was trained to hold one frame, and holding a run of them is the
        // untrained case ROADMAP.md leaves out.
        continuationFrames: 1...1,
        defaultContinuationFrames: 1
    )
}
