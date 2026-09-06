import Foundation
import MLX

/// LTX-2's rotary embedding: a log-spaced frequency ladder over fractional positions, applied
/// in the "split" form, where the two halves of a head's width are the pair that rotates.
///
/// Nothing here is shared with `ZephraMLX.RotaryFrequencies`, on purpose: that table is the
/// `1 / theta^(2i/d)` ladder over integer positions that Qwen-Image and klein use, and this one
/// is `theta^linspace(0, 1, n) * pi / 2` over positions taken as a fraction of a pixel-space
/// extent, evaluated at the midpoint of each latent cell. The ladder is built in `Double`
/// because the checkpoint says `frequencies_precision: float64`: the reference raises theta to
/// 682 exponents in double and only then rounds, and a float32 `pow` lands one unit off for
/// many of them, which the outer product with positions in the thousands turns into visible
/// angle error.
///
/// One instance serves one attention width: the video lane's 3-axis table over
/// `[20, 2048, 2048]`, and the text connector's 1-axis table over `[4096]`.
public struct LTX2RotaryEmbedding: Sendable {
    /// Heads the rotated tensor is split into.
    public let heads: Int
    /// Width of one head; the table has `headDim / 2` angles per head.
    public let headDim: Int
    /// The extents positions are taken as a fraction of, one per axis.
    public let maxPositions: [Double]
    /// The ladder, `dim / (2 * axes)` entries, as the reference rounds it.
    public let ladder: [Float]

    /// Creates the embedding for a stream `heads * headDim` wide over `maxPositions.count` axes.
    public init(heads: Int, headDim: Int, maxPositions: [Double], theta: Double) {
        self.heads = heads
        self.headDim = headDim
        self.maxPositions = maxPositions
        let count = (heads * headDim) / (2 * maxPositions.count)
        ladder = (0..<count).map { index in
            let exponent = count == 1 ? 0 : Double(index) / Double(count - 1)
            return Float(Foundation.pow(theta, exponent) * Double.pi / 2)
        }
    }

    /// Angles the ladder leaves short of half the width; the front of each token's table is
    /// padded with that many unrotated pairs (cosine 1, sine 0). 2 for the video lane.
    public var padding: Int { heads * headDim / 2 - ladder.count * maxPositions.count }

    /// The cosine and sine tables for `positions`, `[axes, tokens]` in the pixel-space units
    /// `maxPositions` is in, as `[1, heads, tokens, headDim / 2]` each.
    ///
    /// Per token the angles are laid out ladder-major: all axes at the first frequency, then
    /// all axes at the second, which is the transpose-and-flatten the reference does.
    public func table(positions: MLXArray) -> LTX2RotaryTable {
        let tokens = positions.shape[1]
        let extents = MLXArray(maxPositions.map(Float.init)).reshaped([-1, 1])
        let fraction = (positions.asType(.float32) / extents) * 2 - 1
        // [axes, tokens, ladder] -> [tokens, ladder, axes] -> [tokens, ladder * axes]
        let angles = (fraction.expandedDimensions(axis: -1) * MLXArray(ladder))
            .transposed(1, 2, 0)
            .reshaped([tokens, -1])
        var cosine = MLX.cos(angles)
        var sine = MLX.sin(angles)
        if padding > 0 {
            cosine = MLX.concatenated([MLX.ones([tokens, padding]), cosine], axis: -1)
            sine = MLX.concatenated([MLX.zeros([tokens, padding]), sine], axis: -1)
        }
        return LTX2RotaryTable(
            cos: cosine.reshaped([1, tokens, heads, headDim / 2]).transposed(0, 2, 1, 3),
            sin: sine.reshaped([1, tokens, heads, headDim / 2]).transposed(0, 2, 1, 3))
    }
}
