import Foundation
import MLX
import MLXNN

/// The step before the convolution in a resampler, `resample.0` in the checkpoint: it carries
/// no weights, and exists as a module so the convolution after it keeps its numbered key,
/// `resample.1`.
///
/// Going up it is the reference's `nearest-exact` doubling. `QwenImage21Upsample` upcasts to
/// float32 for that interpolation and casts back, which matters for a fractional scale and not
/// for this one: at a whole factor of two nearest-exact writes each pixel four times, and
/// copying a value is exact in any width, so the copy is made directly and nothing is cast.
///
/// Going down it is one row and one column of zeros **after** the frame, the reference's
/// `ZeroPad2d((0, 1, 0, 1))`, so the stride-two convolution that follows starts at the top-left
/// pixel and comes out at exactly half the size. Pad symmetrically instead and every feature
/// map drifts half a pixel; it is the one asymmetry in the whole autoencoder.
final class QwenImage21SpatialResize: Module, UnaryLayer {
    let upsamples: Bool

    init(upsamples: Bool) {
        self.upsamples = upsamples
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        upsamples
            ? repeated(repeated(x, count: 2, axis: 1), count: 2, axis: 2)
            : padded(x, widths: [0, [0, 1], [0, 1], 0])
    }
}
