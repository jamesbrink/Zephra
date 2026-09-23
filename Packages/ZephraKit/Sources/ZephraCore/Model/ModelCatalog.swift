import Foundation

/// The models Zephra ships knowledge of, hand-written because each one needs verified numbers.
public enum ModelCatalog {
    /// Where models are kept when the user has not chosen a folder: the root of
    /// `ModelLocations.default`. Everywhere that can be given a folder takes a `ModelLocations`
    /// instead; this is only for a tool with no preferences to read, such as `ZephraQuantize`
    /// deciding where its output goes.
    public static var localModelsDirectory: URL { ModelLocations.default.root }

    /// Z-Image Turbo at eight-bit precision: the downloadable variant. Its untiled peak needs
    /// a 32 GB Mac; between 24 and 32 GB `fitting` offers it only because the decode can tile.
    public static let zImageTurbo8bit = ModelDescriptor(
        id: "z-image-turbo-8bit",
        displayName: "Z-Image Turbo",
        variantName: "8-bit",
        backend: .zImage,
        source: .huggingFace(
            repoID: "mzbac/Z-Image-Turbo-8bit",
            revision: "main",
            filePatterns: ["*.safetensors", "*.json", "tokenizer/*"]
        ),
        quantization: .int8,
        downloadBytes: 13_280_000_000,
        // Measured on halcyon (M4 Max) on 2026-09-13, tile 64, 1024 pixels, nine steps, three
        // runs, the machine 83-90% idle — the same session as the streamed figures below:
        // 12431 MB live between runs, carried rounded **down** as a held figure is. The
        // untiled peak is the earlier M4 Max reading, deterministic across repetitions:
        // 23501 MB during a 1024-pixel generation, which is the VAE decode and not weight
        // loading, which is lazy and never exceeds 7.2 GB; see VENDORED.md.
        residentBytes: 12_430_000_000,
        peakBytes: 23_500_000_000,
        // Measured in that same halcyon session at a 64-cell latent tile: 17867 MB, carried
        // rounded **up** as a peak is, so the decode's transient is 5436 MB on top of the
        // weights rather than the untiled 11070 MB. The entry said 17680 MB before, from the
        // first M4 Max run, 1.1% under this one.
        tiledPeakBytes: 17_870_000_000,
        // Measured on halcyon (M4 Max, 38338 MB working set) on 2026-09-13, tile 64, read-ahead
        // depth 2, 1024 pixels, nine steps, three runs, halcyon at 87% idle (a working
        // desktop; see BENCHMARKS.md): 6410 MB peak, carried rounded up, and
        // 974 MB live between runs, and the image byte for byte the resident run's. The peak
        // was the same to the byte with previews on.
        //
        // The 4-bit entry shares this figure because the two builds measured the same peak to
        // the byte: what the stream leaves resident is the same tensors in either build — the
        // float32 autoencoder, the embeddings and the norms — and the peak is that plus the
        // decode's tile and the depth-2 window of streamed blocks, none of which depends on
        // the width the blocks pack at. The width is paid in time instead: the last stream's
        // pass (the 30-block `layers` stack) reads 6.79 GB a step here against 3.40 GB at four
        // bits. Streaming is not slower here: 7.51 s a step streamed against 8.03 resident, the
        // M4 Max's SSD keeping up while the resident run holds 12.4 GB live. On the 16 GB M4
        // mini (12124 MB working set) the 4-bit build measured 5196 MB peak streamed; the
        // 8-bit build was not run there.
        streamedPeakBytes: 6_420_000_000,
        // The live figure of that same run: 974 MB between runs, carried rounded **down** to 970 MB,
        // against the 12431 MB this model holds resident. Shared with the 4-bit entry,
        // measured, as the peak is.
        streamedResidentBytes: 970_000_000,
        maxPromptTokens: 512,
        capabilities: zImageTurboCapabilities
    )

