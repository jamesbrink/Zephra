import Foundation
import MLX
import MLXNN

/// One Qwen2.5 decoder layer: pre-norm attention, then pre-norm feed-forward, both residual.
final class Qwen25DecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var attention: Qwen25Attention
    @ModuleInfo(key: "mlp") var feedForward: Qwen25FeedForward
    @ModuleInfo(key: "input_layernorm") var attentionNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var feedForwardNorm: RMSNorm

    init(_ configuration: QwenImageTextEncoderConfiguration) {
        _attention.wrappedValue = Qwen25Attention(configuration)
        _feedForward.wrappedValue = Qwen25FeedForward(configuration)
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
