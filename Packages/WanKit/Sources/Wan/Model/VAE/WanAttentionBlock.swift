import Foundation
import MLX
import MLXFast
import MLXNN

/// Single-head self-attention over the cells of one frame, in the mid block only.
///
/// Every frame attends within itself: the clip is folded into the batch, so a chunk of any
/// length runs the same way and nothing is carried between chunks. Queries, keys and values
/// come from one 1 x 1 convolution over the normalised frame, `to_qkv`, in that order along
/// the channel axis, and the head is the whole channel width, scaled by its root as the
/// reference's `scaled_dot_product_attention` scales by default. `norm` is the same RMS norm
/// as everywhere else with its gain stored one axis shorter, since the reference normalises
/// the folded `[frames, channels, height, width]` and not a clip.
final class WanAttentionBlock: Module {
    @ModuleInfo(key: "norm") var norm: WanRMSNorm
    @ModuleInfo(key: "to_qkv") var toQKV: Conv2d
    @ModuleInfo(key: "proj") var proj: Conv2d

    init(channels: Int) {
        _norm.wrappedValue = WanRMSNorm(channels: channels)
        _toQKV.wrappedValue = Conv2d(inputChannels: channels, outputChannels: 3 * channels, kernelSize: 1)
        _proj.wrappedValue = Conv2d(inputChannels: channels, outputChannels: channels, kernelSize: 1)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (batch, frames, height, width, channels) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3), x.dim(4))
        let folded = x.reshaped([batch * frames, height, width, channels])
        let qkv = toQKV(norm(folded)).reshaped([batch * frames, 1, height * width, 3 * channels])
        let attended = MLXFast.scaledDotProductAttention(
            queries: qkv[.ellipsis, 0..<channels],
            keys: qkv[.ellipsis, channels..<(2 * channels)],
            values: qkv[.ellipsis, (2 * channels)...],
            scale: 1 / Float(channels).squareRoot(),
            mask: nil)
        let projected = proj(attended.reshaped([batch * frames, height, width, channels]))
        return projected.reshaped(x.shape) + x
    }
}
