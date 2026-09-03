import Foundation
import MLX
import MLXFast
import MLXNN

/// Grouped-query self-attention, Qwen3 style.
///
/// Two details separate this from the Qwen2.5 encoder Qwen-Image conditions on, and either one
/// taken from the wrong model compiles perfectly while porting the wrong architecture: **the
/// query, key, and value projections are bias-free** here, and **each head's queries and keys
/// are RMS normed** on the way past. Qwen2.5 is the exact opposite on both counts.
///
/// A head's width is stated by the configuration rather than derived. Qwen3-4B's heads are 128
/// wide against a model 2560 wide over 32 heads, so `hiddenSize / numAttentionHeads` is 80 and
/// every projection built from it would be the wrong shape.
final class Qwen3Attention: Module {
    @ModuleInfo(key: "q_proj") var queryProjection: Linear
    @ModuleInfo(key: "k_proj") var keyProjection: Linear
    @ModuleInfo(key: "v_proj") var valueProjection: Linear
    @ModuleInfo(key: "o_proj") var outputProjection: Linear
    @ModuleInfo(key: "q_norm") var queryNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var keyNorm: RMSNorm
    @ModuleInfo(key: "rope") var rope: RoPE

    private let heads: Int
    private let keyValueHeads: Int
    private let headDim: Int
    private let scale: Float

    init(_ configuration: Flux2TextEncoderConfiguration) {
        heads = configuration.numAttentionHeads
        keyValueHeads = configuration.numKeyValueHeads
        headDim = configuration.headDim
        scale = 1 / sqrt(Float(headDim))

        let hidden = configuration.hiddenSize
        _queryProjection.wrappedValue = Linear(hidden, heads * headDim, bias: false)
        _keyProjection.wrappedValue = Linear(hidden, keyValueHeads * headDim, bias: false)
        _valueProjection.wrappedValue = Linear(hidden, keyValueHeads * headDim, bias: false)
        _outputProjection.wrappedValue = Linear(heads * headDim, hidden, bias: false)

        // Over one head's width, not the model's: these normalise a head, which is why they are
        // applied between the reshape and the transpose below and not to the projection whole.
        _queryNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: configuration.rmsNormEps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: configuration.rmsNormEps)

        // Half-split rotation, the language model's convention. The image transformer rotates
        // adjacent pairs instead; the two live in this package and are not interchangeable.
        _rope.wrappedValue = RoPE(
            dimensions: headDim, traditional: false, base: configuration.ropeTheta)
    }

    /// Attends over `x`, `[batch, tokens, hidden]`, with an additive `mask`.
    ///
    /// The order is load-bearing: reshape so each head is its own row, norm each head, transpose
    /// the heads in front, then rotate. Norming after the transpose gives the same answer;
    /// norming before the reshape does not, because it would span every head at once.
    func callAsFunction(_ x: MLXArray, mask: MLXArray?) -> MLXArray {
        let (batch, tokens) = (x.dim(0), x.dim(1))

        var queries = queryNorm(
            queryProjection(x).reshaped(batch, tokens, heads, headDim)
        ).transposed(0, 2, 1, 3)
        var keys = keyNorm(
            keyProjection(x).reshaped(batch, tokens, keyValueHeads, headDim)
        ).transposed(0, 2, 1, 3)
        let values = valueProjection(x)
            .reshaped(batch, tokens, keyValueHeads, headDim).transposed(0, 2, 1, 3)

        queries = rope(queries)
        keys = rope(keys)

        // MLX's attention broadcasts the key-value heads across their query group itself.
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: scale, mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(batch, tokens, heads * headDim)

        return outputProjection(attended)
    }
}
