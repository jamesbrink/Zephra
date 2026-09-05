import Foundation
import MLX

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

    /// Both image edges must be a multiple of this: the autoencoder's eightfold reduction times
    /// the two-by-two packing.
    public static let sizeAlignment = Flux2Autoencoder.spatialScale * Flux2LatentPacking.patchSize

    var loaded: Loaded?

    /// Creates an empty pipeline. Nothing is read until `loadModel`.
    public init() {}

    /// Whether `loadModel` has succeeded and `unloadModel` has not been called since.
    public var isLoaded: Bool { loaded != nil }

    /// Reads the configuration, the tokenizer, and every component's weights under `snapshot`,
    /// and holds the stream in `activation` from then on.
    public func loadModel(
        at snapshot: URL,
        activation: DType = Flux2TransformerPrecision.defaultActivation,
        onProgress: (Flux2GenerationProgress) -> Void = { _ in }
    ) throws {
        onProgress(Flux2GenerationProgress(stage: .loading))
        let configuration = try Flux2Configuration(readingFrom: snapshot)
        let manifest = try Flux2QuantizationManifest.read(from: snapshot)
        let tokenizer = try Flux2Tokenizer(snapshot: snapshot)

        let textEncoder = Qwen3TextEncoder(configuration.textEncoder)
        try Flux2WeightLoading.load(
            into: textEncoder,
            weights: try Flux2WeightLoading.weights(
                in: snapshot.appending(path: Flux2Configuration.Component.textEncoder.directoryName)),
            manifest: manifest)

        let transformer = Flux2Transformer(configuration.transformer)
        try Flux2WeightLoading.load(
            into: transformer,
            weights: Flux2TransformerWeights.sanitized(
                try Flux2WeightLoading.weights(
                    in: snapshot.appending(path: Flux2Configuration.Component.transformer.directoryName))),
            manifest: manifest,
            checkpointName: Flux2TransformerWeights.checkpointName(of:))

        let autoencoder = Flux2Autoencoder(configuration.vae)
        try autoencoder.load(
            weights: try Flux2WeightLoading.weights(
                in: snapshot.appending(path: Flux2Configuration.Component.vae.directoryName)))

        // The stream's dtype is applied here, once: a float32 scale anywhere would widen it.
        Flux2WeightLoading.castFloatParameters(of: textEncoder, to: activation)
        Flux2WeightLoading.castFloatParameters(of: transformer, to: activation)

        loaded = Loaded(
            snapshot: snapshot, configuration: configuration, tokenizer: tokenizer,
            textEncoder: textEncoder, transformer: transformer, autoencoder: autoencoder,
            activation: activation)
        MLX.eval(textEncoder.parameters(), transformer.parameters(), autoencoder.parameters())
    }

    /// Releases the weights and the scratch memory MLX was holding for them.
    public func unloadModel() {
        loaded = nil
        Memory.clearCache()
    }

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
        let alignment = Self.sizeAlignment
        guard request.width % alignment == 0, request.height % alignment == 0 else {
            throw Flux2PipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: alignment)
        }

        onProgress(Flux2GenerationProgress(stage: .encodingPrompt))
        let length = min(request.maxPromptTokens, Flux2PromptTemplate.sequenceLength)
        let (ids, validCount) = model.tokenizer.padded(prompt: request.prompt, to: length)
        let tokens = MLXArray(ids.map(Int32.init)).reshaped([1, -1])
        let text = model.textEncoder(tokens, validCount: validCount)
        MLX.eval(text)

        let references = try encodeReferences(request, with: model, onProgress: onProgress)
        return try denoise(request, text: text, references: references, with: model,
                           onProgress: onProgress, onPreview: onPreview)
    }
}
