import Foundation
import MLX

/// Text to a clip through the three models of Wan 2.2's video path.
///
/// Not Sendable, and confined by its owner to one thread: it holds MLX arrays. The host
/// decides the stream's dtype and whether the two layer stacks are streamed from disk; the kit
/// reads no environment.
public final class WanPipeline {
    /// Everything a loaded model is.
    struct Loaded {
        let tokenizer: WanTokenizer
        let textEncoder: UMT5TextEncoder
        let transformer: WanTransformer
        /// Both halves: the decoder for every clip, the encoder for a held first frame. 1.4 GB
        /// of bfloat16 convolutions against the model's 8 GB, loaded with everything else.
        let autoencoder: WanVideoAutoencoder
        /// The 48 channel means and deviations between the autoencoder and the transformer.
        let normalization: WanLatentNormalization
        /// The dtype the stream runs in.
        let activation: DType
    }

    var loaded: Loaded?

    /// The schedule every run walks; the checkpoint fixes it.
    public let schedule = WanDistilledSchedule()

    public init() {}

    /// Whether a model is in memory.
    public var isLoaded: Bool { loaded != nil }

    /// Called after a step with the step's index, the total, and a closure that makes the
    /// preview frame. A closure rather than a frame so a host that throttles never pays for a
    /// frame it drops.
    public typealias PreviewHandler = (
        _ step: Int, _ totalSteps: Int, _ frame: () -> WanLatentPreview
    ) -> Void

    /// Makes the clip `request` asks for.
    public func generate(
        _ request: WanGenerationRequest,
        onProgress: (WanGenerationProgress) -> Void = { _ in },
        onPreview: PreviewHandler? = nil
    ) throws -> WanClip {
        guard let loaded else { throw WanPipelineError.notLoaded }
        let alignment = WanLatentLayout.pixelAlignment
        guard request.width % alignment == 0, request.height % alignment == 0 else {
            throw WanPipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: alignment)
        }
        guard request.frames >= 1, (request.frames - 1) % WanLatentLayout.frameScale == 0 else {
            throw WanPipelineError.unalignedFrames(
                frames: request.frames, alignment: WanLatentLayout.frameScale)
        }
        onProgress(WanGenerationProgress(stage: .encodingPrompt))
        let text = try encodePrompt(request.prompt, with: loaded)
        let layout = WanLatentLayout(
            pixelFrames: request.frames, pixelWidth: request.width, pixelHeight: request.height)
        let held = try request.firstFrame.map {
            try WanHeldFirstFrame($0, layout: layout, with: loaded)
        }
        let latent = try denoise(
            text: text, layout: layout, request: request, held: held, with: loaded,
            onProgress: onProgress, onPreview: onPreview)
        onProgress(WanGenerationProgress(stage: .decoding))
        let video = loaded.autoencoder.decode(
            loaded.normalization.denormalize(latent).asType(loaded.autoencoder.dtype),
            tile: request.vaeTile)
        MLX.eval(video)
        return WanClip(
            video: WanFrames.video(video, frameRate: request.frameRate),
            poster: try WanFrames.posterPNG(video))
    }
}
