import Foundation
import MLX
import ZephraMLX

/// Getting a packed snapshot into memory and out again.
extension Flux2Pipeline {
    /// Reads the configuration, the tokenizer, and every component's weights under `snapshot`,
    /// and holds the stream in `activation` from then on.
    ///
    /// With `streaming` the encoder's 27 layers, the five dual-stream blocks and the twenty
    /// single-stream ones are not read here at all: each stack is handed to a
    /// `LayerWeightStream` that reads it from the shards on every pass, and only what is left —
    /// the token table, the shared modulation, the two input projections, the output head and
    /// the autoencoder — is evaluated now. Without it every weight is read here and stays.
    ///
    /// The order below is the one `LayerWeightStream` asks for and is load-bearing per
    /// component: fill the tree, cast its float32 parameters to `activation`, attach the stream,
    /// and evaluate the resident parameters last. The cast is what the stream keeps handing back
    /// on every later pass — the packer writes scales float32, and a raw node would widen the
    /// whole stream from the second layer on. Evaluating the tree before a stream is attached
    /// would read the model in, which is the thing being avoided.
    public func loadModel(
        at snapshot: URL,
        activation: DType = Flux2TransformerPrecision.defaultActivation,
        streaming: Flux2Streaming? = nil,
        onProgress: (Flux2GenerationProgress) -> Void = { _ in }
    ) throws {
        onProgress(Flux2GenerationProgress(stage: .loading))
        let configuration = try Flux2Configuration(readingFrom: snapshot)
        let manifest = try PackedSnapshotManifest.read(from: snapshot)
        let tokenizer = try Flux2Tokenizer(snapshot: snapshot)

        let encoderDirectory = snapshot.appending(
            path: Flux2Configuration.Component.textEncoder.directoryName)
        let textEncoder = Qwen3TextEncoder(configuration.textEncoder)
        try PackedWeightLoading.load(
            into: textEncoder,
            weights: try SafetensorsShards.weights(in: encoderDirectory),
            manifest: manifest)
        PackedWeightLoading.castFloatParameters(of: textEncoder, to: activation)
        if let streaming {
            textEncoder.model.stream = try LayerWeightStream(
                layers: textEncoder.model.layers,
                keyPrefix: Flux2ResidentParameters.textEncoderLayers,
                index: ShardIndex(shards: SafetensorsShards.shards(in: encoderDirectory)),
                depth: streaming.depth)
        }

        let transformerDirectory = snapshot.appending(
            path: Flux2Configuration.Component.transformer.directoryName)
        let transformer = Flux2Transformer(configuration.transformer)
        try PackedWeightLoading.load(
            into: transformer,
            weights: Flux2TransformerWeights.sanitized(
                try SafetensorsShards.weights(in: transformerDirectory)),
            manifest: manifest,
            checkpointName: Flux2TransformerWeights.checkpointName(of:))
        PackedWeightLoading.castFloatParameters(of: transformer, to: activation)
        if let streaming {
            // One index over the component, read by both stacks: the dual-stream blocks under
            // the checkpoint's `attn.to_out.0` spelling, the single-stream ones as they are.
            let index = try ShardIndex(shards: SafetensorsShards.shards(in: transformerDirectory))
            transformer.doubleStream = try LayerWeightStream(
                layers: transformer.doubleBlocks,
                keyPrefix: Flux2ResidentParameters.doubleBlocks,
                index: index, depth: streaming.depth,
                checkpointName: Flux2TransformerWeights.checkpointName(of:))
            transformer.singleStream = try LayerWeightStream(
                layers: transformer.singleBlocks,
                keyPrefix: Flux2ResidentParameters.singleBlocks,
                index: index, depth: streaming.depth)
        }

        let autoencoder = Flux2Autoencoder(configuration.vae)
        try autoencoder.load(
            weights: try SafetensorsShards.weights(
                in: snapshot.appending(path: Flux2Configuration.Component.vae.directoryName)))

        Flux2ResidentParameters.eval(
            textEncoder: textEncoder, transformer: transformer, autoencoder: autoencoder,
            streamed: streaming != nil)
        loaded = Loaded(
            snapshot: snapshot, configuration: configuration, tokenizer: tokenizer,
            textEncoder: textEncoder, transformer: transformer, autoencoder: autoencoder,
            activation: activation)
    }

    /// Releases the weights and the scratch memory MLX was holding for them.
    public func unloadModel() {
        loaded = nil
        Memory.clearCache()
    }
}
