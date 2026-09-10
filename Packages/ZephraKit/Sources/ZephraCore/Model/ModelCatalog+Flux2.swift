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
        // Measured on an M4 Max, four steps, seed 42, identical across repetitions: 4941 MB
        // live after a generation at any size, because the weights are the whole of it. Peak
        // follows the image: 7651 MB at 512, 9037 MB at 768, 12087 MB at 1024. So 1024 fits a
        // 16 GB Mac's budget outright, which is what this entry is for. Editing costs more: a
        // 1024 image from a 512 reference peaked at 19227 MB, the reference's tokens riding
        // through every attention layer beside the image's. That edit figure was measured
        // with the reference's tokens still float32, which widened the whole edit to
        // float32; they are cast to the stream's dtype since the 2026-09-05 audit, and the
        // edit is due a rerun on an idle machine.
        residentBytes: 4_940_000_000,
        peakBytes: 12_090_000_000,
        // Measured, same machine and seed, tiled at a 64-cell latent tile: 7660 MB at 1024.
        tiledPeakBytes: 7_660_000_000,
        // The pipeline pads every prompt to 512 tokens and conditions on all of them.
        maxPromptTokens: 512,
        capabilities: flux2KleinCapabilities,
        // Measured: 5,365,936,128 bytes written by the build, 2.70 GB of transformer, 2.49 GB
        // of the encoder's first 27 layers and embedding, and the 168 MB autoencoder verbatim.
        builtBytes: 5_370_000_000,
        mirror: mirror
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
        // Measured as the 4-bit entry was: 8144 MB live, 10854 MB peak at 512 and 15289 MB at
        // 1024, 10861 MB tiled at 1024. A step costs the same as at four bits, 7.0 s against
        // 6.9 s at 1024: the quantized matmul is compute-bound at these shapes whichever width
        // it packs, as it is for Z-Image.
        residentBytes: 8_140_000_000,
        peakBytes: 15_290_000_000,
        tiledPeakBytes: 10_860_000_000,
        maxPromptTokens: 512,
        capabilities: flux2KleinCapabilities,
        // Measured: 8,572,731,392 bytes written by the build.
        builtBytes: 8_570_000_000,
        mirror: mirror
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
            // A quick size, a little over half the default's pixels, for a draft of a prompt.
            ImageSize(width: 768, height: 768),
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
        supportsReferenceImage: true,
        // Strength does not apply, the way guidance does not apply above, and for a reason
        // worth stating: klein does not start from a noised copy of the picture. It encodes the
        // reference to tokens, concatenates them after the image being made with their own
        // image index on the rotary embedding, and walks the whole schedule from pure noise —
        // see `Flux2ReferenceConditioning` and `Flux2Pipeline+Denoise`. There is no partway
        // point to enter at, so there is no distance to choose, and a degenerate range is how a
        // descriptor says so. The interface reads the range and shows no slider.
        referenceStrengthBounds: 1...1,
        defaultReferenceStrength: 1
    )
}
