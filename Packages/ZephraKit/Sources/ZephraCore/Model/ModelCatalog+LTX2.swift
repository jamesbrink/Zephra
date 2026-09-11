import Foundation

/// The LTX-2.5 family's entries. Its numbers are in `all` beside the others; they live here so
/// the catalog file stays one screen of what every model has in common.
extension ModelCatalog {
    /// The files the video-only build reads from the ungated `mlx-community` bf16 pack: the
    /// distilled transformer, the text connector, the Gemma 4 encoder with its tokenizer and
    /// config, the convolutional video decoder and encoder, the spatial latent upscaler the
    /// second stage doubles the latent with, and the pack's own configs and license. The audio
    /// autoencoder, the vocoder, the temporal upscaler, the dev transformer and the diffusion
    /// decoder are left out by pattern rather than fetched and ignored.
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
        "vae_encoder.safetensors", "spatial_upscaler_x2_v1_1.safetensors",
        "spatial_upscaler_x2_v1_1_config.json", "gemma4-12b-ltx-v1/*",
    ]

    /// The video-only files with the audio autoencoder and the vocoder beside them, for the
    /// entry that makes sound. A list of its own rather than the first plus two, because the
    /// patterns are part of a variant's identity (`PackedProvenance`): the video-only entry's
    /// stays what it was, and the mirror's index for it with it.
    static let ltx2AudioPatterns = ltx2Patterns + ["audio_vae.safetensors", "vocoder.safetensors"]

    /// The six weight files as the repository lists them — transformer 37,985,774,111,
    /// connector 6,344,495,770, Gemma 23,814,788,105, decoder 814,349,515, encoder
    /// 637,885,335, spatial upscaler 995,745,061 — plus the 32,169,626-byte tokenizer and
    /// the configs: 70,625,207,798 in all.
    static let ltx2DownloadBytes: Int64 = 70_630_000_000

    /// The same plus `audio_vae.safetensors` (107,157,208) and `vocoder.safetensors`
    /// (258,461,656): 70,990,826,662 in all.
    static let ltx2AudioDownloadBytes: Int64 = 70_995_000_000

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
        // Measured on an M4 Max at 768 x 512 and 49 frames with the video encoder and the
        // spatial upsampler resident: 19155 MB live after a generation and 23421 MB peak, the
        // peak the load's (the float32 scales before their cast) and not the decode's. In two
        // stages, which this frame takes (`LTX2StagePlan`), 47.4 s a clip; in one stage,
        // 68.7 s at 7.6 s a step; holding a first frame in two stages, 49.9 s. Before the
        // upsampler joined the load the same clip measured 18159 MB and 22425 MB, so the
        // upsampler is the gigabyte between. There is no tiled decode yet, so the tiled figure
        // is the plain one.
        residentBytes: 19_160_000_000,
        peakBytes: 23_430_000_000,
        tiledPeakBytes: 23_430_000_000,
        // Measured the same way with both stacks streamed and the video encoder and the
        // upsampler resident (convolutions never stream), holding a first frame in two
        // stages: 10003 MB peak and 5737 MB live, 46.1 s a clip, the same pace as resident on
        // an M4 Max, whose SSD keeps up. Before the upsampler joined the load the same run
        // measured 9007 MB and 4741 MB, and before the encoder did, 8369 MB and 4103 MB, 8.09
        // GB read per step at 1.19 GB/s. On the 16 GB M4 mini (12.1 GB working set),
        // encoder-less and in one stage: 8284 MB peak, 4103 MB live, 25.5 s a step and 232 s
        // a clip, read-bound at 0.32 GB/s straight after the variant landed from the mirror;
        // that read rate is the one figure here worth a rerun.
        streamedPeakBytes: 10_010_000_000,
        // Gemma is padded to 1024 tokens and the connector reads every position.
        maxPromptTokens: 1024,
        capabilities: ltx2Capabilities,
        // Measured: 20,839,333,747 bytes written by `make quantize-ltx2` in 83 s — 8.56 GB of
        // transformer (480 four-bit linears with float32 scales and biases, the conditioning
        // whole), 1.89 GB of connector with its 8-bit projection, 8.00 GB of text encoder with
        // its 8-bit token table, the autoencoder's two files, the 0.81 GB decoder and the
        // 0.64 GB encoder, copied as they are into one shard, and the 1.0 GB spatial
        // upsampler copied likewise.
        builtBytes: 20_840_000_000,
        mirror: mirror
    )

    /// LTX-2.5 distilled at four-bit precision with its audio lane, built on this Mac from the
    /// same pack plus its two audio files the first time it is loaded.
    ///
    /// The whole 22-billion-parameter audio-video DiT: the video stream as `ltx2Distilled4bit`
    /// runs it and, beside it, the audio stream — 5.9 billion parameters of audio attention,
    /// feed-forward and the gated cross-attentions that join the lanes in every block — with
    /// the 2048-wide audio connector, the audio autoencoder's decoder and the vocoder with its
    /// bandwidth extender. The clip's MP4 carries a stereo AAC track at 48 kHz. The video
    /// differs from the video-only entry's: the audio-to-video cross-attention adds a term
    /// the video-only forward has not got.
    public static let ltx2DistilledAudio4bit = ModelDescriptor(
        id: "ltx-2.5-distilled-audio-4bit",
        displayName: "LTX-2.5",
        variantName: "4-bit, with sound",
        backend: .ltx2,
        source: .huggingFace(
            repoID: "mlx-community/ltx-2.5-mlx",
            revision: "main",
            filePatterns: ltx2AudioPatterns
        ),
        quantization: .int4,
        downloadBytes: ltx2AudioDownloadBytes,
        // Estimated from the video-only entry's measurements and the lane's size, to be
        // measured: 5.86 billion more parameters at four bits is 3.3 GB more resident and a
        // fraction more scratch, and the decoder and vocoder 0.37 GB in float32 doubled.
        residentBytes: 23_200_000_000,
        peakBytes: 27_500_000_000,
        tiledPeakBytes: 27_500_000_000,
        // Streamed, the lane's 3.5 GB more of blocks is read per step rather than held; the
        // extra resident pieces are the audio connector and projection, the decoder and the
        // vocoder.
        streamedPeakBytes: 11_400_000_000,
        maxPromptTokens: 1024,
        capabilities: ltx2AudioCapabilities,
        // Estimated from the video-only build: its 20.84 GB plus the lane's 5.86 billion
        // parameters at four bits with float32 scales (3.3 GB), the audio projection at
        // eight bits (0.4 GB), the conditioners whole (0.2 GB), and the two audio files
        // copied (0.37 GB). To be measured by `make quantize-ltx2-audio`.
        builtBytes: 25_100_000_000,
        mirror: mirror
    )

    /// What the audio entry accepts: everything the video-only one does, and it makes sound.
    static let ltx2AudioCapabilities = ModelCapabilities(
        sizeAlignment: ltx2Capabilities.sizeAlignment,
        sizePresets: ltx2Capabilities.sizePresets,
        sizeBounds: ltx2Capabilities.sizeBounds,
        defaultSize: ltx2Capabilities.defaultSize,
        stepBounds: ltx2Capabilities.stepBounds,
        defaultSteps: ltx2Capabilities.defaultSteps,
        guidanceBounds: ltx2Capabilities.guidanceBounds,
        defaultGuidance: ltx2Capabilities.defaultGuidance,
        supportsNegativePrompt: ltx2Capabilities.supportsNegativePrompt,
        supportsSeed: ltx2Capabilities.supportsSeed,
        supportsReferenceImage: ltx2Capabilities.supportsReferenceImage,
        referenceStrengthBounds: ltx2Capabilities.referenceStrengthBounds,
        defaultReferenceStrength: ltx2Capabilities.defaultReferenceStrength,
        frameBounds: ltx2Capabilities.frameBounds,
        defaultFrames: ltx2Capabilities.defaultFrames,
        frameAlignment: ltx2Capabilities.frameAlignment,
        frameRate: ltx2Capabilities.frameRate,
        continuationFrames: ltx2Capabilities.continuationFrames,
        defaultContinuationFrames: ltx2Capabilities.defaultContinuationFrames,
        producesAudio: true
    )

    /// What the distilled LTX-2.5 accepts.
    ///
    /// Steps and guidance are the distillation's: eight sigmas fixed by the checkpoint and no
    /// classifier-free guidance, so neither is a choice. Sizes are aligned to 64: the video
    /// autoencoder's spatial factor is 32, but a frame whose edges halve onto that grid is what
    /// the two-stage path needs (`LTX2StagePlan`, in the backend), and at 47 s against 69 s
    /// for the same 768 x 512 clip that path is the one every fitted or typed size should
    /// land on. 768 x 512 is the reference's one-stage default. A step's time grows with the
    /// token count, so the quick presets are the lever on speed: 512 x 320 is two fifths of
    /// the default's pixels and a clip in about that share of the time. Frames run on the
    /// autoencoder's ladder of eight plus one: 9 to 121 at 24 fps, 49 (two seconds) to start,
    /// which is what an M4 Max makes in under a minute.
    static let ltx2Capabilities = ModelCapabilities(
        sizeAlignment: 64,
        sizePresets: [
            ImageSize(width: 768, height: 512),
            ImageSize(width: 512, height: 768),
            ImageSize(width: 640, height: 384),
            ImageSize(width: 512, height: 320),
            ImageSize(width: 320, height: 512),
            ImageSize(width: 960, height: 576),
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
        frameRate: 24,
        // A clip is carried on by holding its last frames as the new clip's first latent
        // frames, the reference's multi-frame condition at latent index 0. On the ladder of
        // eight plus one: seventeen frames is the last frame on its own plus two chunks of
        // eight, three latent frames. Measured on halcyon over a 768 x 512 two-stage clip:
        // nine held frames left a visible step at the join (the kite moved and the shore
        // came into frame), seventeen carried the motion across it; twenty-five is the most
        // worth holding before the held part crowds out what is new in a 49-frame segment.
        continuationFrames: 1...25,
        defaultContinuationFrames: 17
    )
}
