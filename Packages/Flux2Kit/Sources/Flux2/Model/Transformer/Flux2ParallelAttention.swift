import Foundation
import MLX
import MLXFast
import MLXNN

/// A single-stream block's attention and feed-forward, run side by side out of one pair of
/// matrices.
///
/// This is the ViT-22B "parallel" arrangement: the queries, keys, values and both halves of the
/// gated feed-forward all come out of `to_qkv_mlp_proj`, and the attention's output and the
/// feed-forward's are concatenated and projected back by one `to_out`. Twenty of these are most
/// of the model.
///
/// The split is by width, `3 * dim` of attention then `2 * mlpHidden` of feed-forward, and the
/// order is fixed by the checkpoint's row order. There is no shape that catches getting it
/// wrong.
final class Flux2ParallelAttention: Module {
    @ModuleInfo(key: "to_qkv_mlp_proj") var fusedInput: Linear
    @ModuleInfo(key: "to_out") var fusedOutput: Linear
    @ModuleInfo(key: "norm_q") var queryNorm: RMSNorm
    @ModuleInfo(key: "norm_k") var keyNorm: RMSNorm

    private let heads: Int
    private let headDim: Int
    private let mlpHidden: Int
    private let scale: Float

    init(dim: Int, heads: Int, headDim: Int, mlpHidden: Int, eps: Float) {
        self.heads = heads
        self.headDim = headDim
        self.mlpHidden = mlpHidden
        scale = 1 / sqrt(Float(headDim))

        let inner = heads * headDim
        _fusedInput.wrappedValue = Linear(dim, inner * 3 + mlpHidden * 2, bias: false)
        _fusedOutput.wrappedValue = Linear(inner + mlpHidden, dim, bias: false)
        _queryNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
        _keyNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: eps)
    }

    /// Attends over the whole sequence and gates the feed-forward, in one pass.
    ///
    /// `frequencies` covers the concatenated `[text, image]` sequence, which by this point is
    /// what `x` is.
    ///
    /// A note on `to_out`, for whoever bumps mlx-swift. Up to and including 0.31.6, MLX
    /// JIT-compiles the split-K steel GEMM with the wrong dtype on M5-class GPUs
    /// (ml-explore/mlx#3797, fixed by #3810). The kernel is dispatched only for half precision
    /// and only when the contraction is long — K at least 10240 — and this projection's K is
    /// `3072 + 9216 = 12288`, so it sits squarely inside the window at the token counts a
    /// 512-to-896-pixel generation produces. The stream runs in bfloat16 by default, because a
    /// float32 stream puts the attention over a 4096-token image off the fused kernel and costs
    /// a 2 GB score matrix per block; on hardware the bug reaches, `ZEPHRA_DIT_DTYPE=f32` runs
    /// the stream in float32 and never dispatches the broken kernel. See
    /// `Flux2TransformerPrecision`. `TransformerParityTests` runs a bfloat16 probe at this exact
    /// shape so a bump reports the state of the bug instead of producing quiet garbage.
    func callAsFunction(_ x: MLXArray, frequencies: RotaryFrequencies) -> MLXArray {
        let (batch, tokens) = (x.shape[0], x.shape[1])
        let inner = heads * headDim

        let projected = fusedInput(x)
        let attentionPart = projected[.ellipsis, ..<(inner * 3)]
        let feedForwardPart = projected[.ellipsis, (inner * 3)...]

        func head(_ index: Int) -> MLXArray {
            attentionPart[.ellipsis, (index * inner)..<((index + 1) * inner)]
                .reshaped([batch, tokens, heads, headDim])
        }
        let queries = frequencies.rotate(queryNorm(head(0))).transposed(0, 2, 1, 3)
        let keys = frequencies.rotate(keyNorm(head(1))).transposed(0, 2, 1, 3)
        let values = head(2).transposed(0, 2, 1, 3)

        let attended = MLXFast.scaledDotProductAttention(
            queries: queries, keys: keys, values: values, scale: scale, mask: nil
        )
        .transposed(0, 2, 1, 3)
        .reshaped([batch, tokens, inner])

        return fusedOutput(
            MLX.concatenated([attended, Flux2FeedForward.swiglu(feedForwardPart)], axis: -1))
    }
}
