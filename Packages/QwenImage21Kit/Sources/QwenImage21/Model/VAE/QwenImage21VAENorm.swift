import Foundation
import MLX
import MLXNN

/// `QwenImage21RMS_norm`: each location scaled to unit length over its channels, times the
/// square root of the channel count, times a learned gain.
///
/// The reference spells it `F.normalize(x, dim=1) * sqrt(dim) * gamma`, and dividing by the
/// root mean of the squares is the same arithmetic: dividing by the norm and multiplying by
/// the root of the count. The one difference is at the origin, where `F.normalize` clamps the
/// norm at 1e-12 and the fused kernel adds that epsilon inside the root; neither touches a
/// real activation. There is no bias: the reference builds every one of these with
/// `bias=False`, where `self.bias` is the Python scalar `0.0`, and the checkpoint carries only
/// `gamma`.
///
/// The checkpoint stores the gain broadcastable over a channels-first tensor: `[dim, 1, 1, 1]`
/// in the residual blocks and at `norm_out`, which the reference builds with `images=False`,
/// and `[dim, 1, 1]` in the attention block, which it builds with `images=True` because it
/// normalises a folded `[frames, channels, height, width]` there. Both normalise the channel
/// axis and both flatten to `[dim]` for the last axis of a channels-last activation, which is
/// what `QwenImage21VAEWeights` does at load, so one type serves both.
final class QwenImage21VAENorm: Module {
    @ParameterInfo(key: "gamma") var gamma: MLXArray

    /// `F.normalize`'s clamp on the norm, used here as the epsilon inside the root.
    static let epsilon: Float = 1e-12

    init(channels: Int) {
        _gamma.wrappedValue = MLXArray.ones([channels])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        MLX.rmsNorm(x, weight: gamma, eps: Self.epsilon)
    }
}
