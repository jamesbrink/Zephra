import Foundation
import MLX
import MLXFast
import MLXNN
import ZephraMLX

/// One block, instantiated 32 times. A single stream: text and latents meet everywhere, not
/// just in the attention.
///
/// The shape is modulate, attend, gate back into the residual; modulate again, feed forward,
/// gate back again. Three details are 2.1's and each is silent when wrong:
///
/// - The two layer norms have **nothing learned**, which is why the checkpoint carries no
///   weights for them. Building them with an affine pair loads an initialiser's ones and zeros
///   and changes nothing, until a packed variant tries to quantize them.
/// - Modulation is `x * (1 + scale)` with **no shift**; the table has four vectors, not six.
/// - The residual gate is **`tanh(gate)`**, never the raw gate. Neither scale is gated.
///
/// The modulation arrives as an argument because the model computes it once for the whole
/// forward and every block reads the same four vectors; see `QwenImage21SharedModulation`.
final class QwenImage21TransformerBlock: Module {
    @ModuleInfo(key: "attn") var attention: QwenImage21BlockAttention
    @ModuleInfo(key: "img_mlp") var feedForward: QwenImage21SwiGLUFeedForward

    private let eps: Float

    init(dim: Int, heads: Int, headDim: Int, mlpHidden: Int, eps: Float) {
        _attention.wrappedValue = QwenImage21BlockAttention(
            dim: dim, heads: heads, headDim: headDim, eps: eps)
        _feedForward.wrappedValue = QwenImage21SwiGLUFeedForward(dim: dim, hidden: mlpHidden)
        self.eps = eps
    }

    func callAsFunction(
        _ hidden: MLXArray,
        modulation: QwenImage21SharedModulation.Parameters,
        frequencies: RotaryFrequencies,
        plan: QwenImage21AttentionPlan,
        cache: QwenImage21KVLayerCache?,
        mode: QwenImage21KVCache.Mode?,
        prefixLength: Int
    ) throws -> MLXArray {
        let attended = try attention(
            normed(hidden) * (1 + modulation.attentionScale),
            frequencies: frequencies,
            plan: plan,
            cache: cache,
            mode: mode,
            prefixLength: prefixLength)
        var stream = hidden + MLX.tanh(modulation.attentionGate) * attended

        let forwarded = feedForward(normed(stream) * (1 + modulation.mlpScale))
        stream = stream + MLX.tanh(modulation.mlpGate) * forwarded
        return stream
    }

    private func normed(_ x: MLXArray) -> MLXArray {
        MLXFast.layerNorm(x, weight: nil, bias: nil, eps: eps)
    }
}
