import Foundation
import MLX
import MLXNN

/// The first half of a UMT5 block, `layer.0` in the checkpoint: a scale-only RMS norm, the
/// attention, and the residual add.
///
/// Pre-norm, and only pre-norm: the residual stream is normed on the way into the attention
/// and never on the way out, which is the shape T5 has always had.
final class UMT5SelfAttentionLayer: Module {
    @ModuleInfo(key: "SelfAttention") var attention: UMT5Attention
    @ModuleInfo(key: "layer_norm") var norm: RMSNorm

    init(_ configuration: UMT5Configuration) {
        _attention.wrappedValue = UMT5Attention(configuration)
        _norm.wrappedValue = RMSNorm(dimensions: configuration.dModel, eps: configuration.layerNormEpsilon)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray, buckets: MLXArray) -> MLXArray {
        x + attention(norm(x), mask: mask, buckets: buckets)
    }
}
