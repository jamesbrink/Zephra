import Foundation

/// The Qwen-Image 2.1 family's one entry. Its numbers are in `all` beside the others; they live
/// here so the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// Qwen-Image 2.1 at four-bit precision, built on this Mac from the bf16 release the first
    /// time it is loaded.
    ///
    /// The most capable model Zephra runs and the slowest: a 20-billion-parameter MMDiT over
    /// Qwen3-VL, forty steps rather than klein's four, and the only entry that reads **several**
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
        // ESTIMATE, 2026-09-22, to be measured with `make bench` at 1024 pixels, forty steps,
        // three runs on an idle Mac; `BENCHMARKS.md` carries it under "Owed reruns" until then.
        // Arithmetic rather than a reading: the packed weights (about 9.95 GB, see `builtBytes`)
        // plus the float32 autoencoder's own working set and the tokenizer, which is what every
        // other family's live figure comes out as.
        residentBytes: 10_300_000_000,
        // ESTIMATE, 2026-09-22, to be measured with `make bench`. The resident figure plus an
        // untiled decode's transient at 1024, taken from the ratio the two measured 16-channel
        // families show between their untiled and tiled decodes.
        peakBytes: 17_300_000_000,
        // ESTIMATE, 2026-09-22, to be measured with `make bench` under `ZEPHRA_VAE_TILE=64`.
        //
        // Rounded **up** deliberately, and the one figure here where the rounding is a decision
        // rather than a habit: 13.9 GB is over a 16 GB Mac's 13.74 GB fallback budget and over
        // bender's measured 12.71 GB working set, so such a Mac streams this model rather than
        // holding it. An estimate carrying a gigabyte of uncertainty must not be the thing that
        // puts 10.3 GB of weights resident on the smallest Mac in the table; if the measurement
        // comes in under the budget, that is a change to make deliberately with a reading in
        // hand, the way `zImageTurbo4bit`'s 12.15 GB was.
        tiledPeakBytes: 13_900_000_000,
        // ESTIMATE, 2026-09-22, to be measured with `make bench --stream --stream-depth 2`.
        // Both 60-block stacks stream, so what is left is the float32 autoencoder, the
        // embeddings, the norms and the modulation table, plus the decode's tile and the
        // depth-2 window.
        streamedPeakBytes: 7_500_000_000,
        // ESTIMATE, 2026-09-22, the live figure of that same streamed run, to be measured
        // beside the peak. The two go together: `MemoryGuard` subtracts this from the streamed
        // peak, and `residentBytes` cannot stand in for it.
        streamedResidentBytes: 2_600_000_000,
        // ESTIMATE, 2026-09-22, to be measured with `make bench --reference IMAGE` against the
        // same run without one. One 1024-pixel reference is 4096 prefix tokens held across
        // every layer's key and value cache, plus the latents themselves; near enough constant
        // across target sizes, because a reference is fitted to the same megapixel budget
        // whatever is being made. `MemoryGuard` adds it per picture, twice under guidance.
        referencePrefixBytes: 2_200_000_000,
        // The pipeline pads every prompt to 512 tokens and conditions on all of them.
        maxPromptTokens: 512,
        capabilities: qwenImage21Capabilities,
        // ESTIMATE, 2026-09-22, to be replaced with the size `make quantize-qwen21` writes.
        // Arithmetic from the release: transformer 4.00 GB at four bits (which
        // `mlx-community/Qwen-Image-2.1-MLX-4bit` publishes as 4,002,275,328 bytes exactly),
        // the text encoder 4.26 GB, its vision tower 0.33 GB, the autoencoder's 1.35 GB copied
        // whole, and the processor.
        builtBytes: 9_950_000_000,
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
        // The one family whose vision tower takes four channels, so a cut-out arrives as a
        // cut-out rather than over white and `ReferenceMatteNote` says nothing about it.
        readsTransparentReferences: true,
        referenceStrengthBounds: 1...1,
        defaultReferenceStrength: 1
    )
}
