import Foundation
import MLX
import ZephraMLX

/// Text to picture, and pictures to picture, with Qwen-Image 2.1: the loaded components and the
/// loop that runs them.
///
/// Not `Sendable`, and confined to the engine's serial inference executor like the backend that
/// owns it.
///
/// The shape of a run is the reference pipeline's, in four moves. Every reference picture is
/// decoded and resized **once**, and that one copy feeds both the vision tower (flattened over
/// white) and the autoencoder (all four channels). The prompt and its pictures go through the
/// vision-language encoder together, and what comes back is the text the encoder wrote having
/// looked at them — the encoder's own image embeddings are thrown away, and the condition
/// latents take their place in the joint sequence. The loop then walks the schedule with the
/// condition latents prepended to the noise on every step, slicing the prediction back to the
/// target's tail. And the finished latent is unpacked, put back in the autoencoder's space and
/// decoded to four channels.
public final class QwenImage21Pipeline {
    /// What a loaded model consists of.
    struct Loaded {
        let snapshot: URL
        let configuration: QwenImage21Configuration
        let tokenizer: QwenImage21Tokenizer
        let encoder: QwenImage21PromptEncoder
        let transformer: QwenImage21Transformer
        let autoencoder: QwenImage21Autoencoder
        let normalization: QwenImage21LatentNormalization
        let rope: QwenImage21Rope
        /// What the stream is held in, decided once at load; see
        /// `QwenImage21TransformerPrecision`.
        let activation: DType

        /// Pixels a latent cell covers along each edge: sixteen.
        var latentScale: Int { configuration.vae.spatialCompression }
        /// Both edges of a rendered picture are a multiple of this: thirty-two.
        var alignment: Int { configuration.sizeAlignment }
    }

    var loaded: Loaded?

    /// Creates an empty pipeline. Nothing is read until `loadModel`.
    public init() {}

    /// Whether `loadModel` has succeeded and `unloadModel` has not been called since.
    public var isLoaded: Bool { loaded != nil }

    /// Called after a denoising step has been evaluated, with the step it just finished
    /// (counting from zero), how many there are, and a way to decode the latent as it stands.
    ///
    /// The frame is a closure rather than a value because making one is a whole pass through
    /// the autoencoder: a host that shows frames only every so often never pays for the ones it
    /// would have thrown away. How often that is belongs to the host, not to this package.
    public typealias PreviewHandler = (
        _ step: Int, _ totalSteps: Int, _ frame: () throws -> QwenImage21LatentPreview
    ) -> Void

    /// Makes one picture.
    public func generate(
        _ request: QwenImage21Request,
        onProgress: (QwenImage21GenerationProgress) -> Void = { _ in },
        onPreview: PreviewHandler? = nil
    ) throws -> QwenImage21Result {
        guard let model = loaded else { throw QwenImage21PipelineError.notLoaded }
        guard request.width % model.alignment == 0, request.height % model.alignment == 0 else {
            throw QwenImage21PipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: model.alignment)
        }

        let pictures = try request.references.map { try QwenImage21ReferencePicture.fitted($0) }
        let conditioning = try encode(request, pictures: pictures, with: model, onProgress: onProgress)
        let latents = try denoise(
            request, conditioning: conditioning, with: model,
            onProgress: onProgress, onPreview: onPreview)
        return try decode(request, latents: latents, with: model, onProgress: onProgress)
    }
}
