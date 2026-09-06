import Foundation

/// The LTX-2.5 family's entries. Its numbers are in `all` beside the others; they live here so
/// the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// The files the video-only build reads from the ungated `mlx-community` bf16 pack: the
    /// distilled transformer, the text connector, the Gemma 4 encoder with its tokenizer and
    /// config, the convolutional video decoder, and the pack's own configs and license. The
    /// audio autoencoder, the vocoder, the two upscalers, the dev transformer, the diffusion
    /// decoder and the video encoder are left out by pattern rather than fetched and ignored.
    ///
    /// Lightricks' own repositories are gated: a download needs a logged-in token, and Zephra
    /// sends none. This pack is the same bf16 weights redistributed under the LTX-2.x Community
    /// License, which travels with them as `LICENSE.md`.
    static let ltx2Patterns = [
        "config.json", "embedded_config.json", "LICENSE.md",
        "transformer-distilled.safetensors", "connector.safetensors", "vae_decoder.safetensors",
        "gemma4-12b-ltx-v1/*",
    ]

    /// The four weight files as the repository lists them: transformer 37,986,118,xxx,
    /// connector 6,344,489,120, Gemma 23,815,xxx,xxx, decoder 814,xxx,xxx, plus the 32 MB
    /// tokenizer and the configs — 68.96 GB in all.
    static let ltx2DownloadBytes: Int64 = 68_960_000_000

    /// LTX-2.5 distilled at four-bit precision, video only, built on this Mac from the pack the
    /// first time it is loaded.
    ///
    /// A 22-billion-parameter audio-video DiT of which the video stream — 13.1 billion
    /// parameters across 48 blocks — is packed and run, conditioned on a Gemma 4 12B encoder
    /// through a 1-D connector and decoded by a 3-D convolutional autoencoder, distilled to
    /// eight ancestral Euler steps with no guidance. Frames come in eights plus one at 24 fps;
    /// the audio stream, and so sound, is the audio variant's job (`ROADMAP.md`).
    public static let ltx2Distilled4bit = ModelDescriptor(
        id: "ltx-2.5-distilled-4bit",
        displayName: "LTX-2.5",
        variantName: "4-bit, video only",
        backend: .ltx2,
        source: .huggingFace(
            repoID: "mlx-community/ltx-2.5-mlx",
            revision: "main",
            filePatterns: ltx2Patterns
        ),
        quantization: .int4,
        downloadBytes: ltx2DownloadBytes,
        // Estimates, to be replaced by measurements on an M4 Max at 768 x 512, 49 frames:
        // the 19.3 GB build less the float32 scales the loader casts to bfloat16, about
        // 17 GB resident; peak adds the attention over 6144 tokens and the decoder's
        // intermediates at that size; streamed, the two stacks leave their non-streamed
        // remainder — the embeddings, the projection, the conditioning and the decoder —
        // resident.
        residentBytes: 17_000_000_000,
        peakBytes: 21_000_000_000,
        tiledPeakBytes: 21_000_000_000,
        streamedPeakBytes: 8_000_000_000,
        // Gemma is padded to 1024 tokens and the connector reads every position.
        maxPromptTokens: 1024,
        capabilities: ltx2Capabilities,
        // Measured: 19,263,078,400 bytes written by the first `make quantize-ltx2` in 82 s —
        // 8.56 GB of transformer (480 four-bit linears with float32 scales and biases, the
        // conditioning whole), 1.89 GB of connector with its 8-bit projection, 8.00 GB of
        // encoder with its 8-bit token table, and the 0.81 GB decoder copied as it is.
        builtBytes: 19_270_000_000,
        mirror: mirror
    )

    /// What the distilled LTX-2.5 accepts.
    ///
    /// Steps and guidance are the distillation's: eight sigmas fixed by the checkpoint and no
    /// classifier-free guidance, so neither is a choice. Sizes are aligned to 32, the video
    /// autoencoder's spatial factor; 768 x 512 is the reference's one-stage default. Frames
    /// run on the autoencoder's ladder of eight plus one: 9 to 121 at 24 fps, 49 (two
    /// seconds) to start, which is what an M4 Max makes in under a minute.
    static let ltx2Capabilities = ModelCapabilities(
        sizeAlignment: 32,
        sizePresets: [
            ImageSize(width: 768, height: 512),
            ImageSize(width: 512, height: 288),
            ImageSize(width: 640, height: 384),
            ImageSize(width: 960, height: 544),
            ImageSize(width: 512, height: 768),
        ],
        sizeBounds: 256...1024,
        defaultSize: ImageSize(width: 768, height: 512),
        stepBounds: 8...8,
        defaultSteps: 8,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        supportsReferenceImage: false,
        frameBounds: 9...121,
        defaultFrames: 49,
        frameAlignment: 8,
        frameRate: 24
    )
}
