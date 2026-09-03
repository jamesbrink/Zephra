import Foundation

/// The FLUX.2 klein family's entries. Its numbers are in `all` beside the others; they live
/// here so the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// The one download both variants are built from: the bf16 release, without the root
    /// `flux-2-klein-4b.safetensors`. That file is Black Forest Labs' own single-file format,
    /// 149 tensors this loader does not read, and 7.75 GB, so it is left out by pattern rather
    /// than fetched and ignored. The three sample JPEGs beside it are left out the same way.
    static let flux2KleinPatterns = [
        "model_index.json", "scheduler/*", "text_encoder/*", "tokenizer/*", "transformer/*",
        "vae/*",
    ]

    /// The bf16 release, in bytes, as listed by the repository: transformer 7,751,109,744,
    /// text encoder 8,044,981,992, autoencoder 168,120,878, tokenizer 15,881,232, and configs.
    static let flux2KleinDownloadBytes: Int64 = 15_980_000_000

    /// FLUX.2 klein 4B at four-bit precision, built on this Mac from the release the first
    /// time it is loaded.
    ///
    /// A 3.9-billion-parameter rectified-flow transformer conditioned on Qwen3-4B, distilled
    /// to four steps with no guidance. Half the parameters of Z-Image Turbo and fewer than half
    /// the steps, which is what makes it the model a 16 GB Mac opens on. The same checkpoint
    /// edits a picture handed in beside the prompt, which no other model here does.
    ///
    /// Nothing publishes it in a form this loader reads, and the release is 16 GB of bf16, so
    /// the download is packed here: `builtBytes` is that cost, on top of the download.
    public static let flux2Klein4bit = ModelDescriptor(
        id: "flux2-klein-4b-4bit",
        displayName: "FLUX.2 klein 4B",
        variantName: "4-bit",
        backend: .flux2,
        source: .huggingFace(
            repoID: "black-forest-labs/FLUX.2-klein-4B",
            revision: "main",
            filePatterns: flux2KleinPatterns
        ),
        quantization: .int4,
        downloadBytes: flux2KleinDownloadBytes,
        // TODO(measure): estimates, not measurements. Derived from Z-Image's measured bytes per
        // parameter: 3.5 billion transformer weights packed at four bits plus 0.4 billion held
        // whole, the first 27 of the encoder's 36 layers packed the same way with its
        // embedding table whole, and the 168 MB autoencoder verbatim. Replace all four with
        // `make bench ARGS="--model flux2-klein-4b-4bit --size 1024 --steps 4 --runs 3 --json"`
        // on Release, idle, with and without ZEPHRA_VAE_TILE=64.
        residentBytes: 5_400_000_000,
        peakBytes: 10_500_000_000,
        tiledPeakBytes: 7_500_000_000,
        // The pipeline pads every prompt to 512 tokens and conditions on all of them.
        maxPromptTokens: 512,
        capabilities: flux2KleinCapabilities,
        builtBytes: 4_500_000_000
    )

    /// FLUX.2 klein 4B at eight-bit precision, built the same way from the same download.
    public static let flux2Klein8bit = ModelDescriptor(
        id: "flux2-klein-4b-8bit",
        displayName: "FLUX.2 klein 4B",
        variantName: "8-bit",
        backend: .flux2,
        source: .huggingFace(
            repoID: "black-forest-labs/FLUX.2-klein-4B",
            revision: "main",
            filePatterns: flux2KleinPatterns
        ),
        quantization: .int8,
        downloadBytes: flux2KleinDownloadBytes,
        // TODO(measure): estimates; see the 4-bit entry for the procedure.
        residentBytes: 8_500_000_000,
        peakBytes: 13_500_000_000,
        tiledPeakBytes: 10_500_000_000,
        maxPromptTokens: 512,
        capabilities: flux2KleinCapabilities,
        builtBytes: 7_500_000_000
    )

    /// What the distilled klein accepts.
    ///
    /// The step and guidance bounds are the distillation's, not the architecture's: the release
    /// is marked distilled, was trained for four steps, and takes no classifier-free guidance,
    /// so a guidance slider or a negative prompt would be a control nothing answers to. Sizes
    /// are aligned to 16: a 2x2 patch over an 8x autoencoder, as Z-Image's are.
    static let flux2KleinCapabilities = ModelCapabilities(
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
        sizeBounds: 512...1536,
        defaultSize: ImageSize(width: 1024, height: 1024),
        // Chosen, not measured: four is what it was distilled for, and eight leaves room to
        // try more without offering the fifty the undistilled release wants.
        stepBounds: 1...8,
        defaultSteps: 4,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        supportsReferenceImage: true
    )
}
