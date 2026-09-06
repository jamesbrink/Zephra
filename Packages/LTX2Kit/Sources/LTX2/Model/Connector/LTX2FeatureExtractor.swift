import Foundation
import MLX
import MLXNN

/// Turns Gemma's 49 hidden states into one 4096-wide token stream for the video connector.
///
/// Each state is RMS-normalised per token over its own width, the 49 are laid side by side
/// hidden-major (state 0's channel 0, state 1's channel 0, ... which is the reference's
/// `stack(dim=-1).flatten(2, 3)` and the order the projection's 188160 input columns are in),
/// padded positions are zeroed, the whole is scaled by `sqrt(4096 / 3840)`, and one linear
/// projects it. That linear runs in float32 on purpose: 188160 products summed in bfloat16
/// overflow the accumulation's precision, and the port that first found this measured the
/// difference on real prompts. The pack keeps its scales float32 for the same reason.
final class LTX2FeatureExtractor: Module {
    @ModuleInfo(key: "video_aggregate_embed") var projection: Linear

    private let hiddenSize: Int
    private let stateCount: Int
    private let outputSize: Int
    private let eps: Float

    /// The checkpoint's prefix for this module's path.
    static let checkpointPrefix = "connector.text_embedding_projection."

    /// - Parameters:
    ///   - hiddenSize: The encoder's width, 3840.
    ///   - stateCount: How many hidden states arrive, 49.
    ///   - outputSize: The connector's width, 4096.
    init(hiddenSize: Int, stateCount: Int, outputSize: Int, eps: Float = 1e-6) {
        self.hiddenSize = hiddenSize
        self.stateCount = stateCount
        self.outputSize = outputSize
        self.eps = eps
        _projection.wrappedValue = Linear(hiddenSize * stateCount, outputSize, bias: true)
    }

    /// The projected features, `[batch, length, outputSize]` in float32, from `states` (each
    /// `[batch, length, hiddenSize]`) under `padding`, a `[batch, length]` mask of ones over the
    /// real tokens.
    func callAsFunction(_ states: [MLXArray], padding: MLXArray) -> MLXArray {
        precondition(states.count == stateCount, "expected \(stateCount) hidden states, got \(states.count)")
        let stacked = MLX.stacked(states.map { $0.asType(.float32) }, axis: -1)
        let variance = MLX.mean(stacked * stacked, axis: 2, keepDims: true)
        let normed = (stacked * MLX.rsqrt(variance + eps))
            .reshaped(stacked.dim(0), stacked.dim(1), hiddenSize * stateCount)
        let kept = MLX.where(
            (padding .!= 0)[0..., 0..., .newAxis], normed, MLXArray.zeros(like: normed))
        let scaled = kept * (Float(outputSize) / Float(hiddenSize)).squareRoot()
        return projection(scaled)
    }
}
