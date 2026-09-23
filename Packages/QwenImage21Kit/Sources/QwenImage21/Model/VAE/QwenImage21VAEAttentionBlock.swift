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

    /// The most queries attended in one pass. Each query's softmax reads only its own row of
    /// scores, so a chunk of queries against every key is exactly the whole attention's rows;
    /// what the chunk bounds is the score matrix, which at a 2K preset's 29,584 cells would
    /// be 3.5 GB in one piece, since a head this wide takes MLX's unfused path. It mattered less
    /// while a tiled decode cut the picture before this block, which it no longer does.
    static let queryChunk = 4096

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        callAsFunction(x, queryChunk: Self.queryChunk)
    }

    func callAsFunction(_ x: MLXArray, queryChunk: Int) -> MLXArray {
        let (batch, height, width, channels) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let cells = height * width
        let qkv = toQKV(norm(x)).reshaped([batch, 1, cells, 3 * channels])
        let keys = qkv[.ellipsis, channels..<(2 * channels)]
        let values = qkv[.ellipsis, (2 * channels)...]
        let scale = 1 / Float(channels).squareRoot()
        let attended: MLXArray
        if cells <= queryChunk {
            attended = MLXFast.scaledDotProductAttention(
                queries: qkv[.ellipsis, 0..<channels], keys: keys, values: values,
                scale: scale, mask: nil)
        } else {
            let chunks = stride(from: 0, to: cells, by: queryChunk).map { start in
                let chunk = MLXFast.scaledDotProductAttention(
                    queries: qkv[0..., 0..., start..<min(start + queryChunk, cells), 0..<channels],
                    keys: keys, values: values, scale: scale, mask: nil)
                eval(chunk)
                return chunk
            }
            attended = concatenated(chunks, axis: 2)
        }
        return proj(attended.reshaped([batch, height, width, channels])) + x
    }
}
