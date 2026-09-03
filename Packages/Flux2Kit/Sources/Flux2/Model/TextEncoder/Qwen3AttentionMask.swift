import Foundation
import MLX

/// The additive attention mask a right-padded prompt needs: causal, and blind to the padding.
///
/// FLUX.2 klein pads every prompt to 512 tokens and then hands the transformer all 512 of the
/// encoder's outputs, padding included. So the padded positions' hidden states are part of the
/// conditioning and have to match the reference's exactly, which makes the mask a correctness
/// question rather than a performance one.
enum Qwen3AttentionMask {
    /// An additive `[1, 1, length, length]` mask, blocking a query at `row` from a key at
    /// `column` when the key is in that query's future or is padding.
    ///
    /// - Parameters:
    ///   - length: The padded sequence length. Both axes of the mask.
    ///   - validCount: Real tokens, all of them at the front. Keys at or after this are padding.
    ///   - dtype: The hidden state's element type. Attention adds the mask to its scores, so the
    ///     two have to agree.
    static func causalAndPadding(length: Int, validCount: Int, dtype: DType) -> MLXArray {
        let positions = MLXArray(Array(0..<Int32(length)))
        let rows = positions[0..., .newAxis]
        let columns = positions[.newAxis, 0...]
        let blocked = (columns .> rows) .|| (columns .>= MLXArray(Int32(validCount)))
        let mask = MLX.where(blocked, MLXArray(blockedScore), MLXArray(Float(0)))
        return mask.reshaped(1, 1, length, length).asType(dtype)
    }

    /// What a blocked key scores: large and negative, but finite.
    ///
    /// Negative infinity would be the obvious choice and is wrong here in one case that this
    /// mask has to survive. A row every one of whose keys is blocked softmaxes over all-infinite
    /// scores and comes back NaN, which then spreads through the residual stream. With right
    /// padding no row is ever fully blocked -- a padded query still sees the whole real prefix,
    /// because the prefix is in its past and is not padding -- so infinity would in fact work
    /// today. A finite sentinel keeps that from being a thing to remember: it softmaxes to zero
    /// weight either way, and a fully blocked row degrades to a uniform average rather than to
    /// NaN. The reference does the same, using the dtype's most negative finite value.
    private static let blockedScore = Float(-1e9)
}
