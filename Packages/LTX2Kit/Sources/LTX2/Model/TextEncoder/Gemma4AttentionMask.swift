import Foundation
import MLX

/// The additive masks a left-padded prompt needs: causal, blind to the padding, and on a
/// sliding layer blind to anything further back than the window.
///
/// LTX-2.5 pads every prompt to 1024 tokens on the left and hands the text encoder the padding
/// mask; the reference then builds Gemma's own per-layer masks from it, a causal one for the
/// full layers and a windowed one for the sliding layers. At 1024 tokens the window of 1024
/// admits every causal key, so the two are the same table on the real model; they differ on a
/// doll's house, which is what the parity fixture exercises, so both are built.
enum Gemma4AttentionMask {
    /// Both masks for one prompt, each `[batch, 1, length, length]`, from a `[batch, length]`
    /// mask of ones over the real tokens.
    static func masks(padding: MLXArray, slidingWindow: Int, dtype: DType)
        -> (full: MLXArray, sliding: MLXArray)
    {
        let length = padding.dim(1)
        let positions = MLXArray(Array(0..<Int32(length)))
        let rows = positions[0..., .newAxis]
        let columns = positions[.newAxis, 0...]
        // A key is blocked when it is in the query's future or is padding.
        let padded = (padding .== 0)[0..., .newAxis, .newAxis, 0...]
        let future = (columns .> rows)[.newAxis, .newAxis, 0..., 0...]
        // The reference's window: a key is visible while `key > query - window`, so a window of
        // `w` sees the query and the `w - 1` tokens before it.
        let tooFar = (columns .<= rows - MLXArray(Int32(slidingWindow)))[.newAxis, .newAxis, 0..., 0...]
        return (
            additive(future .|| padded, dtype: dtype),
            additive(future .|| padded .|| tooFar, dtype: dtype)
        )
    }

    /// Zero where a key may be seen, a large finite negative where it may not.
    ///
    /// Finite rather than infinite on purpose: a padded query at the front of a left-padded
    /// prompt has nothing it may see, and a row of infinities softmaxes to NaN, which then
    /// spreads through the residual stream. A finite floor degrades that row to a uniform
    /// average instead; its state is discarded downstream, but a NaN would not be.
    private static func additive(_ blocked: MLXArray, dtype: DType) -> MLXArray {
        MLX.where(blocked, MLXArray(Float(-1e9)), MLXArray(Float(0))).asType(dtype)
    }
}
