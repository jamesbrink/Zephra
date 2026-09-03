import Foundation
import MLX
import MLXNN

/// One Qwen3 decoder layer: pre-norm attention, then pre-norm feed-forward, both residual.
///
/// The names are the checkpoint's, so the weights load by their own paths with no remapping
/// table to drift out of date.
final class Qwen3DecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var attention: Qwen3Attention
    @ModuleInfo(key: "mlp") var feedForward: Qwen3FeedForward
    @ModuleInfo(key: "input_layernorm") var attentionNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var feedForwardNorm: RMSNorm

    init(_ configuration: Flux2TextEncoderConfiguration) {
        _attention.wrappedValue = Qwen3Attention(configuration)
        _feedForward.wrappedValue = Qwen3FeedForward(configuration)
        _attentionNorm.wrappedValue = RMSNorm(
            dimensions: configuration.hiddenSize, eps: configuration.rmsNormEps)
        _feedForwardNorm.wrappedValue = RMSNorm(
            dimensions: configuration.hiddenSize, eps: configuration.rmsNormEps)
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray?) -> MLXArray {
        let attended = x + attention(attentionNorm(x), mask: mask)
        return attended + feedForward(feedForwardNorm(attended))
    }
}
