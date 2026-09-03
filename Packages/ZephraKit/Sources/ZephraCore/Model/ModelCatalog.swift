import Foundation

/// The models Zephra ships knowledge of, hand-written because each one needs verified numbers.
public enum ModelCatalog {
    /// Where variants built on this Mac are kept. Nothing downloads into it; `make quantize`
    /// writes here, and a descriptor pointing at a directory that is not there yet fails with a
    /// message naming the missing folder rather than trying to fetch it.
    public static let localModelsDirectory = URL.applicationSupportDirectory
        .appending(path: "Zephra/Models", directoryHint: .isDirectory)

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

    /// Z-Image Turbo at four-bit precision, built on this Mac by `make quantize`.
    ///
    /// No published repository carries four-bit Z-Image weights in the manifest format the
    /// vendored loader reads, so this variant has no download: the descriptor points at the
    /// directory the quantizer writes, and the backend reports a clear error until it is there.
    public static let zImageTurbo4bit = ModelDescriptor(
        id: "z-image-turbo-4bit",
        displayName: "Z-Image Turbo",
        variantName: "4-bit",
        backend: .zImage,
        source: .localDirectory(localModelsDirectory.appending(path: "z-image-turbo-4bit")),
        quantization: .int4,
        downloadBytes: 0,
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
        capabilities: zImageTurboCapabilities
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

    /// The model to start a Mac with this much RAM on: the first listed variant that runs at
    /// its default size there, or `default` when none does.
    ///
    /// Without this a 16 GB Mac would open on a model its own menu marks "Needs 23 GB", load
    /// 12 GB of weights it cannot decode with, and only find the variant it can run by hand.
    public static func `default`(fitting physicalMemory: UInt64) -> ModelDescriptor {
        fitting(physicalMemory: physicalMemory).first ?? zImageTurbo8bit
    }

    /// Looks up a model by the identifier stored in settings or in a past generation.
    public static func descriptor(id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    /// The models that run at their default size on a Mac with this much RAM without paging,
    /// counting the tiled VAE decode as available — it is what the app turns on when it matters.
    ///
    /// This is the filter behind the model picker's wording, not a gate on what can be chosen:
    /// a model left out of this list is still runnable at a smaller size.
    public static func fitting(physicalMemory: UInt64) -> [ModelDescriptor] {
        all.filter { fit($0, physicalMemory: physicalMemory).runsAtDefaultSize }
    }

    /// Where one model lands against a Mac's working-set budget: exactly, only tiled, or not
    /// at its default size at all.
    public static func fit(_ descriptor: ModelDescriptor, physicalMemory: UInt64) -> MemoryFit {
        MemoryFit(descriptor: descriptor, physicalMemory: physicalMemory)
    }

    /// Whether this Mac can run the model at its default size with the exact, untiled decode.
    public static func fitsComfortably(
        _ descriptor: ModelDescriptor,
        physicalMemory: UInt64
    ) -> Bool {
        fit(descriptor, physicalMemory: physicalMemory) == .fits
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
