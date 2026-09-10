import Foundation
import MLX
import MLXNN
import ZephraMLX

/// The UMT5-XXL encoder Wan 2.2 conditions on: the token table, 24 blocks, and the final norm,
/// answering the last hidden state.
///
/// The module tree is the checkpoint's, name for name: `shared.weight` for the token table,
/// `encoder.block.N.layer.{0,1}...` for the blocks, `encoder.final_layer_norm.weight`. Nothing
/// is renamed on the way in, so the loader and the stream read the tensors by their own names
/// with `blocksKeyPrefix` as the stack's path.
///
/// What is shared across the blocks is built once per pass: the additive padding mask, and
/// the table of relative position buckets every layer gathers its own bias with.
final class UMT5TextEncoder: Module {
    @ModuleInfo(key: "shared") var shared: Embedding
    @ModuleInfo(key: "encoder") var encoder: UMT5EncoderStack

    /// Set when the blocks' weights are read from disk on each pass rather than held.
    var stream: LayerWeightStream<UMT5Block>?

    let configuration: UMT5Configuration

    /// The module path of the block stack, for a `LayerWeightStream` over `layers`.
    static let blocksKeyPrefix = "encoder.block"

    /// The blocks, in the order they run.
    var layers: [UMT5Block] { encoder.block }

    init(_ configuration: UMT5Configuration) {
        self.configuration = configuration
        _shared.wrappedValue = Embedding(
            embeddingCount: configuration.vocabSize, dimensions: configuration.dModel)
        _encoder.wrappedValue = UMT5EncoderStack(configuration)
    }

    /// The last hidden state for `tokens`, `[batch, length]`, under `padding`, a
    /// `[batch, length]` mask of ones over the real tokens: `[batch, length, dModel]`, normed.
    ///
    /// Padded positions are computed too, as the reference computes them; they attend to the
    /// real tokens only and are finite, and what is done with them is the caller's decision.
    func lastHiddenState(_ tokens: MLXArray, padding: MLXArray) throws -> MLXArray {
        var x = shared(tokens)
        let mask = UMT5AttentionMask.additive(padding: padding, dtype: x.dtype)
        let buckets = UMT5RelativePositionBucket.table(
            length: tokens.dim(1),
            buckets: configuration.relativeAttentionNumBuckets,
            maxDistance: configuration.relativeAttentionMaxDistance)
        if let stream {
            try stream.run { block in
                x = block(x, mask: mask, buckets: buckets)
                return [x]
            }
        } else {
            for block in layers {
                x = block(x, mask: mask, buckets: buckets)
            }
        }
        return encoder.finalLayerNorm(x)
    }
}
