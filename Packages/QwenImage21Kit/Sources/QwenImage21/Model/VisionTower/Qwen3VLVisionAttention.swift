import Foundation
import MLX
import MLXFast
import MLXNN

/// Self-attention in a tower block: one **fused** `qkv` projection **with bias**, then `proj`.
///
/// Both differences from the decoder's attention are visible in the weight list and neither is
/// optional: `attn.qkv.weight` is `[3456, 1152]` with a `[3456]` bias, and `attn.proj` has a
/// bias too. There is no grouped-query split here — every head is a full head — and no
/// normalisation of queries or keys.
///
/// Attention is over the whole picture and is not causal. The reference splits the sequence by
/// `cu_seqlens` so that several pictures packed into one tensor do not attend across each
/// other; this kit encodes one picture per call, so the split is the whole sequence and the
/// mask is nothing at all.
final class Qwen3VLVisionAttention: Module {
    @ModuleInfo(key: "qkv") var fused: Linear
    @ModuleInfo(key: "proj") var projection: Linear

    private let heads: Int
    private let headDim: Int
    private let scale: Float

    init(_ configuration: Qwen3VLTextConfiguration.Vision) {
        heads = configuration.numHeads
        headDim = configuration.headDim
        scale = 1 / sqrt(Float(headDim))
        _fused.wrappedValue = Linear(
            configuration.hiddenSize, configuration.hiddenSize * 3, bias: true)
        _projection.wrappedValue = Linear(
            configuration.hiddenSize, configuration.hiddenSize, bias: true)
    }

    /// `[patches, hidden]` in and out, rotated by the tower's own tables.
    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let patches = x.dim(0)
        let parts = fused(x).reshaped(patches, 3, heads, headDim).transposed(1, 0, 2, 3)

        let queries = Qwen3VLVisionRotary.applied(parts[0], cos: cos, sin: sin)
        let keys = Qwen3VLVisionRotary.applied(parts[1], cos: cos, sin: sin)
        let values = parts[2]

        let attended = MLXFast.scaledDotProductAttention(
            queries: queries.transposed(1, 0, 2).expandedDimensions(axis: 0),
            keys: keys.transposed(1, 0, 2).expandedDimensions(axis: 0),
            values: values.transposed(1, 0, 2).expandedDimensions(axis: 0),
            scale: scale, mask: nil
        )
        .squeezed(axis: 0).transposed(1, 0, 2).reshaped(patches, heads * headDim)

        return projection(attended)
    }
}
