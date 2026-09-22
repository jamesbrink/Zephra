import Foundation
import MLX
import MLXFast
import MLXNN

/// Single-head self-attention over the cells of the picture, in the mid block only.
///
/// `attn_scales` is empty in every published configuration, so the mid blocks' one layer each
/// is the whole of the attention in this autoencoder. Queries, keys and values come from one
/// 1 x 1 convolution over the normalised picture, `to_qkv`, in that order along the channel
/// axis, and the head is the whole channel width, scaled by its root as the reference's
/// `scaled_dot_product_attention` scales by default.
///
/// `norm` is the same norm as everywhere else with its gain stored one axis shorter, because
/// the reference builds this one with `images=True`: it normalises a folded
/// `[frames, channels, height, width]` here and a clip-shaped tensor elsewhere. Both are the
/// channel axis and both flatten to `[dim]`.
final class QwenImage21VAEAttentionBlock: Module {
    @ModuleInfo(key: "norm") var norm: QwenImage21VAENorm
    @ModuleInfo(key: "to_qkv") var toQKV: Conv2d
    @ModuleInfo(key: "proj") var proj: Conv2d

    init(channels: Int) {
        _norm.wrappedValue = QwenImage21VAENorm(channels: channels)
        _toQKV.wrappedValue = Conv2d(
            inputChannels: channels, outputChannels: 3 * channels, kernelSize: 1)
        _proj.wrappedValue = Conv2d(
            inputChannels: channels, outputChannels: channels, kernelSize: 1)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (batch, height, width, channels) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let qkv = toQKV(norm(x)).reshaped([batch, 1, height * width, 3 * channels])
        let attended = MLXFast.scaledDotProductAttention(
            queries: qkv[.ellipsis, 0..<channels],
            keys: qkv[.ellipsis, channels..<(2 * channels)],
            values: qkv[.ellipsis, (2 * channels)...],
            scale: 1 / Float(channels).squareRoot(),
            mask: nil)
        return proj(attended.reshaped([batch, height, width, channels])) + x
    }
}
