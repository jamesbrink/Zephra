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
        // Measured on an M4 Max, deterministic across repetitions: 12236 MB live after a
        // 1024-pixel generation and 23501 MB peak during one. The peak is the VAE decode, not
        // weight loading, which is lazy and never exceeds 7.2 GB; see VENDORED.md.
        residentBytes: 12_240_000_000,
        peakBytes: 23_500_000_000,
        // Measured, same machine and seed, with the tiled decode at a 64-cell latent tile:
        // 17673 MB, so the decode transient falls from 11265 MB to 5437 MB.
        tiledPeakBytes: 17_680_000_000,
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
        // Measured on an M4 Max, deterministic across repetitions: 6575 MB live after a
        // generation, and a peak that follows the image size — 10693 MB at 512 pixels,
        // 14599 MB at 768, 17839 MB at 1024. Peak is resident plus the VAE decode's scratch,
        // which is unquantized and so costs the same here as it does at eight bits.
        residentBytes: 6_580_000_000,
        peakBytes: 17_840_000_000,
        // Derived, not measured: 6575 MB resident plus the 5437 MB tiled decode transient
        // measured on the 8-bit variant, which decodes the same unquantized VAE at the same
        // tile and so costs the same here.
        tiledPeakBytes: 12_010_000_000,
        maxPromptTokens: 512,
        capabilities: zImageTurboCapabilities,
        // Measured: what `make quantize` writes at four bits, group 64 — 6.7 GB against the
        // 13.3 GB of the published eight-bit build.
        builtBytes: 6_700_000_000
    )

    /// Every known model, in the order a picker should list them.
    ///
    /// klein's 4-bit variant sits before its 8-bit one on purpose: `default(fitting:)` takes the
    /// first entry that runs, and the 8-bit variant's peak lands within a gigabyte of a 16 GB
    /// Mac's budget, so which variant such a Mac opened on would otherwise be decided by a
    /// measurement error rather than by a decision.
    public static let all: [ModelDescriptor] = [
        zImageTurbo8bit, flux2Klein4bit, flux2Klein8bit, zImageTurbo4bit, qwenImage2512_4bit,
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
