/// The models Zephra ships knowledge of, hand-written because each one needs verified numbers.
public enum ModelCatalog {
    /// Z-Image Turbo at eight-bit precision: the only variant Zephra ships, and it needs more
    /// than a 16 GB Mac can spare. `fitting` excludes it below roughly 21 GB of physical memory.
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
        // Measured on an M4 Max, deterministic across six repetitions: 12236 MB live after a
        // 1024-pixel generation and 23501 MB peak during one. The peak is the VAE decode, not
        // weight loading, which is lazy and never exceeds 7.2 GB; see VENDORED.md.
        residentBytes: 12_240_000_000,
        maxPromptTokens: 512,
        capabilities: ModelCapabilities(
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
    )

    /// Every known model, in the order a picker should list them.
    public static let all: [ModelDescriptor] = [zImageTurbo8bit]

    /// The model selected on first launch.
    public static let `default`: ModelDescriptor = zImageTurbo8bit

    /// Looks up a model by the identifier stored in settings or in a past generation.
    public static func descriptor(id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    /// The models that leave enough headroom on a Mac with this much RAM to stay responsive.
    ///
    /// Nothing calls this while there is one model: it is the filter behind the model picker,
    /// and it is tested so the numbers in the catalog stay honest in the meantime.
    public static func fitting(physicalMemory: UInt64) -> [ModelDescriptor] {
        let budget = Double(physicalMemory) * 0.6
        return all.filter { Double($0.residentBytes) <= budget }
    }
}