    /// Z-Image Turbo at four-bit precision, built on this Mac from the bf16 release the first
    /// time it is loaded.
    ///
    /// No published repository carries four-bit Z-Image weights in the manifest format the
    /// vendored loader reads, so what is downloaded is not what is loaded: the release is
    /// `Tongyi-MAI/Z-Image-Turbo`, 32.9 GB of bfloat16, and the packer writes the variant
    /// beside it. `make quantize` is the same build by hand.
    ///
    /// This is the variant a 16 GB Mac wants, which is the whole reason it downloads rather
    /// than waiting to be built from the command line.
    public static let zImageTurbo4bit = ModelDescriptor(
        id: "z-image-turbo-4bit",
        displayName: "Z-Image Turbo",
        variantName: "4-bit",
        backend: .zImage,
        source: .huggingFace(
            repoID: "Tongyi-MAI/Z-Image-Turbo",
            revision: "main",
            // `assets/` is 51 MB of sample pictures and a gallery PDF, left out by omission the
            // way `make quantize` leaves it out by `--exclude`. The rest of the repository is
            // what the packer reads: the two components it packs, and the three it copies whole.
            filePatterns: ["*.safetensors", "*.json", "tokenizer/*"]
        ),
        quantization: .int4,
        // As the repository lists it, with those patterns: transformer 24,619,690,888,
        // text encoder 8,044,982,000, autoencoder 167,666,902, tokenizer 15,881,072, and the
        // configs — 32,848,305,533 in all.
        downloadBytes: 32_850_000_000,
        // Measured on halcyon (M4 Max) on 2026-09-13, tile 64, 1024 pixels, nine steps, three
        // runs, 83-90% idle — the same session as the 8-bit entry's and as the streamed
        // figures below: 6707 MB live between runs, carried rounded **down**. The peak that
        // follows the image size is the earlier M4 Max reading, deterministic across
        // repetitions: 10693 MB at 512 pixels, 14599 MB at 768, 17839 MB at 1024 — resident
        // plus the VAE decode's scratch, which is unquantized and so costs the same here as
        // it does at eight bits.
        residentBytes: 6_700_000_000,
        peakBytes: 17_840_000_000,
        // Measured in that same halcyon session, where this figure used to be derived:
        // 12143 MB at a 64-cell latent tile, carried rounded **up**. The derivation it
        // replaces said 12010 MB — 6575 MB resident plus the 8-bit variant's tile transient.
        //
        // This is the number a 16 GB Mac's verdict turns on, and it clears it: bender's M4
        // mini reports a 12,713,115,648-byte working set, which is the 12124 MiB the machine
        // table spells "12124 MB", so 12.15 GB leaves about 560 MB and the variant is still
        // tiled there rather than streamed. The reading that called 12143 MB "19 MB over"
        // compared the bench's decimal MB against mebibytes.
        tiledPeakBytes: 12_150_000_000,
        // Measured on halcyon the same way as the 8-bit entry's, 2026-09-13, tile 64, depth 2,
        // 1024, nine steps, three runs: 6410 MB peak and 974 MB live, the same figures to the
        // byte, for the reason written out there — the stream leaves the same resident tensors
        // behind whichever width the blocks pack at, and the peak is those plus the decode's
        // tile and the depth-2 window. The width shows in the reading instead: 3.40 GB a step
        // off the last stream's pass, against 6.79 at eight bits, at 7.15 s a step against
        // 7.51 resident. On the 16 GB M4 mini (12124 MB working set) this build measured
        // 5196 MB peak streamed, 22.6 s a step.
        streamedPeakBytes: 6_420_000_000,
        // The live figure of that same run: 974 MB, rounded **down** to 970 MB, the same to the byte
        // as the 8-bit build's and for the same reason, against the 6707 MB resident.
        streamedResidentBytes: 970_000_000,
        maxPromptTokens: 512,
        capabilities: zImageTurboCapabilities,
        // Measured: 7,123,354,222 bytes written by `make mirror` on 2026-09-06 at four bits,
        // group 64 — 3.8 GB of transformer, 3.0 GB of text encoder, the 164 MB autoencoder
        // and the tokenizer — against the 13.3 GB of the published eight-bit build. The
        // entry said 6.7 GB before this measurement; which change grew the build was not
        // traced.
        builtBytes: 7_130_000_000,
        mirror: mirror
    )

