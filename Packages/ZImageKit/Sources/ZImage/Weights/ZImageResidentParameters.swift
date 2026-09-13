// ZEPHRA-PATCH: streaming the weights from disk. New file: the one place that says where each
// streamed stack begins, and the one place a load is evaluated. See VENDORED.md.
import MLX
import MLXNN

/// Which of a loaded model's parameters are read into memory at load, and which are left to the
/// streams.
///
/// One place for the prefixes so the loader and the streams cannot disagree about where a layer
/// stack begins: a parameter under a streamed prefix that was also evaluated here would be
/// resident for the pipeline's life, which is exactly what streaming exists to avoid.
enum ZImageResidentParameters {
  /// The transformer's main stack, in both the module tree and the checkpoint.
  static let mainLayers = "layers"
  /// The stack that refines the noise stream, in both the module tree and the checkpoint.
  static let noiseRefiner = "noise_refiner"
  /// The stack that refines the caption stream, in both the module tree and the checkpoint.
  static let contextRefiner = "context_refiner"
  /// Every stack of the transformer that streams.
  static let transformerStacks = [mainLayers, noiseRefiner, contextRefiner]
  /// The module path of the text encoder's decoder layers, from `QwenTextEncoder`.
  static let textEncoderLayers = "encoder.layers"
  /// What the text encoder's checkpoint calls the same stack. The two differ here and nowhere
  /// else: `ZImageWeightsMapping.textEncoderMapping` rewrites `model.` to `encoder.` on the way
  /// in, and a stream reads the shards by the checkpoint's own names.
  static let textEncoderCheckpointLayers = "model.layers"

  /// Reads every parameter into memory, except the streamed stacks when `streamed`.
  ///
  /// Called once, last, after the streams are attached: a stack evaluated before its stream is
  /// attached would read the whole model in, which is the one thing streaming must not do.
  static func eval(
    transformer: ZImageTransformer2DModel,
    textEncoder: QwenTextEncoder,
    vae: AutoencoderKL,
    streamed: Bool
  ) {
    let always = vae.parameters().flattenedValues()
    guard streamed else {
      MLX.eval(
        always + transformer.parameters().flattenedValues()
          + textEncoder.parameters().flattenedValues())
      return
    }
    MLX.eval(
      always + resident(of: transformer, outside: transformerStacks)
        + resident(of: textEncoder, outside: [textEncoderLayers]))
  }

  /// The arrays of `module` that are under none of `prefixes`.
  static func resident(of module: Module, outside prefixes: [String]) -> [MLXArray] {
    module.parameters().flattened()
      .filter { entry in !prefixes.contains { entry.0.hasPrefix($0 + ".") } }
      .map(\.1)
  }
}
