import Foundation
import MLX
import MLXRandom
import ZephraMLX

/// Runs Qwen-Image: prompt in, PNG out.
///
/// One instance holds one loaded model. It is not `Sendable` and belongs to whichever executor
/// loaded it, like everything else in this package.
public final class QwenImagePipeline {
    var loaded: Loaded?

    /// Everything a loaded model consists of.
    struct Loaded {
        let snapshot: URL
        let configuration: QwenImageConfiguration
        let tokenizer: QwenImageTokenizer
        let textEncoder: Qwen25TextEncoder
        let transformer: QwenImageTransformer
        let autoencoder: QwenImageAutoencoder
        /// What the stream is held in, decided once at load; see `QwenImageTransformerPrecision`.
        let activation: DType
    }

    public init() {}

    /// Whether a model is in memory.
    public var isLoaded: Bool { loaded != nil }

    /// Called after a denoising step has been evaluated, with the step it just finished
    /// (counting from zero), how many there are, and a way to decode the latent as it stands.
    ///
    /// The frame is a closure rather than a value because making one is a pass through the
    /// autoencoder: a host that shows frames only every so often never pays for the ones it
    /// would have thrown away. How often that is belongs to the host, not to this package.
    public typealias PreviewHandler = (
        _ step: Int, _ totalSteps: Int, _ frame: () -> QwenImageLatentPreview
    ) -> Void

    /// Generates one image and returns PNG bytes.
    public func generate(
        _ request: QwenImageGenerationRequest,
        onProgress: (QwenImageGenerationProgress) -> Void = { _ in },
        onPreview: PreviewHandler? = nil
    ) throws -> Data {
        guard let model = loaded else { throw QwenImagePipelineError.notLoaded }
        let alignment = model.configuration.sizeAlignment
        guard request.width % alignment == 0, request.height % alignment == 0 else {
            throw QwenImagePipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: alignment)
        }

        onProgress(QwenImageGenerationProgress(stage: .encodingPrompt))
        let ids = model.tokenizer.encode(prompt: request.prompt, limit: request.maxPromptTokens)
        let tokens = MLXArray(ids.map(Int32.init)).reshaped([1, -1])
        let conditioning = try model.textEncoder(
            tokens, dropping: QwenImagePromptTemplate.dropIndex)
        MLX.eval(conditioning)

        let scale = model.configuration.vae.spatialScale
        let latentHeight = request.height / scale
        let latentWidth = request.width / scale
        let patch = model.configuration.transformer.patchSize
        let tokenCount = QwenImageLatentPacking.tokenCount(
            latentHeight: latentHeight, latentWidth: latentWidth)

        let scheduler = FlowMatchEulerScheduler(
            configuration: model.configuration.scheduler,
            steps: request.steps,
            imageSequenceLength: tokenCount
        )
        let frequencies = QwenImageRotaryEmbedding(
            axesDim: model.configuration.transformer.axesDimsRope
        ).frequencies(
            frames: 1,
            height: latentHeight / patch,
            width: latentWidth / patch,
            textLength: conditioning.shape[1]
        )

        // Noise and conditioning enter the loop in the stream's dtype: MLX promotes, so a
        // float32 noise would run every block in float32 whatever the weights are.
        let dtype = model.activation
        let noise = QwenImageLatentPacking.pack(
            MLXRandom.normal(
                [1, model.configuration.vae.zDim, latentHeight, latentWidth],
                key: MLXRandom.key(request.seed)
            )
        ).asType(dtype)

        let latents = try QwenImageDenoiseLoop.run(
            noise: noise,
            latentSize: (height: latentHeight, width: latentWidth),
            reference: request.referenceImage.map {
                QwenImageDenoiseLoop.Reference(
                    image: $0, strength: request.referenceStrength,
                    width: request.width, height: request.height)
            },
            scheduler: scheduler,
            transformer: model.transformer,
            autoencoder: model.autoencoder,
            conditioning: conditioning.asType(dtype),
            frequencies: frequencies,
            onProgress: onProgress,
            onPreview: onPreview
        )

        onProgress(QwenImageGenerationProgress(stage: .decoding))
        let unpacked = QwenImageLatentPacking.unpack(
            latents, height: latentHeight, width: latentWidth)
        let pixels = model.autoencoder.decode(unpacked, tile: request.vaeTile)
        MLX.eval(pixels)
        return try PixelBuffer.png(from: pixels)
    }
}
