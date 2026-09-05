import MLX
import MLXNN

/// Which of a loaded model's parameters are read into memory at load, and which are left to
/// the streams.
///
/// One place for the two prefixes so the loader and the streams cannot disagree about where a
/// layer stack begins: a parameter under a streamed prefix that was also evaluated here would
/// be resident for the pipeline's life, which is exactly what streaming exists to avoid.
enum QwenImageResidentParameters {
    /// The module path of the text encoder's decoder layers.
    static let textEncoderLayers = "model.layers"
    /// The module path of the transformer's blocks.
    static let transformerBlocks = "transformer_blocks"

    /// Reads every parameter into memory, except the streamed stacks when `streamed`.
    static func eval(
        textEncoder: Qwen25TextEncoder,
        transformer: QwenImageTransformer,
        autoencoder: QwenImageAutoencoder,
        streamed: Bool
    ) {
        guard streamed else {
            MLX.eval(textEncoder.parameters(), transformer.parameters(), autoencoder.parameters())
            return
        }
        MLX.eval(
            resident(of: textEncoder, outside: textEncoderLayers)
                + resident(of: transformer, outside: transformerBlocks)
                + autoencoder.parameters().flattenedValues())
    }

    /// The arrays of `module` that are not under `prefix`.
    static func resident(of module: Module, outside prefix: String) -> [MLXArray] {
        module.parameters().flattened()
            .filter { !$0.0.hasPrefix(prefix + ".") }
            .map(\.1)
    }
}
