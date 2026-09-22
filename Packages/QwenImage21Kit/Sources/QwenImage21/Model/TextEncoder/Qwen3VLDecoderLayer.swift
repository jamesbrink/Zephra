import Foundation
import MLX
import MLXNN

/// One Qwen3-VL decoder layer: pre-norm attention, then pre-norm feed-forward, both residual.
///
/// The names are the checkpoint's, so the weights load by their own paths with no remapping
/// table to drift out of date. `Qwen3VLTextWeights` strips the `model.language_model.` prefix
/// and nothing else.
final class Qwen3VLDecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var attention: Qwen3VLAttention
    @ModuleInfo(key: "mlp") var feedForward: Qwen3VLFeedForward
    @ModuleInfo(key: "input_layernorm") var attentionNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var feedForwardNorm: RMSNorm

    init(_ configuration: Qwen3VLTextConfiguration.Text) {
        _attention.wrappedValue = Qwen3VLAttention(configuration)
        _feedForward.wrappedValue = Qwen3VLFeedForward(configuration)
        _attentionNorm.wrappedValue = RMSNorm(
            dimensions: configuration.hiddenSize, eps: configuration.rmsNormEps)
        _feedForwardNorm.wrappedValue = RMSNorm(
            dimensions: configuration.hiddenSize, eps: configuration.rmsNormEps)
    }

    func callAsFunction(_ x: MLXArray, cos: MLXArray, sin: MLXArray, mask: MLXArray?) -> MLXArray
    {
        let attended = x + attention(attentionNorm(x), cos: cos, sin: sin, mask: mask)
        return attended + feedForward(feedForwardNorm(attended))
    }
}
