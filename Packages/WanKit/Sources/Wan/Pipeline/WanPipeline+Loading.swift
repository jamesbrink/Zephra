import Foundation
import MLX
import ZephraMLX

/// Getting a packed snapshot into memory and out again.
extension WanPipeline {
    /// Reads a snapshot into memory, replacing whatever was there.
    ///
    /// With `streaming` the encoder's 24 blocks and the transformer's 30 are not read here at
    /// all: each stack is handed to a `LayerWeightStream` that reads it from the shards on
    /// every pass, and only what is left — the token table, the patch embedding, the
    /// conditioning, the head and the autoencoder — is evaluated now. Without it every weight
    /// is read here and stays.
    ///
    /// The encoder's and transformer's float32 parameters — the packer's scales and biases —
    /// are cast to `activation` here, before a stream is attached, so a streamed pass hands
    /// back the cast nodes rather than the shards' float32. The autoencoder computes in the
    /// dtype its weights came in.
    public func loadModel(
        at snapshot: URL,
        activation: DType = .bfloat16,
        streaming: WanStreaming? = nil,
        onProgress: (WanGenerationProgress) -> Void = { _ in }
    ) throws {
        unloadModel()
        onProgress(WanGenerationProgress(stage: .loading))
        let manifest = try PackedSnapshotManifest.read(from: snapshot)

        let encoderDirectory = snapshot.appending(path: "text_encoder")
        let textEncoder = UMT5TextEncoder(
            try UMT5Configuration(readingFrom: encoderDirectory.appending(path: "config.json")))
        try PackedWeightLoading.load(
            into: textEncoder,
            weights: try SafetensorsShards.weights(in: encoderDirectory),
            manifest: manifest,
            checkpointName: { $0 })
        PackedWeightLoading.castFloatParameters(of: textEncoder, to: activation)
        if let streaming {
            textEncoder.stream = try LayerWeightStream(
                layers: textEncoder.layers,
                keyPrefix: WanResidentParameters.textEncoderLayers,
                index: ShardIndex(shards: SafetensorsShards.shards(in: encoderDirectory)),
                depth: streaming.depth,
                checkpointName: { $0 })
        }

        let transformerDirectory = snapshot.appending(path: "transformer")
        let transformer = WanTransformer(
            try WanTransformerConfiguration(readingFrom: transformerDirectory.appending(path: "config.json")))
        try PackedWeightLoading.load(
            into: transformer,
            weights: WanTransformerWeights.sanitized(try SafetensorsShards.weights(in: transformerDirectory)),
            manifest: manifest,
            checkpointName: WanTransformerWeights.checkpointName(of:))
        PackedWeightLoading.castFloatParameters(of: transformer, to: activation)
        if let streaming {
            transformer.stream = try LayerWeightStream(
                layers: transformer.blocks,
                keyPrefix: WanResidentParameters.transformerBlocks,
                index: ShardIndex(shards: SafetensorsShards.shards(in: transformerDirectory)),
                depth: streaming.depth,
                checkpointName: WanTransformerWeights.checkpointName(of:))
        }

        let vaeDirectory = snapshot.appending(path: "vae")
        let configuration = try WanVAEConfiguration(readingFrom: vaeDirectory.appending(path: "config.json"))
        let autoencoder = WanVideoAutoencoder(configuration)
        // The release keeps the autoencoder in float32 and the packer copies it as it is; it
        // runs here in bfloat16, cast tensor by tensor as it is read. Float32 cost 38 s of a
        // 55 s clip at 832 x 480 and set the run's peak; bfloat16 decodes the same latent to
        // the same picture at half the bytes, since the convolutions accumulate in float32
        // on Metal either way.
        try autoencoder.load(
            weights: try SafetensorsShards.weights(in: vaeDirectory).mapValues { $0.asType(.bfloat16) })

        let result = Loaded(
            tokenizer: try WanTokenizer(directory: snapshot.appending(path: "tokenizer")),
            textEncoder: textEncoder, transformer: transformer, autoencoder: autoencoder,
            normalization: WanLatentNormalization(configuration), activation: activation)
        WanResidentParameters.eval(result, streamed: streaming != nil)
        loaded = result
    }

    /// Drops the weights and the scratch they were using.
    public func unloadModel() {
        loaded = nil
        Memory.clearCache()
    }
}
