import Foundation
import MLX
import MLXNN

/// One of the tower's 27 blocks: pre-norm attention, then pre-norm feed-forward, both residual.
///
/// The norms are `LayerNorm` with an epsilon of 1e-6 and both a gain and a bias — not the
/// decoder's gain-only RMS norm. The epsilon is hard-coded in the reference's block rather than
/// read from the config, which is why it is a literal here too.
final class Qwen3VLVisionBlock: Module {
    @ModuleInfo(key: "norm1") var attentionNorm: LayerNorm
    @ModuleInfo(key: "attn") var attention: Qwen3VLVisionAttention
    @ModuleInfo(key: "norm2") var feedForwardNorm: LayerNorm
    @ModuleInfo(key: "mlp") var feedForward: Qwen3VLVisionFeedForward

    /// What the reference's `Qwen3VLVisionBlock` passes to both `nn.LayerNorm`s.
    static let normEpsilon: Float = 1e-6

    init(_ configuration: Qwen3VLTextConfiguration.Vision) {
        _attentionNorm.wrappedValue = LayerNorm(
            dimensions: configuration.hiddenSize, eps: Self.normEpsilon)
        _attention.wrappedValue = Qwen3VLVisionAttention(configuration)
        _feedForwardNorm.wrappedValue = LayerNorm(
            dimensions: configuration.hiddenSize, eps: Self.normEpsilon)
        _feedForward.wrappedValue = Qwen3VLVisionFeedForward(configuration)
    }

    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let attended = x + attention(attentionNorm(x), cos: cos, sin: sin)
        return attended + feedForward(feedForwardNorm(attended))
    }
}
