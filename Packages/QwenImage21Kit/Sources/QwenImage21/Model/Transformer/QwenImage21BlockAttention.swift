import Foundation
import MLX
import MLXFast
import MLXNN
import ZephraMLX

/// A block's attention, `attn`. One stream: text and latents are already one sequence by the
/// time it gets here.
///
/// **No biases anywhere** — the reference sets `use_bias = False` and the checkpoint carries
/// only `.weight` tensors, so building any of these with a bias makes the strict load fail on a
/// tensor nothing supplies.
///
/// The order is the reference's and each step of it matters: project, split the heads out,
/// `norm_q`/`norm_k` over **one head's width**, cast back to the value's dtype, then rotate.
/// Norming before the split would span every head at once; rotating before the norm would
/// normalise an angle.
///
/// The keys and values are then held head-major for the rest of the call, which is the layout
/// the attention kernel and the prefix cache both want.
final class QwenImage21BlockAttention: Module {
    @ModuleInfo(key: "to_q") var query: Linear
    @ModuleInfo(key: "to_k") var key: Linear
    @ModuleInfo(key: "to_v") var value: Linear
    /// The reference wraps this in a `ModuleList` with a dropout, so the checkpoint calls it
    /// `to_out.0`; `QwenImage21TransformerWeights` renames the position away.
    @ModuleInfo(key: "to_out") var output: Linear
    @ModuleInfo(key: "norm_q") var queryNorm: RMSNorm
    @ModuleInfo(key: "norm_k") var keyNorm: RMSNorm

    private let heads: Int
    private let headDim: Int
    private let scale: Float

    init(dim: Int, heads: Int, headDim: Int, eps: Float) {
        self.heads = heads
        self.headDim = headDim
        scale = 1 / sqrt(Float(headDim))
        for projection in [_query, _key, _value] {
            projection.wrappedValue = Linear(dim, heads * headDim, bias: false)
        }
        _output.wrappedValue = Linear(heads * headDim, dim, bias: false)
        for norm in [_queryNorm, _keyNorm] {
            norm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
        }
    }

    /// - Parameters:
    ///   - hidden: `[batch, tokens, dim]`, already modulated.
    ///   - frequencies: The rotary table over exactly these tokens.
    ///   - plan: The attention calls this step makes.
    ///   - cache: This layer's prefix cache, or nil to run without one.
    ///   - mode: What to do with that cache.
    ///   - prefixLength: How many leading tokens are the prefix, read under `.extract` only.
    func callAsFunction(
        _ hidden: MLXArray,
        frequencies: RotaryFrequencies,
        plan: QwenImage21AttentionPlan,
        cache: QwenImage21KVLayerCache?,
        mode: QwenImage21KVCache.Mode?,
        prefixLength: Int
    ) throws -> MLXArray {
        let (batch, tokens) = (hidden.dim(0), hidden.dim(1))
        let values = split(value(hidden))
        let dtype = values.dtype
        let queries = frequencies.rotate(
            queryNorm(split(query(hidden))).asType(dtype), computeDType: .float32
        ).transposed(0, 2, 1, 3)
        var keys = frequencies.rotate(
            keyNorm(split(key(hidden))).asType(dtype), computeDType: .float32
        ).transposed(0, 2, 1, 3)
        var heldValues = values.transposed(0, 2, 1, 3)

        if let cache {
            switch mode {
            case .extract:
                // `contiguous` over a head-major slice is what makes this a copy rather than a
                // window onto the whole prefill; see `QwenImage21KVLayerCache`.
                cache.store(
                    key: MLX.contiguous(keys[0..., 0..., ..<prefixLength]),
                    value: MLX.contiguous(heldValues[0..., 0..., ..<prefixLength]))
            case .cached:
                let held = try cache.read()
                keys = MLX.concatenated([held.key, keys], axis: 2)
                heldValues = MLX.concatenated([held.value, heldValues], axis: 2)
            case nil:
                break
            }
        }

        let attended = plan.passes.map { pass in
            MLXFast.scaledDotProductAttention(
                queries: queries[0..., 0..., pass.queries],
                keys: pass.keyLimit.map { keys[0..., 0..., ..<$0] } ?? keys,
                values: pass.keyLimit.map { heldValues[0..., 0..., ..<$0] } ?? heldValues,
                scale: scale,
                mask: pass.mask)
        }
        let joined = attended.count == 1 ? attended[0] : MLX.concatenated(attended, axis: 2)
        return output(joined.transposed(0, 2, 1, 3).reshaped([batch, tokens, heads * headDim]))
    }

    /// `[batch, tokens, heads * headDim]` into `[batch, tokens, heads, headDim]`.
    private func split(_ x: MLXArray) -> MLXArray {
        x.reshaped([x.dim(0), x.dim(1), heads, headDim])
    }
}
