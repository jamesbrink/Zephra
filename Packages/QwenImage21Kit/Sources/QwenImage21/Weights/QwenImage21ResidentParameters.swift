import MLX
import MLXNN

/// Which of a loaded model's parameters are read into memory at load, and which are left to the
/// streams.
///
/// One place for the two prefixes, so the loader and the streams cannot disagree about where a
/// stack begins: a parameter under a streamed prefix that was also evaluated here would be
/// resident for the pipeline's life, which is exactly what streaming exists to avoid.
///
/// The prefixes are **module paths**. For the transformer that is the checkpoint's own name
/// too; for the decoder stack the checkpoint puts `model.language_model.` in front of it, which
/// is `Qwen3VLTextWeights.checkpointName(of:)`'s whole job and why the stream is handed it.
enum QwenImage21ResidentParameters {
    /// The module path of the transformer's 32 blocks.
    static let transformerBlocks = "transformer_blocks"
    /// The module path of the decoder's 36 layers, from `Qwen3VLLanguageModel`'s own root.
    static let textEncoderLayers = "layers"

    /// Reads every parameter into memory, except the streamed stacks when `streamed`.
    ///
    /// **Last of all**, after each tree has been filled, cast and had its stream attached.
    /// Evaluating a stack before its stream is attached reads the whole model in, which is the
    /// thing streaming exists to avoid.
    ///
    /// The vision tower and the autoencoder never stream. The tower runs once per reference
    /// picture — a run with none never touches it — and the autoencoder once per generation,
    /// and between them they are a fraction of what the two stacks hold.
    static func eval(
        model: Qwen3VLLanguageModel,
        tower: Qwen3VLVisionTower,
        transformer: QwenImage21Transformer,
        autoencoder: QwenImage21Autoencoder,
        streamed: Bool
    ) {
        let always =
            autoencoder.parameters().flattenedValues() + tower.parameters().flattenedValues()
        guard streamed else {
            MLX.eval(
                always + model.parameters().flattenedValues()
                    + transformer.parameters().flattenedValues())
            return
        }
        MLX.eval(
            always + resident(of: model, outside: [textEncoderLayers])
                + resident(of: transformer, outside: [transformerBlocks]))
    }

    /// The arrays of `module` that lie under none of `prefixes`.
    static func resident(of module: Module, outside prefixes: [String]) -> [MLXArray] {
        module.parameters().flattened()
            .filter { key, _ in !prefixes.contains { key.hasPrefix($0 + ".") } }
            .map(\.1)
    }
}
