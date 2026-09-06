import Foundation
import MLX

/// Gemma 4's rotary embedding, in the half-split layout the language models use.
///
/// Two things keep this from being `MLXNN.RoPE`. A full-attention layer rotates only the first
/// quarter of each head's pairs (`partial_rotary_factor` 0.25) and leaves the rest untouched,
/// and its frequency ladder is still built over the *whole* head width: pair `i` turns at
/// `theta^(-2i / headDim)` for `i` below the rotated count and not at all above it. `RoPE` over
/// a narrower `dimensions` would rebuild the ladder over that narrower width and pair the
/// channels differently, so both layer kinds go through this one table instead.
struct Gemma4RotaryEmbedding {
    /// Width of one head.
    let headDim: Int
    /// Base of the frequency ladder.
    let theta: Float
    /// How many of the head's `headDim / 2` pairs turn; the rest have frequency zero.
    let rotatedPairs: Int

    init(headDim: Int, theta: Float, rotaryFraction: Float) {
        self.headDim = headDim
        self.theta = theta
        rotatedPairs = Int(rotaryFraction * Float(headDim)) / 2
    }

    /// Cosine and sine tables for positions `0..<length`, each `[length, headDim]`, laid out as
    /// the reference lays them: the pair frequencies repeated twice, so channel `i` and channel
    /// `i + headDim / 2` share an angle.
    func tables(length: Int) -> (cos: MLXArray, sin: MLXArray) {
        var inverse = [Float](repeating: 0, count: headDim / 2)
        for pair in 0..<rotatedPairs {
            inverse[pair] = 1 / pow(theta, Float(2 * pair) / Float(headDim))
        }
        let positions = MLXArray(Array(0..<Int32(length))).asType(.float32)[0..., .newAxis]
        let frequencies = positions * MLXArray(inverse)[.newAxis, 0...]
        let angles = MLX.concatenated([frequencies, frequencies], axis: -1)
        return (MLX.cos(angles), MLX.sin(angles))
    }

    /// Rotates `x`, `[batch, heads, length, headDim]`, by the tables.
    static func rotate(_ x: MLXArray, cos: MLXArray, sin: MLXArray) -> MLXArray {
        let half = x.dim(-1) / 2
        let first = x[.ellipsis, 0..<half]
        let second = x[.ellipsis, half...]
        let rotated = MLX.concatenated([-second, first], axis: -1)
        return x * cos.asType(x.dtype) + rotated * sin.asType(x.dtype)
    }
}
