import Foundation
import MLX
import ZephraMLX

/// Getting a snapshot into memory and out again.
extension QwenImage21Pipeline {
    /// Reads the configuration, the tokenizer, and every component's weights under `snapshot`,
    /// and holds the stream in `activation` from then on.
    ///
    /// Works on a packed variant and on the raw bf16 release alike: `PackedSnapshotManifest` is
    /// nil for a release, `PackedWeightLoading` then loads the tree unchanged, and the bench and
    /// the parity suite get the same pipeline the app runs.
    ///
    /// With `streaming` the transformer's 32 blocks and the decoder's 36 layers are not read
    /// here at all: each stack is handed a `LayerWeightStream` that reads it from the shards on
    /// every pass, and only what is left — the embedding table, the shared modulation, the two
    /// input projections, the output head, the whole vision tower and the whole autoencoder —
    /// is evaluated now.
    ///
    /// **The order below is the one `LayerWeightStream` asks for and is load-bearing per
    /// component**: fill the tree, cast its float32 parameters to `activation`, attach the
    /// stream, and evaluate the resident parameters last of all. The cast is what the stream
    /// keeps handing back on every later pass — a packer writes scales float32 and MLX's
    /// quantized matmul takes its output dtype from them, so a raw node would widen the whole
    /// stream from the second layer on. Evaluating a tree before its stream is attached reads
    /// the model in, which is the thing being avoided.
    public func loadModel(
        at snapshot: URL,
        activation: DType = QwenImage21TransformerPrecision.defaultActivation,
        streaming: QwenImage21Streaming? = nil,
        onProgress: (QwenImage21GenerationProgress) -> Void = { _ in }
    ) throws {
        onProgress(QwenImage21GenerationProgress(stage: .loading))
        let configuration = try QwenImage21Configuration(readingFrom: snapshot)
        // Read for its refusal and nothing else: a Qwen-Image 2512 release has the same five
        // directories with the same file names inside them, and the class names are what tell
        // the two apart before a weight is touched. Nil for a packed variant, which carries none.
        _ = try QwenImage21Configuration.modelIndex(in: snapshot)
        let manifest = try PackedSnapshotManifest.read(from: snapshot)
        let tokenizer = try QwenImage21Tokenizer(snapshot: snapshot)

        let (model, tower) = try loadTextEncoder(
            at: snapshot, configuration: configuration.textEncoder, manifest: manifest,
            activation: activation, streaming: streaming)
        let transformer = try loadTransformer(
            at: snapshot, configuration: configuration.transformer, manifest: manifest,
            activation: activation, streaming: streaming)

        // Plainly, and in float32: the release ships it there, a bfloat16 decode of a
        // 64-channel latent bands, and the decode is a few seconds of a run either way.
        let autoencoder = QwenImage21Autoencoder(configuration.vae)
        try autoencoder.load(
            weights: try SafetensorsShards.weights(
                in: snapshot.appending(
                    path: QwenImage21Configuration.Component.vae.directoryName)))

        QwenImage21ResidentParameters.eval(
            model: model, tower: tower, transformer: transformer, autoencoder: autoencoder,
            streamed: streaming != nil)
        loaded = Loaded(
            snapshot: snapshot, configuration: configuration, tokenizer: tokenizer,
            encoder: QwenImage21PromptEncoder(
                model: model, tower: tower, configuration: configuration.textEncoder,
                processor: configuration.processor),
            transformer: transformer, autoencoder: autoencoder,
            normalization: QwenImage21LatentNormalization(configuration.vae),
            rope: QwenImage21Rope(axesDim: configuration.transformer.axesDimsRope),
            activation: activation)
    }

    /// Releases the weights and the scratch memory MLX was holding for them.
    public func unloadModel() {
        loaded = nil
        Memory.clearCache()
    }

    /// The decoder stack and the vision tower, which the release ships as one component.
    ///
    /// One directory, two models and a tensor neither loads: `model.language_model.*` is the
    /// 36-layer decoder, `model.visual.*` is the 27-block tower, and `lm_head.weight` beside
    /// them is 1.24 GB that `Qwen3VLTextWeights.sanitized` drops by name. The tower is
    /// **always built and never streamed**: a run with no reference picture never calls it, and
    /// one with a picture calls it once.
    private func loadTextEncoder(
        at snapshot: URL,
        configuration: Qwen3VLTextConfiguration,
        manifest: PackedSnapshotManifest?,
        activation: DType,
        streaming: QwenImage21Streaming?
    ) throws -> (Qwen3VLLanguageModel, Qwen3VLVisionTower) {
        let directory = snapshot.appending(
            path: QwenImage21Configuration.Component.textEncoder.directoryName)
        let weights = try SafetensorsShards.weights(in: directory)

        let model = Qwen3VLLanguageModel(configuration.text)
        try PackedWeightLoading.load(
            into: model, weights: Qwen3VLTextWeights.sanitized(weights), manifest: manifest,
            checkpointName: Qwen3VLTextWeights.checkpointName(of:))
        PackedWeightLoading.castFloatParameters(of: model, to: activation)
        if let streaming {
            model.stream = try LayerWeightStream(
                layers: model.layers,
                keyPrefix: QwenImage21ResidentParameters.textEncoderLayers,
                index: ShardIndex(shards: SafetensorsShards.shards(in: directory)),
                depth: streaming.depth,
                checkpointName: Qwen3VLTextWeights.checkpointName(of:))
        }

        let tower = Qwen3VLVisionTower(configuration.vision)
        try PackedWeightLoading.load(
            into: tower, weights: Qwen3VLVisionWeights.sanitized(weights), manifest: manifest,
            checkpointName: Qwen3VLVisionWeights.checkpointName(of:))
        PackedWeightLoading.castFloatParameters(of: tower, to: activation)
        return (model, tower)
    }

    /// The rectified-flow transformer, with its 32 blocks streamed or held.
    private func loadTransformer(
        at snapshot: URL,
        configuration: QwenImage21TransformerConfiguration,
        manifest: PackedSnapshotManifest?,
        activation: DType,
        streaming: QwenImage21Streaming?
    ) throws -> QwenImage21Transformer {
        let directory = snapshot.appending(
            path: QwenImage21Configuration.Component.transformer.directoryName)
        let transformer = QwenImage21Transformer(configuration)
        try PackedWeightLoading.load(
            into: transformer,
            weights: QwenImage21TransformerWeights.sanitized(
                try SafetensorsShards.weights(in: directory)),
            manifest: manifest,
            checkpointName: QwenImage21TransformerWeights.checkpointName(of:))
        PackedWeightLoading.castFloatParameters(of: transformer, to: activation)
        if let streaming {
            transformer.blockStream = try LayerWeightStream(
                layers: transformer.blocks,
                keyPrefix: QwenImage21ResidentParameters.transformerBlocks,
                index: try ShardIndex(shards: SafetensorsShards.shards(in: directory)),
                depth: streaming.depth,
                checkpointName: QwenImage21TransformerWeights.checkpointName(of:))
        }
        return transformer
    }
}
