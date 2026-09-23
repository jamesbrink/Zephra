import Foundation
import MLX

/// The additive mask a Qwen3-VL decoder layer attends under: plain causal, and nothing else.
///
/// `layer_types` is absent from 2.1's text config, so every one of the 36 layers is full
/// attention and there is no sliding window anywhere in this stack.
///
/// There is no padding term either, and that is a property of how the pipeline uses the
/// encoder rather than an omission. Tokenisation is **left**-padded, as the checkpoint was
/// trained; the valid slice is then extracted per row and the *embeddings* are right-padded for
/// the transformer (spec C.4). One prompt at a time is one row with nothing padded, so the mask
/// the encoder needs is the causal triangle and the padding never reaches a query. A batched
/// encoder would need the left-padding term as well, and this is the one file that would grow
/// it.
enum Qwen3VLAttentionMask {
    /// An additive `[1, 1, length, length]` mask blocking a query at `row` from any key in its
    /// future.
    ///
    /// - Parameters:
    ///   - length: Tokens. Both axes of the mask.
    ///   - dtype: The hidden state's element type; attention adds this to its scores.
    static func causal(length: Int, dtype: DType) -> MLXArray {
        let positions = MLXArray((0..<length).map { Int32($0) })
        let blocked = positions[.newAxis, 0...] .> positions[0..., .newAxis]
        let mask = MLX.where(blocked, MLXArray(blockedScore), MLXArray(Float(0)))
        return mask.reshaped(1, 1, length, length).asType(dtype)
    }

    /// What a blocked key scores: large and negative, but finite.
    ///
    /// Negative infinity softmaxes a fully blocked row to NaN. No row is ever fully blocked
    /// under a causal mask — a query always sees itself — so infinity would work today; a
    /// finite sentinel keeps that from being a thing to remember.
    private static let blockedScore = Float(-1e9)
}
