import Foundation

/// The Qwen-Image 2.1 family's one entry. Its numbers are in `all` beside the others; they live
/// here so the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// Qwen-Image 2.1 at four-bit precision, built on this Mac from the bf16 release the first
    /// time it is loaded.
    ///
    /// The most capable picture model Zephra runs and the slowest: a 7-billion-parameter
    /// single-stream transformer of 32 blocks over a Qwen3-VL encoder, forty steps rather than klein's four, and the only entry that reads **several**
    /// pictures at once and reads their transparency rather than being handed them over white.
    /// Legible text in a picture is what it is known for.
    ///
    /// Nothing publishes it in a form this loader reads, and the release is 33 GB of bf16, so the
    /// download is packed here: `builtBytes` is that cost, on top of the download. The mirror
    /// carries the packed variant, which is the path most people take.
    ///
    /// The weights are **not** Apache-2.0: the Qwen RESEARCH LICENSE AGREEMENT is
    /// non-commercial, which is why the chooser's line says so and why the packer copies the
    /// release's `LICENSE` and writes the `NOTICE` clause 3.c asks for.
    public static let qwenImage21_4bit = ModelDescriptor(
        id: "qwen-image-2.1-4bit",
        displayName: "Qwen-Image 2.1",
        variantName: "4-bit",
        backend: .qwenImage21,
        source: .huggingFace(
            repoID: "Qwen/Qwen-Image-2.1",
            revision: "main",
            // Everything the packer reads and nothing else: the two components it packs
            // (`transformer`, `text_encoder`), the three directories it copies whole (`vae`,
            // `processor` — where 2.1 publishes its tokenizer — and `scheduler`), the
            // `model_index.json` that names them, and the `LICENSE` the weights travel under.
            // `README.md` and `assets/` are left out by omission, the way klein's samples are.
            filePatterns: [
                "model_index.json", "LICENSE", "scheduler/*", "processor/*", "text_encoder/*",
                "transformer/*", "vae/*",
            ]
        ),
        quantization: .int4,
        // As the repository lists it, with those patterns, measured off a complete `hf download`
        // on 2026-09-22: transformer 14,230,315,061, text encoder 17,534,409,013, autoencoder
        // 1,350,991,591, processor 15,884,996, scheduler 485, LICENSE 7,831 and the index —
        // 33,131,609,424 in all, carried rounded **up** as a transfer estimate is.
        downloadBytes: 33_140_000_000,
        // Measured on halcyon (M4 Max, 48 GB, 40.2 GB working set) on 2026-09-22 with
        // `make bench` at 1024 pixels, forty steps, one run, the machine otherwise idle but
        // shared for timing; the memory figures are stable across runs. 10,585 MB live after
        // a generation at any size: the packed weights plus the float32 autoencoder, which is
        // the whole of it. Held figures round down.
        residentBytes: 10_580_000_000,
        // Measured, same run: 20,069 MB untiled at 1024. The transient over the weights is the
        // float32 decode's: MLX runs the decoder's 3 x 3 convolutions as Winograd and the
        // 1024-pixel upsampler stage alone holds about 8 GB of scratch. The transformer's own
        // step adds 3.3 GB at the first step and 1.4 GB on a cached one. Peaks round up.
        // Re-measured on 2026-09-23 with preview frames on, now that a frame is the picture's
        // own decode rather than a pooled thumbnail: 20,082 MB, the frames adding 13 MB. Twelve-
        // step runs the same afternoon peaked at 21,787 MB with frames off and 21,801 MB with
        // them on, so the spread is the allocator's rather than the frames', and the entry
        // carries the highest reading.
        peakBytes: 21_810_000_000,
        // Measured, same machine and seed, under `ZEPHRA_VAE_TILE=64` (32 latent cells after
        // the mapper halves it): 14,073 MB, set by the transformer's first step rather than
        // the decode. Over a 16 GB Mac's 13.74 GB fallback budget and over bender's 12.71 GB
        // working set, so such a Mac streams this model rather than holding it. With preview
        // frames on, 2026-09-23: 14,086 MB, since a frame is decoded in the same tile.
        tiledPeakBytes: 14_090_000_000,
        // Measured, `--stream --stream-depth 2` under tile 64: 6,306 MB peak and 4.36 GB read
        // per step. The 32 transformer blocks and the 36 language-model layers stream; what
        // is left resident is the float32 autoencoder, the vision tower, the embeddings, the
        // norms and the modulation table, plus the decode's tile and the depth-2 window.
        // Unmoved with preview frames on, 2026-09-23: 6,306 MB.
        streamedPeakBytes: 6_310_000_000,
        // Measured, the live figure of that same streamed run: 2,752 MB between runs. The two
        // go together: `MemoryGuard` subtracts this from the streamed peak, and
        // `residentBytes` cannot stand in for it.
        streamedResidentBytes: 2_750_000_000,
        // Measured with `--reference` over a 1024-pixel picture against the same run without
        // one, tiled so the decode does not hide it: 16,459 against 14,073 MB, +2.39 GB over
        // the run and +2.57 GB at the first step, where the prefill holds the cache it is
        // filling beside the prefix tokens' own activations. The cache itself is the
        // arithmetic 4096 tokens x 32 layers x K and V x 4096 x 2 bytes = 2.15 GB. Carried as
        // the first step's figure, rounded up; `MemoryGuard` adds it per picture, twice under
        // guidance.
        referencePrefixBytes: 2_600_000_000,
        // The pipeline pads every prompt to 512 tokens and conditions on all of them.
        maxPromptTokens: 512,
        capabilities: qwenImage21Capabilities,
        // Measured: 11,564,552,844 bytes written by `make quantize-qwen21` on halcyon on
        // 2026-09-22 at four bits, group 64, in 43 seconds — 568 packed layers plus the
        // float32 autoencoder, the processor and the scheduler copied whole. Carried rounded
        // **up**, as a figure the free-space check is made against. The arithmetic estimate
        // this replaces said 9.95 GB, 16% under: the packer writes every scale and bias
        // float32, which the published four-bit repacks do not.
        builtBytes: 11_570_000_000,
        mirror: mirror
    )

    /// What Qwen-Image 2.1 accepts.
    ///
    /// Sizes are multiples of 32: a 2x2 patch over a 16-pixel autoencoder cell, twice Z-Image's
    /// grid. That is why the large preset is 1344 rather than the 1328 the brief asked for —
    /// 1328 is not a multiple of 32, and it was only ever legal on a family aligned to 16.
    ///
    /// Forty steps and a guidance range that *starts* at 1: this is not a distilled checkpoint,
    /// so unlike every other entry here both controls are real, and a negative prompt is read
    /// wherever guidance is over one. One is the default because the release's own card samples
    /// it that way, and it is the value at which the second forward — and its share of the
    /// prefix cache — is not paid.
    ///
    /// `referenceStrengthBounds: 1...1` is the degenerate range that says the slider is not
    /// offered, klein's case rather than Z-Image's: 2.1 conditions on the pictures directly and
    /// still walks the whole schedule from noise, so there is no partway point to enter at.
    /// `referenceImageCount` of `1...10` is the model card's own limit and
    /// `ReferenceLimits.maximumPictures`, which is what the PNG record and the link can carry.
    static let qwenImage21Capabilities = ModelCapabilities(
        sizeAlignment: 32,
        sizePresets: [
            ImageSize(width: 1024, height: 1024),
            // A quick size, a little over half the default's pixels, for a draft of a prompt.
            ImageSize(width: 768, height: 768),
            ImageSize(width: 1152, height: 896),
            ImageSize(width: 896, height: 1152),
            ImageSize(width: 1344, height: 768),
            ImageSize(width: 768, height: 1344),
            ImageSize(width: 1280, height: 1024),
            ImageSize(width: 1344, height: 1344),
            // The 2K set, every one of them well over one and a half times the default's
            // pixels, so `SizeTier` files them all under "Larger, slower" — which they are.
            ImageSize(width: 2048, height: 2048),
            ImageSize(width: 2400, height: 1792),
            ImageSize(width: 1792, height: 2400),
            ImageSize(width: 2528, height: 1696),
            ImageSize(width: 1696, height: 2528),
            ImageSize(width: 2752, height: 1536),
            ImageSize(width: 1536, height: 2752),
        ],
        sizeBounds: 512...2752,
        defaultSize: ImageSize(width: 1024, height: 1024),
        stepBounds: 8...50,
        defaultSteps: 40,
        guidanceBounds: 1...8,
        defaultGuidance: 1,
        supportsNegativePrompt: true,
        supportsSeed: true,
        supportsReferenceImage: true,
        referenceImageCount: 1...10,
        // The one family whose autoencoder takes four channels: a cut-out's alpha reaches the
        // condition latents as itself (the vision tower still reads it over white, as the
        // reference pipeline does), so `ReferenceMatteNote` says nothing about it.
        readsTransparentReferences: true,
        referenceStrengthBounds: 1...1,
        defaultReferenceStrength: 1
    )
}
