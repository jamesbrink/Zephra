import Foundation

/// The LTX-2.5 family's entries. Its numbers are in `all` beside the others; they live here so
/// the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// The files the video-only build reads from the ungated `mlx-community` bf16 pack: the
    /// distilled transformer, the text connector, the Gemma 4 encoder with its tokenizer and
    /// config, the convolutional video decoder and encoder, and the pack's own configs and
    /// license. The audio autoencoder, the vocoder, the two upscalers, the dev transformer and
    /// the diffusion decoder are left out by pattern rather than fetched and ignored.
    ///
    /// The video *encoder* is fetched because a first frame is held by encoding the picture:
    /// image-to-video is the one thing this family does with a reference picture, and the
    /// encoder is the half of the autoencoder that reads one.
    ///
    /// Lightricks' own repositories are gated: a download needs a logged-in token, and Zephra
    /// sends none. This pack is the same bf16 weights redistributed under the LTX-2.x Community
    /// License, which travels with them as `LICENSE.md`.
    static let ltx2Patterns = [
        "config.json", "embedded_config.json", "LICENSE.md",
        "transformer-distilled.safetensors", "connector.safetensors", "vae_decoder.safetensors",
        "vae_encoder.safetensors", "gemma4-12b-ltx-v1/*",
    ]

    /// The five weight files as the repository lists them — transformer 37,985,774,111,
    /// connector 6,344,495,770, Gemma 23,814,788,105, decoder 814,349,515, encoder
    /// 637,885,335 — plus the 32,169,626-byte tokenizer and the configs: 69,629,462,462 in all.
    static let ltx2DownloadBytes: Int64 = 69_630_000_000

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
        // Measured on an M4 Max, eight steps, seed 42, at 768 x 512 and 49 frames, with the
        // video encoder resident: 18159 MB live after a generation and 22425 MB peak. Before
        // the encoder was loaded the same run measured 17521 MB and 21787 MB, so the encoder is
        // the 638 MB between them and the peak is still the load's — the float32 scales before
        // their cast — and not the decode's, which a 9-frame 512 x 288 clip reaching the same
        // peak already said. 63.4 s a clip at 7.0 s a step; holding a first frame costs
        // nothing measurable (65.6 s at strength 0, 68.8 s at 0.6, on a busy machine) and the
        // peak does not move. There is no tiled decode yet, so the tiled figure is the plain
        // one.
        residentBytes: 18_160_000_000,
        peakBytes: 22_430_000_000,
        tiledPeakBytes: 22_430_000_000,
        // Measured the same way with both stacks streamed and the video encoder resident (it
        // is 0.64 GB of convolutions and never streams): 9007 MB peak and 4741 MB live holding
        // a first frame, a poster byte for byte the resident run's, and the same pace as
        // resident on an M4 Max, whose SSD keeps up. Before the encoder joined the load the
        // same run measured 8369 MB and 4103 MB, 8.09 GB read per step at 1.19 GB/s. On the
        // 16 GB M4 mini (12.1 GB working set), encoder-less: 8284 MB peak, 4103 MB live,
        // 25.5 s a step and 232 s a clip, read-bound at 0.32 GB/s straight after the variant
        // landed from the mirror; that read rate is the one figure here worth a rerun.
        streamedPeakBytes: 9_010_000_000,
        // Gemma is padded to 1024 tokens and the connector reads every position.
        maxPromptTokens: 1024,
        capabilities: ltx2Capabilities,
        // Measured: 19,843,588,073 bytes written by `make quantize-ltx2` in 88 s — 8.56 GB of
        // transformer (480 four-bit linears with float32 scales and biases, the conditioning
        // whole), 1.89 GB of connector with its 8-bit projection, 8.00 GB of text encoder with
        // its 8-bit token table, and the autoencoder's two files, the 0.81 GB decoder and the
        // 0.64 GB encoder, copied as they are into one shard.
        builtBytes: 19_850_000_000,
        mirror: mirror
    )

    /// What the distilled LTX-2.5 accepts.
    ///
    /// Steps and guidance are the distillation's: eight sigmas fixed by the checkpoint and no
    /// classifier-free guidance, so neither is a choice. Sizes are aligned to 32, the video
    /// autoencoder's spatial factor; 768 x 512 is the reference's one-stage default. A step's
    /// time grows with the token count, so the quick presets are the lever on speed: 512 x 288
    /// is three eighths of the default's pixels and a clip in about three eighths of the time.
    /// Frames run on the autoencoder's ladder of eight plus one: 9 to 121 at 24 fps, 49 (two
    /// seconds) to start, which is what an M4 Max makes in under a minute.
    static let ltx2Capabilities = ModelCapabilities(
        sizeAlignment: 32,
        sizePresets: [
            ImageSize(width: 768, height: 512),
            ImageSize(width: 512, height: 768),
            ImageSize(width: 640, height: 384),
            ImageSize(width: 512, height: 288),
            ImageSize(width: 288, height: 512),
            ImageSize(width: 960, height: 544),
        ],
        sizeBounds: 256...1024,
        defaultSize: ImageSize(width: 768, height: 512),
        stepBounds: 8...8,
        defaultSteps: 8,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        supportsReferenceImage: true,
        // The strength runs the other way here, and the inversion is the backend's
        // (`LTX2RequestMapper`). Everywhere else in Zephra strength is "how much of the
        // picture to throw away" on a model that starts from a noised copy of it; LTX-2.5
        // does not start from the picture, it *holds* it as the clip's first frame, and what
        // the loop wants is the opposite number — how strongly to hold it, `1 - strength`. So
        // 0, the default, holds the frame exactly, which is what image-to-video means, and
        // 0.9 lets the model redraw almost all of it. A bound of 1 is not offered: at 1 the
        // frame is not held at all, which is text-to-image with an ignored picture.
        referenceStrengthBounds: 0.0...0.9,
        defaultReferenceStrength: 0,
        frameBounds: 9...121,
        defaultFrames: 49,
        frameAlignment: 8,
        frameRate: 24
    )
}
