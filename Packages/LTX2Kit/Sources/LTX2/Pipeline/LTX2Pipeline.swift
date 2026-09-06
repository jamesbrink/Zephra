import Foundation
import MLX

/// Text to a clip through the four models of LTX-2.5's video path.
///
/// Not Sendable, and confined by its owner to one thread: it holds MLX arrays. The host
/// decides the stream's dtype and whether the two layer stacks are streamed from disk; the kit
/// reads no environment.
public final class LTX2Pipeline {
    /// Everything a loaded model is.
    struct Loaded {
        let snapshot: URL
        let tokenizer: LTX2Tokenizer
        let textEncoder: Gemma4TextModel
        let extractor: LTX2FeatureExtractor
        let connector: LTX2TextConnector
        let transformer: LTX2Transformer
        let decoder: LTX2VideoDecoder
        /// The dtype the stream runs in.
        let activation: DType
    }

    var loaded: Loaded?

    /// The schedule every run walks; the checkpoint fixes it.
    public let schedule = LTX2DistilledSchedule()

    public init() {}

    /// Whether a model is in memory.
    public var isLoaded: Bool { loaded != nil }

    /// Called after a step with the step's index, the total, and a closure that makes the
    /// preview frame. A closure rather than a frame so a host that throttles never pays for a
    /// frame it drops.
    public typealias PreviewHandler = (
        _ step: Int, _ totalSteps: Int, _ frame: () -> LTX2LatentPreview
    ) -> Void

    /// Makes the clip `request` asks for.
    public func generate(
        _ request: LTX2GenerationRequest,
        onProgress: (LTX2GenerationProgress) -> Void = { _ in },
        onPreview: PreviewHandler? = nil
    ) throws -> LTX2Clip {
        guard let loaded else { throw LTX2PipelineError.notLoaded }
        let alignment = LTX2LatentLayout.scale
        guard request.width % alignment.width == 0, request.height % alignment.height == 0 else {
            throw LTX2PipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: alignment.width)
        }
        guard request.frames >= 1, (request.frames - 1) % alignment.frames == 0 else {
            throw LTX2PipelineError.unalignedFrames(frames: request.frames, alignment: alignment.frames)
        }
        onProgress(LTX2GenerationProgress(stage: .encodingPrompt))
        let text = try encodePrompt(request.prompt, maxTokens: request.maxPromptTokens, with: loaded)
        let layout = LTX2LatentLayout(
            pixelFrames: request.frames, pixelWidth: request.width, pixelHeight: request.height)
        let latent = try denoise(
            text: text, layout: layout, request: request, with: loaded,
            onProgress: onProgress, onPreview: onPreview)
        onProgress(LTX2GenerationProgress(stage: .decoding))
        let video = loaded.decoder.decode(latent.asType(loaded.decoder.dtype))
        MLX.eval(video)
        return LTX2Clip(
            video: LTX2Frames.video(video, frameRate: request.frameRate),
            poster: try LTX2Frames.posterPNG(video))
    }
}
