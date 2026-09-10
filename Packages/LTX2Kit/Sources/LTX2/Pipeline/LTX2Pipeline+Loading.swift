import Foundation
import MLX
import ZephraMLX

/// Getting a packed snapshot into memory and out again.
extension LTX2Pipeline {
    /// Reads a snapshot into memory, replacing whatever was there.
    ///
    /// With `streaming` the encoder's 48 layers and the transformer's 48 blocks are not read
    /// here at all: each stack is handed to a `LayerWeightStream` that reads it from the shards
    /// on every pass, and only what is left — the token table, the projection, the connector,
    /// the conditioning heads and the decoder — is evaluated now. Without it every weight is
    /// read here and stays.
    ///
    /// The encoder's, connector's and transformer's float32 parameters — the packer's scales
    /// and biases — are cast to `activation` here, before a stream is attached, so a streamed
    /// pass hands back the cast nodes rather than the shards' float32. The feature extractor's
    /// projection is left in float32 on purpose: 188160 products summed in bfloat16 lose the
    /// prompt. The decoder and the upsampler compute in the dtype their weights came in.
    public func loadModel(
        at snapshot: URL,
        activation: DType = .bfloat16,
        streaming: LTX2Streaming? = nil,
        onProgress: (LTX2GenerationProgress) -> Void = { _ in }
    ) throws {
        unloadModel()
        onProgress(LTX2GenerationProgress(stage: .loading))
        let manifest = try PackedSnapshotManifest.read(from: snapshot)

        let encoderDirectory = snapshot.appending(path: "text_encoder")
        let gemma = try Gemma4Configuration(readingFrom: encoderDirectory.appending(path: "config.json"))
        let textEncoder = Gemma4TextModel(gemma)
        try PackedWeightLoading.load(
            into: textEncoder,
            weights: Self.stripped(try SafetensorsShards.weights(in: encoderDirectory), of: Gemma4TextModel.checkpointPrefix),
            manifest: manifest,
            checkpointName: { Gemma4TextModel.checkpointPrefix + $0 })
        PackedWeightLoading.castFloatParameters(of: textEncoder, to: activation)
        if let streaming {
            textEncoder.stream = try LayerWeightStream(
                layers: textEncoder.layers,
                keyPrefix: LTX2ResidentParameters.textEncoderLayers,
                index: ShardIndex(shards: SafetensorsShards.shards(in: encoderDirectory)),
                depth: streaming.depth,
                checkpointName: { Gemma4TextModel.checkpointPrefix + $0 })
        }

        let transformerConfiguration = LTX2TransformerConfiguration()
        let connectorWeights = try SafetensorsShards.weights(in: snapshot.appending(path: "connector"))
        let extractor = LTX2FeatureExtractor(
            hiddenSize: gemma.hiddenSize, stateCount: gemma.numHiddenLayers + 1,
            outputSize: transformerConfiguration.crossAttentionDim)
        try PackedWeightLoading.load(
            into: extractor,
            weights: LTX2ConnectorWeights.projectionWeights(connectorWeights),
            manifest: manifest,
            checkpointName: { LTX2ConnectorWeights.projectionPrefix + $0 })
        let connector = LTX2TextConnector(
            dim: transformerConfiguration.crossAttentionDim, heads: transformerConfiguration.heads,
            layers: LTX2TextConnector.defaultLayers)
        try PackedWeightLoading.load(
            into: connector,
            weights: LTX2ConnectorWeights.connectorWeights(connectorWeights),
            manifest: manifest,
            checkpointName: LTX2ConnectorWeights.checkpointName(of:))
        PackedWeightLoading.castFloatParameters(of: connector, to: activation)

        let transformerDirectory = snapshot.appending(path: "transformer")
        let transformer = LTX2Transformer(transformerConfiguration)
        try PackedWeightLoading.load(
            into: transformer,
            weights: LTX2TransformerWeights.sanitized(try SafetensorsShards.weights(in: transformerDirectory)),
            manifest: manifest,
            checkpointName: LTX2TransformerWeights.checkpointName(of:))
        PackedWeightLoading.castFloatParameters(of: transformer, to: activation)
        if let streaming {
            transformer.stream = try LayerWeightStream(
                layers: transformer.blocks,
                keyPrefix: LTX2ResidentParameters.transformerBlocks,
                index: ShardIndex(shards: SafetensorsShards.shards(in: transformerDirectory)),
                depth: streaming.depth,
                checkpointName: LTX2TransformerWeights.checkpointName(of:))
        }

        // Both halves of the autoencoder are packed into one `vae` component and read from one
        // dictionary; each sanitizer takes the tensors under its own file's prefix.
        let vae = try SafetensorsShards.weights(in: snapshot.appending(path: "vae"))
        let decoder = LTX2VideoDecoder(.ltx25)
        try decoder.load(weights: vae)
        let videoEncoder = LTX2VideoEncoder(.ltx25)
        try videoEncoder.load(weights: vae)
        let upsampler = LTX2LatentUpsampler()
        try upsampler.load(weights: try SafetensorsShards.weights(in: snapshot.appending(path: "upsampler")))

        let result = Loaded(
            tokenizer: try LTX2Tokenizer(directory: encoderDirectory),
            textEncoder: textEncoder, extractor: extractor, connector: connector,
            transformer: transformer, decoder: decoder, encoder: videoEncoder,
            upsampler: upsampler, activation: activation)
        LTX2ResidentParameters.eval(result, streamed: streaming != nil)
        loaded = result
    }

    /// Drops the weights and the scratch they were using.
    public func unloadModel() {
        loaded = nil
        Memory.clearCache()
    }

    /// `weights` under their names with `prefix` removed; anything not under it is left out.
    static func stripped(_ weights: [String: MLXArray], of prefix: String) -> [String: MLXArray] {
        weights.reduce(into: [:]) { renamed, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            renamed[String(entry.key.dropFirst(prefix.count))] = entry.value
        }
    }
}
