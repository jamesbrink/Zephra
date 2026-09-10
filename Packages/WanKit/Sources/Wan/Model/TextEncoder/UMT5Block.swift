import Foundation
import MLX
import MLXNN

/// One UMT5 encoder block: self-attention, then the feed-forward, each behind its own norm.
///
/// The checkpoint numbers the two halves `layer.0` and `layer.1` under one `layer` list, so
/// they are held as a pair rather than as two named properties: MLX flattens a tuple the way
/// it flattens an array, which is what puts `layer.0.SelfAttention.q.weight` on the path the
/// loader and the stream look for.
final class UMT5Block: Module {
    @ModuleInfo(key: "layer") var layer: (UMT5SelfAttentionLayer, UMT5FeedForwardLayer)

    init(_ configuration: UMT5Configuration) {
        _layer.wrappedValue = (UMT5SelfAttentionLayer(configuration), UMT5FeedForwardLayer(configuration))
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray, buckets: MLXArray) -> MLXArray {
        layer.1(layer.0(x, mask: mask, buckets: buckets))
    }
}
