import MLX
import MLXNN

/// Which of a loaded model's parameters are read into memory at load, and which are left to the
/// streams.
///
/// One place for the three prefixes, so the loader and the streams cannot disagree about where a
/// stack begins: a parameter under a streamed prefix that was also evaluated here would be
/// resident for the pipeline's life, which is exactly what streaming exists to avoid.
///
/// The prefixes are module paths, which for klein are the checkpoint's own names too. The one
/// rename, the dual-stream block's `attn.to_out.0`, is inside a block rather than at its head,
/// so a stack begins at the same name either way.
enum Flux2ResidentParameters {
    /// The module path of the encoder's decoder layers, from the encoder's own root.
    static let textEncoderLayers = "model.layers"
    /// The module path of the five dual-stream blocks.
    static let doubleBlocks = "transformer_blocks"
    /// The module path of the twenty single-stream blocks.
    static let singleBlocks = "single_transformer_blocks"

    /// Reads every parameter into memory, except the streamed stacks when `streamed`.
    ///
    /// The autoencoder never streams: a picture is one pass through it, and its weights are a
    /// fraction of what the three stacks hold.
    static func eval(
        textEncoder: Qwen3TextEncoder,
        transformer: Flux2Transformer,
        autoencoder: Flux2Autoencoder,
        streamed: Bool
    ) {
        let always = autoencoder.parameters().flattenedValues()
        guard streamed else {
            MLX.eval(
                always + textEncoder.parameters().flattenedValues()
                    + transformer.parameters().flattenedValues())
            return
        }
        MLX.eval(
            always + resident(of: textEncoder, outside: [textEncoderLayers])
                + resident(of: transformer, outside: [doubleBlocks, singleBlocks]))
    }

    /// The arrays of `module` that lie under none of `prefixes`.
    static func resident(of module: Module, outside prefixes: [String]) -> [MLXArray] {
        module.parameters().flattened()
            .filter { key, _ in !prefixes.contains { key.hasPrefix($0 + ".") } }
            .map(\.1)
    }
}
