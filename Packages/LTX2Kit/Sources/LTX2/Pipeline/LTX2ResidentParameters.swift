import MLX
import MLXNN

/// Which of a loaded model's parameters are read into memory at load, and which are left to
/// the streams.
///
/// One place for the two prefixes so the loader and the streams cannot disagree about where a
/// layer stack begins: a parameter under a streamed prefix that was also evaluated here would be
/// resident for the pipeline's life, which is exactly what streaming exists to avoid.
enum LTX2ResidentParameters {
    /// The module path of the text encoder's decoder layers.
    static let textEncoderLayers = "layers"
    /// The module path of the transformer's blocks.
    static let transformerBlocks = "transformer_blocks"

    /// Reads every parameter into memory, except the streamed stacks when `streamed`.
    static func eval(_ loaded: LTX2Pipeline.Loaded, streamed: Bool) {
        let always = loaded.extractor.parameters().flattenedValues()
            + loaded.connector.parameters().flattenedValues()
            + loaded.decoder.parameters().flattenedValues()
        guard streamed else {
            MLX.eval(
                always + loaded.textEncoder.parameters().flattenedValues()
                    + loaded.transformer.parameters().flattenedValues())
            return
        }
        MLX.eval(
            always + resident(of: loaded.textEncoder, outside: textEncoderLayers)
                + resident(of: loaded.transformer, outside: transformerBlocks))
    }

    /// The arrays of `module` that are not under `prefix`.
    static func resident(of module: Module, outside prefix: String) -> [MLXArray] {
        module.parameters().flattened()
            .filter { !$0.0.hasPrefix(prefix + ".") }
            .map(\.1)
    }
}
