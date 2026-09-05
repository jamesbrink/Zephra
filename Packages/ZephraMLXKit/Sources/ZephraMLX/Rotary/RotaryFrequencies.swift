import Foundation
import MLX

/// One rotary position table: a cosine and a sine for every position and every rotated pair.
///
/// Both are `[positions, headDim / 2]`. Rotation is applied to adjacent pairs of a head's
/// channels, so there is half a head's width of each.
///
/// Not `Sendable`, and deliberately so: it holds `MLXArray`s, which belong to whichever thread
/// built them. Everything in this package is confined to the engine's serial inference executor,
/// the same way the backend itself is.
public struct RotaryFrequencies {
    /// Cosines, `[positions, headDim / 2]`.
    public let cos: MLXArray
    /// Sines, the same shape.
    public let sin: MLXArray

    /// How many positions this table covers.
    public var count: Int { cos.shape[0] }

    /// Wraps a pair of tables.
    public init(cos: MLXArray, sin: MLXArray) {
        self.cos = cos
        self.sin = sin
    }
}
