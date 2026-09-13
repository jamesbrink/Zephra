import Foundation
import MLX
import ZephraMLX

/// Text to image, and picture to picture, with FLUX.2 klein: the loaded components and the loop
/// that runs them.
///
/// Not `Sendable`, and confined to the engine's serial inference executor like the backend
/// that owns it.
public final class Flux2Pipeline {
    /// What a loaded model consists of.
    struct Loaded {
        let snapshot: URL
        let configuration: Flux2Configuration
        let tokenizer: Flux2Tokenizer
        let textEncoder: Qwen3TextEncoder
        let transformer: Flux2Transformer
        let autoencoder: Flux2Autoencoder
        /// What the stream is held in, decided once at load; see `Flux2TransformerPrecision`.
        let activation: DType
    }

    var loaded: Loaded?

    /// Creates an empty pipeline. Nothing is read until `loadModel`.
    public init() {}

    /// Whether `loadModel` has succeeded and `unloadModel` has not been called since.
    public var isLoaded: Bool { loaded != nil }

    /// Makes one image and returns it as PNG bytes.
    /// Called after a denoising step has been evaluated, with the step it just finished
    /// (counting from zero), how many there are, and a way to decode the latent as it stands.
    ///
    /// The frame is a closure rather than a value because making one is a whole pass through
    /// the autoencoder: a host that shows frames only every so often never pays for the ones it
    /// would have thrown away. How often that is belongs to the host, not to this package.
    public typealias PreviewHandler = (
        _ step: Int, _ totalSteps: Int, _ frame: () -> Flux2LatentPreview
    ) -> Void

    public func generate(
        _ request: Flux2GenerationRequest,
        onProgress: (Flux2GenerationProgress) -> Void = { _ in },
        onPreview: PreviewHandler? = nil
    ) throws -> Data {
        guard let model = loaded else { throw Flux2PipelineError.notLoaded }
        let alignment = model.configuration.sizeAlignment
        guard request.width % alignment == 0, request.height % alignment == 0 else {
            throw Flux2PipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: alignment)
        }

        onProgress(Flux2GenerationProgress(stage: .encodingPrompt))
        let length = min(request.maxPromptTokens, Flux2PromptTemplate.sequenceLength)
        let (ids, validCount) = model.tokenizer.padded(prompt: request.prompt, to: length)
        let tokens = MLXArray(ids.map(Int32.init)).reshaped([1, -1])
        let text = try model.textEncoder(tokens, validCount: validCount)
        MLX.eval(text)

        let references = try encodeReferences(request, with: model, onProgress: onProgress)
        return try denoise(request, text: text, references: references, with: model,
                           onProgress: onProgress, onPreview: onPreview)
    }
}
