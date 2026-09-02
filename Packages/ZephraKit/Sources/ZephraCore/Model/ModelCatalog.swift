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

    /// Qwen-Image-2512 at four-bit precision, distilled to four steps, built on this Mac by
    /// `make quantize-qwen`.
    ///
    /// A twenty-billion-parameter dual-stream MMDiT against Z-Image Turbo's six billion, which
    /// buys prompt adherence and text rendering in a different class and costs about eight times
    /// the seconds per step. Nothing publishes it in a form Zephra can load: the release is 57.7
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
        // Qwen-Image conditions on 1024 tokens of Qwen2.5-VL hidden states, against Z-Image's 512.
        maxPromptTokens: 1024,
        capabilities: qwenImage2512Capabilities
    )

    /// Every known model, in the order a picker should list them.
    public static let all: [ModelDescriptor] = [
        zImageTurbo8bit, zImageTurbo4bit, qwenImage2512_4bit,
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
    private static let qwenImage2512Capabilities = ModelCapabilities(
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
        stepBounds: 1...12,
        defaultSteps: 4,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true
    )

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
        supportsSeed: true
    )
}
