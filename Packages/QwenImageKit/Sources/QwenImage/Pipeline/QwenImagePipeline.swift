import Foundation
import MLX
import MLXRandom

/// Runs Qwen-Image: prompt in, PNG out.
///
/// One instance holds one loaded model. It is not `Sendable` and belongs to whichever executor
/// loaded it, like everything else in this package.
public final class QwenImagePipeline {
    private var loaded: Loaded?

    /// Everything a loaded model consists of.
    private struct Loaded {
        let snapshot: URL
        let configuration: QwenImageConfiguration
        let tokenizer: QwenImageTokenizer
        let textEncoder: Qwen25TextEncoder
        let transformer: QwenImageTransformer
        let autoencoder: QwenImageAutoencoder
    }

    /// The image size must be a whole number of patches, which is the VAE's eightfold
    /// compression times the transformer's 2x2 patch.
    public static let sizeAlignment = 16

    public init() {}

    /// Whether a model is in memory.
    public var isLoaded: Bool { loaded != nil }

    /// Reads a snapshot into memory, replacing whatever was there.
    public func loadModel(
        at snapshot: URL,
        onProgress: (QwenImageGenerationProgress) -> Void = { _ in }
    ) throws {
        unloadModel()
        onProgress(QwenImageGenerationProgress(stage: .loading))

        let configuration = try QwenImageConfiguration(readingFrom: snapshot)
        let manifest = QwenImageQuantizationManifest.read(from: snapshot)

        let textEncoder = Qwen25TextEncoder(configuration.textEncoder)
        try QwenImageWeightLoading.load(
            into: textEncoder,
            weights: try QwenImageWeightLoading.weights(
                in: snapshot.appending(path: "text_encoder")),
            manifest: manifest
        )

        let transformer = QwenImageTransformer(configuration.transformer)
        try QwenImageWeightLoading.load(
            into: transformer,
            weights: try QwenImageWeightLoading.weights(
                in: snapshot.appending(path: "transformer")),
            manifest: manifest
        )

        let autoencoder = QwenImageAutoencoder(configuration.vae)
        try autoencoder.load(
            weights: try QwenImageWeightLoading.weights(in: snapshot.appending(path: "vae")))

        loaded = Loaded(
            snapshot: snapshot,
            configuration: configuration,
            tokenizer: try QwenImageTokenizer(snapshot: snapshot),
            textEncoder: textEncoder,
            transformer: transformer,
            autoencoder: autoencoder
        )
        MLX.eval(textEncoder.parameters(), transformer.parameters(), autoencoder.parameters())
    }

    /// Drops the weights and the scratch they were using.
    public func unloadModel() {
        loaded = nil
        Memory.clearCache()
    }

    /// Generates one image and returns PNG bytes.
    public func generate(
        _ request: QwenImageGenerationRequest,
        onProgress: (QwenImageGenerationProgress) -> Void = { _ in }
    ) throws -> Data {
        guard let model = loaded else { throw QwenImagePipelineError.notLoaded }
        let alignment = Self.sizeAlignment
        guard request.width % alignment == 0, request.height % alignment == 0 else {
            throw QwenImagePipelineError.unalignedSize(
                width: request.width, height: request.height, alignment: alignment)
        }

        onProgress(QwenImageGenerationProgress(stage: .encodingPrompt))
        let tokens = MLXArray(model.tokenizer.encode(prompt: request.prompt).map(Int32.init))
            .reshaped([1, -1])
        let conditioning = model.textEncoder(
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

        var latents = QwenImageLatentPacking.pack(
            MLXRandom.normal(
                [1, model.configuration.vae.zDim, latentHeight, latentWidth],
                key: MLXRandom.key(request.seed)
            ))

        let timesteps = scheduler.timesteps(
            scaledBy: model.configuration.scheduler.numTrainTimesteps)
        for (index, timestep) in timesteps.enumerated() {
            try Task.checkCancellation()
            onProgress(
                QwenImageGenerationProgress(
                    stage: .denoising(step: index, of: timesteps.count)))
            // The model reads the noise level on a zero-to-one scale and stretches it back up
            // itself.
            let prediction = model.transformer(
                latents: latents,
                text: conditioning,
                timestep: MLXArray([Float(timestep / 1000)]),
                frequencies: frequencies
            )
            latents = scheduler.step(modelOutput: prediction, index: index, sample: latents)
            MLX.eval(latents)
        }

        onProgress(QwenImageGenerationProgress(stage: .decoding))
        let unpacked = QwenImageLatentPacking.unpack(
            latents, height: latentHeight, width: latentWidth)
        let pixels = model.autoencoder.decode(unpacked)
        MLX.eval(pixels)
        return try QwenPixelBuffer.png(from: pixels)
    }
}
