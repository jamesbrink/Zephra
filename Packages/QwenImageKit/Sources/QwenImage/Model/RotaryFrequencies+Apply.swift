import Foundation
import MLX

extension RotaryFrequencies {
    /// Rotates every adjacent pair of channels in `x` by this table's angles.
    ///
    /// `x` is `[batch, positions, heads, headDim]`. Channels are taken two at a time as a
    /// complex number and multiplied by the unit vector at that position's angle, which is the
    /// same arithmetic as the reference's complex path written out in real terms — MLX has no
    /// need of a complex dtype for it, and the real form makes the pairing explicit.
    ///
    /// The pairing is **adjacent** channels, `(0,1), (2,3), ...`, not two halves of the head.
    /// Both conventions exist in the wild and they are not interchangeable.
    public func rotate(_ x: MLXArray) -> MLXArray {
        let shape = x.shape
        let (batch, positions, heads, headDim) = (shape[0], shape[1], shape[2], shape[3])
        let pairs = headDim / 2

        let split = x.reshaped([batch, positions, heads, pairs, 2])
        let real = split[.ellipsis, 0]
        let imaginary = split[.ellipsis, 1]

        // One angle per position and pair, broadcast across the batch and the heads.
        let cosine = cos.reshaped([1, positions, 1, pairs]).asType(x.dtype)
        let sine = sin.reshaped([1, positions, 1, pairs]).asType(x.dtype)

        let rotatedReal = real * cosine - imaginary * sine
        let rotatedImaginary = real * sine + imaginary * cosine

        return MLX.stacked([rotatedReal, rotatedImaginary], axis: -1)
            .reshaped([batch, positions, heads, headDim])
    }
}
