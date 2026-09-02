// ZEPHRA-PATCH: the 8-bit repository stores every non-packed transformer tensor as F32,
// including the quantization scales, so the whole DiT ran in float32. Apple GPUs reach their
// matmul and attention peak in bfloat16, and float32 activations cost twice the bandwidth.
// Reference Z-Image inference is bfloat16, so this restores the intended precision rather
// than trading accuracy for speed.
import Foundation
import MLX
import MLXNN

/// The dtype the transformer's own arithmetic runs in.
public enum ZImageTransformerPrecision {
  /// bfloat16 unless `ZEPHRA_DIT_DTYPE=f32` asks for the old float32 behaviour, which exists
  /// so a suspected precision regression can be bisected without a rebuild.
  public static let activation: DType =
    ProcessInfo.processInfo.environment["ZEPHRA_DIT_DTYPE"] == "f32" ? .float32 : .bfloat16
}

extension ZImageTransformer2DModel {
  /// Rewrites every float32 parameter to `dtype`, leaving packed quantized weights alone.
  ///
  /// Packed weights are `uint32` and carry bit-fields rather than numbers, so casting them
  /// would destroy them. Their `scales` and `biases` are ordinary floats and do get cast,
  /// which is where most of the saving is: at group size 32 they are a sixteenth of the
  /// parameter count and were costing four bytes each.
  public func castFloatParameters(to dtype: DType) {
    guard dtype != .float32 else { return }
    update(parameters: parameters().mapValues { $0.dtype == .float32 ? $0.asType(dtype) : $0 })
    MLX.eval(parameters())
  }
}
