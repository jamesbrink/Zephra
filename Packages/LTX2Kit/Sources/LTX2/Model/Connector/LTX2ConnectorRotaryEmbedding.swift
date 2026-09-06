import Foundation
import MLX

/// The 1-D rotary embedding of the text connector, in LTX's "split" layout.
///
/// LTX builds its frequency ladder unlike a language model's: `theta` raised to `linspace(0, 1)`
/// over half the width, times pi over two, in double precision, so the ladder runs from one
/// radian per unit position up to `theta` radians, log-spaced. Positions are fractions of a
/// nominal sequence length (`maxPosition`, 4096) mapped to -1...1, so a token's angle depends on
/// where it sits in that span, not on its raw index. Split layout means the first half of each
/// head's channels holds the real parts and the second half the imaginary ones.
struct LTX2ConnectorRotaryEmbedding {
    /// Width of the token stream, `heads * headDim`.
    let dim: Int
    /// Heads the tables are shaped for.
    let heads: Int
    /// The nominal sequence length positions are measured against.
    let maxPosition: Int
    /// Base of the ladder.
    let theta: Double

    init(dim: Int, heads: Int, maxPosition: Int = 4096, theta: Double = 10_000) {
        self.dim = dim
        self.heads = heads
        self.maxPosition = maxPosition
        self.theta = theta
    }

    /// Cosine and sine for positions `0..<length`, each `[length, heads, headDim / 2]`.
    func tables(length: Int) -> (cos: MLXArray, sin: MLXArray) {
        let count = dim / 2
        let ladder = (0..<count).map { index -> Float in
            let fraction = count == 1 ? 0 : Double(index) / Double(count - 1)
            return Float(pow(theta, fraction) * Double.pi / 2)
        }
        let positions = (0..<length).map { Float(Double($0) / Double(maxPosition)) * 2 - 1 }
        let angles = MLXArray(positions)[0..., .newAxis] * MLXArray(ladder)[.newAxis, 0...]
        let shaped = angles.reshaped(length, heads, count / heads)
        return (MLX.cos(shaped), MLX.sin(shaped))
    }

    /// Rotates `x`, `[batch, length, heads, headDim]`, by the tables: the head's first half
    /// against its second, `(a cos - b sin, b cos + a sin)`.
    static func rotate(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let half = x.dim(-1) / 2
        let first = x[.ellipsis, 0..<half].asType(.float32)
        let second = x[.ellipsis, half...].asType(.float32)
        let cosine = cos[.newAxis, 0..., 0..., 0...]
        let sine = sin[.newAxis, 0..., 0..., 0...]
        return MLX.concatenated(
            [first * cosine - second * sine, second * cosine + first * sine], axis: -1
        ).asType(x.dtype)
    }
}
