import Foundation
import MLX
import MLXNN

/// `WanRMS_norm`: each location scaled to unit length over its channels, times the square
/// root of the channel count, times a learned gain.
///
/// The reference spells it `F.normalize(x, dim=channels) * sqrt(dim) * gamma`, and the root
/// mean square norm is the same arithmetic: dividing by the root mean of the squares is
/// dividing by the norm and multiplying by the root of the count. The one difference is at the
/// origin, where `F.normalize` clamps the norm at 1e-12 and the fused kernel adds an epsilon
/// inside the root; both leave a real activation untouched. No bias: the checkpoint's norms are
/// built with `bias=False` and carry only `gamma`.
///
/// The checkpoint stores the gain broadcastable over a channels-first tensor, `[dim, 1, 1, 1]`
/// or `[dim, 1, 1]` in the attention block; the tree holds it flat, `[dim]`, for the last axis
/// of a channels-last activation, and `WanVAEWeights` flattens it at load.
final class WanRMSNorm: Module {
    @ParameterInfo(key: "gamma") var gamma: MLXArray

    static let epsilon: Float = 1e-12

    init(channels: Int) {
        _gamma.wrappedValue = MLXArray.ones([channels])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLX.rmsNorm(x, weight: gamma, eps: Self.epsilon)
    }
}