    /// Every known model, in the order a picker should list them.
    ///
    /// klein's 4-bit variant sits before its 8-bit one on purpose: `default(fitting:)` takes the
    /// first entry that runs resident, and the 8-bit variant's peak lands within a gigabyte of
    /// a 16 GB Mac's budget, so which variant such a Mac opened on would otherwise be decided
    /// by a measurement error rather than by a decision.
    ///
    /// The order is no longer "smallest machine first" on its own terms, because every family
    /// streams: Z-Image 8-bit leads the list and is selectable on a 16 GB Mac, streamed. What
    /// keeps that from becoming such a Mac's recommendation is `default(fitting:)`, not this
    /// order — its resident pass on a Mac that holds something, and its *leanest* streamed pass
    /// on one that holds nothing, since order is an editorial judgement about what to show
    /// first and says nothing about which model is cheapest to read off a disk. So a later
    /// entry may be added here on its merits as a listing.
    /// Qwen-Image 2.1 sits after every picture model and before every clip model, which is the
    /// slot Qwen-Image-2512 held. Two rules decide it. It must come **after** klein 4-bit,
    /// because `default(fitting:)`'s resident pass walks this order and takes the first entry a
    /// Mac can hold: on a 24 GB Mac 2.1 fits resident, and a first launch that opened on a 33 GB
    /// download and forty steps a picture would be the worst first answer in the catalog. And it
    /// belongs before Wan, because the list reads as pictures and then clips, and because
    /// `animator()` takes the first entry that makes them — a picture model cannot change that
    /// answer, but the reading is what keeps it obvious that it cannot.
    public static let all: [ModelDescriptor] = [
        zImageTurbo8bit, flux2Klein4bit, flux2Klein8bit, zImageTurbo4bit, qwenImage21_4bit,
        wan22TI2V5B4bit, ltx2Distilled4bit, ltx2DistilledAudio4bit,
    ]

    /// The model selected on first launch when nothing is known about the machine.
    public static let `default`: ModelDescriptor = zImageTurbo8bit

    /// Looks up a model by the identifier stored in settings or in a past generation.
    public static func descriptor(id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    /// What every Z-Image Turbo variant accepts. Quantizing the weights changes how much memory
    /// they need and how fine the output is, not which sizes or step counts the model runs.
    private static let zImageTurboCapabilities = ModelCapabilities(
        sizeAlignment: 16,
        sizePresets: [
            ImageSize(width: 1024, height: 1024),
            // A quick size, a little over half the default's pixels, for a draft of a prompt.
            ImageSize(width: 768, height: 768),
            ImageSize(width: 1152, height: 896),
            ImageSize(width: 896, height: 1152),
            ImageSize(width: 1216, height: 832),
            ImageSize(width: 832, height: 1216),
            ImageSize(width: 1344, height: 768),
            ImageSize(width: 768, height: 1344),
        ],
        sizeBounds: 512...2048,
        defaultSize: ImageSize(width: 1024, height: 1024),
        stepBounds: 1...20,
        defaultSteps: 9,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        // SDEdit needs only an image encoder and a linear schedule, and Z-Image has both: the
        // autoencoder's encoder is in every snapshot Zephra loads, 106 tensors the loader
        // already applies, and the flow-matching scheduler interpolates
        // `x_t = (1 - sigma) * x0 + sigma * noise`. Nothing extra is downloaded or loaded for
        // this, which is why both variants get it.
        supportsReferenceImage: true,
        referenceStrengthBounds: 0.1...0.9,
        defaultReferenceStrength: 0.6
    )
}
