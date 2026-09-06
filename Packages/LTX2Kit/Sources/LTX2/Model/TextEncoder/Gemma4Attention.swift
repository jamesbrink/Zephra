import Foundation
import MLX
import MLXFast
import MLXNN

/// One Gemma 4 attention layer, sliding or full, shaped by `Gemma4Configuration.LayerShape`.
///
/// Three things here are Gemma 4's own and easy to lose to habit. **Scores are not scaled**:
/// the reference sets the scale to 1 and lets the query and key norms do that work. **Values
/// are normed too**, with a scale-free RMS norm per head. And on a full-attention layer with
/// `attention_k_eq_v` **the keys are the values**: there is no `v_proj` in the checkpoint, and
/// building one would leave a weight nothing fills.
final class Gemma4Attention: Module {
    @ModuleInfo(key: "q_proj") var queryProjection: Linear
    @ModuleInfo(key: "k_proj") var keyProjection: Linear
    @ModuleInfo(key: "v_proj") var valueProjection: Linear?
    @ModuleInfo(key: "o_proj") var outputProjection: Linear
    @ModuleInfo(key: "q_norm") var queryNorm: RMSNorm
    @ModuleInfo(key: "k_norm") var keyNorm: RMSNorm

    private let heads: Int
    private let keyValueHeads: Int
    private let headDim: Int
    private let eps: Float
    private let rotary: Gemma4RotaryEmbedding

    init(_ configuration: Gemma4Configuration, layer index: Int) {
        let shape = configuration.layer(at: index)
        heads = configuration.numAttentionHeads
        keyValueHeads = shape.keyValueHeads
        headDim = shape.headDim
        eps = configuration.rmsNormEps
        rotary = Gemma4RotaryEmbedding(
            headDim: shape.headDim, theta: shape.ropeTheta, rotaryFraction: shape.rotaryFraction)

        let hidden = configuration.hiddenSize
        _queryProjection.wrappedValue = Linear(hidden, heads * headDim, bias: false)
        _keyProjection.wrappedValue = Linear(hidden, keyValueHeads * headDim, bias: false)
        _valueProjection.wrappedValue =
            shape.hasValueProjection ? Linear(hidden, keyValueHeads * headDim, bias: false) : nil
        _outputProjection.wrappedValue = Linear(heads * headDim, hidden, bias: false)
        _queryNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
    }

    /// Attends over `x`, `[batch, length, hidden]`, under an additive `mask`.
    ///
    /// Order, as the reference has it: project, reshape to heads, norm each head, rotate, then
    /// attend with the heads in front. The value path norms but never rotates.
    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let (batch, length) = (x.dim(0), x.dim(1))
        let (cos, sin) = rotary.tables(length: length)

        let queries = Gemma4RotaryEmbedding.rotate(
            queryNorm(queryProjection(x).reshaped(batch, length, heads, headDim))
                .transposed(0, 2, 1, 3),
            cos: cos, sin: sin)
        let keyStates = keyProjection(x).reshaped(batch, length, keyValueHeads, headDim)
        let keys = Gemma4RotaryEmbedding.rotate(
            keyNorm(keyStates).transposed(0, 2, 1, 3), cos: cos, sin: sin)
        let valueStates =
            valueProjection?(x).reshaped(batch, length, keyValueHeads, headDim) ?? keyStates
        let values = Self.scaleFreeNorm(valueStates, eps: eps).transposed(0, 2, 1, 3)

        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: 1, mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(batch, length, heads * headDim)
        return outputProjection(attended)
    }

    /// RMS normalisation with no learned scale, which is what the values get.
    static func scaleFreeNorm(_ x: MLXArray, eps: Float) -> MLXArray {
        let wide = x.asType(.float32)
        let meanSquare = MLX.mean(wide * wide, axis: -1, keepDims: true)
        return (wide * MLX.rsqrt(meanSquare + eps)).asType(x.dtype)
    }
}
