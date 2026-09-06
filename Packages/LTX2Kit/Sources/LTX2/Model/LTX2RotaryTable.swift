import Foundation
import MLX

/// The cosine and sine of one sequence's rotary angles, and the rotation they define.
///
/// `[1, heads, tokens, headDim / 2]` each, so a table is built once per generation and
/// broadcast over the batch and over every block.
public struct LTX2RotaryTable {
    public let cos: MLXArray
    public let sin: MLXArray

    public init(cos: MLXArray, sin: MLXArray) {
        self.cos = cos
        self.sin = sin
    }

    /// Heads the table was built for.
    public var heads: Int { cos.shape[1] }
    /// Tokens the table was built for.
    public var tokens: Int { cos.shape[2] }

    /// Rotates `x`, `[batch, tokens, heads * headDim]`, into heads-major `[batch, heads, tokens,
    /// headDim]` for attention.
    ///
    /// The split form: the first and second halves of a head's width are the pair, so
    /// `[a, b] -> [a cos - b sin, b cos + a sin]`. Computed in float32 and cast back to `x`'s
    /// dtype, as the reference upcasts before it rotates.
    public func rotate(_ x: MLXArray) -> MLXArray {
        let batch = x.shape[0]
        let half = cos.shape[3]
        let split = x.reshaped([batch, x.shape[1], heads, 2 * half])
            .transposed(0, 2, 1, 3)
            .asType(.float32)
        let first = split[.ellipsis, ..<half]
        let second = split[.ellipsis, half...]
        return MLX.concatenated(
            [first * cos - second * sin, second * cos + first * sin], axis: -1
        ).asType(x.dtype)
    }
}
