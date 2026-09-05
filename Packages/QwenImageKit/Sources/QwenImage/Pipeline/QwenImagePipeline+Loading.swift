import Foundation
import MLX
import ZephraMLX

/// Getting a snapshot into memory and out again.
extension QwenImagePipeline {
    /// Reads a snapshot into memory, replacing whatever was there.
    ///
    /// With `streaming` the text encoder's layers and the transformer's blocks are not read
    /// here at all: each is handed to a `LayerWeightStream` that reads it from the shards on
    /// every pass, and only what is left — embeddings, the input and output projections, the
    /// norms, and the whole autoencoder — is evaluated now. Without it every weight is read
    /// here and stays.
    ///
    /// The text encoder's and the transformer's float32 parameters — the packer's scales and
    /// biases — are cast to the activation dtype here, before a stream is attached, so a
    /// streamed pass hands back the cast nodes rather than the shards' float32. The
    /// autoencoder is left in float32 on purpose: its decode is the peak and not the step,
    /// and the VAE and preview fixtures are float32.
    public func loadModel(
        at snapshot: URL,
        streaming: QwenImageStreaming? = nil,
        onProgress: (QwenImageGenerationProgress) -> Void = { _ in }
    ) throws {
        unloadModel()
        onProgress(QwenImageGenerationProgress(stage: .loading))

        let configuration = try QwenImageConfiguration(readingFrom: snapshot)
        let manifest = try QwenImageQuantizationManifest.read(from: snapshot)
        let activation = QwenImageTransformerPrecision.activation

        let textEncoderDirectory = snapshot.appending(path: "text_encoder")
        let textEncoder = Qwen25TextEncoder(configuration.textEncoder)
        try QwenImageWeightLoading.load(
            into: textEncoder,
            weights: try QwenImageWeightLoading.weights(in: textEncoderDirectory),
            manifest: manifest
        )
        QwenImageWeightLoading.castFloatParameters(of: textEncoder, to: activation)
        if let streaming {
            textEncoder.model.stream = try LayerWeightStream(
                layers: textEncoder.model.layers,
                keyPrefix: QwenImageResidentParameters.textEncoderLayers,
                index: ShardIndex(shards: QwenImageWeightLoading.shards(in: textEncoderDirectory)),
                depth: streaming.depth
            )
        }

        let transformerDirectory = snapshot.appending(path: "transformer")
        let transformer = QwenImageTransformer(configuration.transformer)
        try QwenImageWeightLoading.load(
            into: transformer,
            weights: try QwenImageWeightLoading.weights(in: transformerDirectory),
            manifest: manifest
        )
        QwenImageWeightLoading.castFloatParameters(of: transformer, to: activation)
        if let streaming {
            transformer.stream = try LayerWeightStream(
                layers: transformer.blocks,
                keyPrefix: QwenImageResidentParameters.transformerBlocks,
                index: ShardIndex(shards: QwenImageWeightLoading.shards(in: transformerDirectory)),
                depth: streaming.depth,
                checkpointName: QwenImageTransformerWeights.checkpointName(of:)
            )
        }

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
        QwenImageResidentParameters.eval(
            textEncoder: textEncoder, transformer: transformer, autoencoder: autoencoder,
            streamed: streaming != nil)
    }

    /// Drops the weights and the scratch they were using.
    public func unloadModel() {
        loaded = nil
        Memory.clearCache()
    }
}
