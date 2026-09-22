import Foundation
import MLX
import MLXNN

/// The two-by-two spatial merge that turns four tower patches into one image slot, and projects
/// it onto the decoder's width.
///
/// Four of these exist in the checkpoint and they are **not all the same shape**. `merger`
/// normalises **before** the shuffle, over one patch's 1152 channels; the three
/// `deepstack_merger_list` entries normalise **after**, over the shuffled 4608. The norm's own
/// shape is the only tell — 1152 against 4608 — and getting it the wrong way round normalises
/// across four patches that should have been normalised apart, which loads cleanly and is
/// quietly wrong.
///
/// The activation between the two linears is `nn.GELU()`, the **exact** error-function one.
/// The tower's own feed-forward uses the tanh approximation instead; this file and
/// `Qwen3VLVisionFeedForward` are the two halves of that distinction.
final class Qwen3VLVisionMerger: Module, UnaryLayer {
    @ModuleInfo(key: "norm") var norm: LayerNorm
    @ModuleInfo(key: "linear_fc1") var first: Linear
    @ModuleInfo(key: "linear_fc2") var second: Linear

    private let shuffled: Int
    private let normalisesAfterShuffle: Bool

    /// - Parameter afterShuffle: True for a DeepStack merger, false for the tower's own.
    init(_ configuration: Qwen3VLTextConfiguration.Vision, afterShuffle: Bool) {
        shuffled = configuration.hiddenSize * configuration.spatialMergeSize
            * configuration.spatialMergeSize
        normalisesAfterShuffle = afterShuffle
        _norm.wrappedValue = LayerNorm(
            dimensions: afterShuffle ? shuffled : configuration.hiddenSize,
            eps: Qwen3VLVisionBlock.normEpsilon)
        _first.wrappedValue = Linear(shuffled, shuffled, bias: true)
        _second.wrappedValue = Linear(shuffled, configuration.outHiddenSize, bias: true)
    }

    /// `[patches, hidden]` in, `[patches / merge², outHidden]` out.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let shuffledFirst = normalisesAfterShuffle ? norm(x.reshaped(-1, shuffled)) : norm(x)
        return second(gelu(first(shuffledFirst.reshaped(-1, shuffled))))
    }
}
