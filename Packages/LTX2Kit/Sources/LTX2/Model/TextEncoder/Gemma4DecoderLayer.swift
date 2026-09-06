import Foundation
import MLX
import MLXNN

/// One Gemma 4 decoder layer: sandwich-normed attention, sandwich-normed feed-forward, and a
/// learned scalar on the way out.
///
/// Four norms, not two. Each sub-layer is normed on the way in *and* on the way out before the
/// residual add, which is Gemma's shape since the second generation; and the whole layer's
/// output is multiplied by `layer_scalar`, a one-element tensor the checkpoint carries per
/// layer. Every one of these is a real weight here, not a one, and the fixture randomises them.
final class Gemma4DecoderLayer: Module {
    @ModuleInfo(key: "self_attn") var attention: Gemma4Attention
    @ModuleInfo(key: "mlp") var feedForward: Gemma4FeedForward
    @ModuleInfo(key: "input_layernorm") var attentionInputNorm: RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var attentionOutputNorm: RMSNorm
    @ModuleInfo(key: "pre_feedforward_layernorm") var feedForwardInputNorm: RMSNorm
    @ModuleInfo(key: "post_feedforward_layernorm") var feedForwardOutputNorm: RMSNorm
    @ParameterInfo(key: "layer_scalar") var layerScalar: MLXArray

    init(_ configuration: Gemma4Configuration, layer index: Int) {
        let hidden = configuration.hiddenSize
        let eps = configuration.rmsNormEps
        _attention.wrappedValue = Gemma4Attention(configuration, layer: index)
        _feedForward.wrappedValue = Gemma4FeedForward(configuration)
        _attentionInputNorm.wrappedValue = RMSNorm(dimensions: hidden, eps: eps)
        _attentionOutputNorm.wrappedValue = RMSNorm(dimensions: hidden, eps: eps)
        _feedForwardInputNorm.wrappedValue = RMSNorm(dimensions: hidden, eps: eps)
        _feedForwardOutputNorm.wrappedValue = RMSNorm(dimensions: hidden, eps: eps)
        _layerScalar.wrappedValue = MLXArray.ones([1])
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let attended = x + attentionOutputNorm(attention(attentionInputNorm(x), mask: mask))
        let fed = attended + feedForwardOutputNorm(feedForward(feedForwardInputNorm(attended)))
        return fed * layerScalar.asType(fed.dtype)
    }
}
