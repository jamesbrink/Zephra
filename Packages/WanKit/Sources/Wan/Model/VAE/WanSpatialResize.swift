import Foundation
import MLX
import MLXNN

/// The step before the convolution in a resampler, `resample.0` in the checkpoint: it carries
/// no weights, and exists as a module so the convolution after it keeps its key, `resample.1`.
///
/// Going up it is the reference's `nearest-exact` doubling, which at a whole factor of two is
/// each pixel written four times. Going down it is one row and one column of zeros after the
/// frame, so the strided convolution that follows lands on every other pixel and comes out at
/// exactly half the size; the reference pads with `ZeroPad2d((0, 1, 0, 1))` for the same
/// reason. Frames are folded into the batch, `[frames, height, width, channels]`.
final class WanSpatialResize: Module, UnaryLayer {
    let mode: WanResampleMode

    init(mode: WanResampleMode) {
        self.mode = mode
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        if mode.upsamples {
            return repeated(repeated(x, count: 2, axis: 1), count: 2, axis: 2)
        }
        return padded(x, widths: [0, [0, 1], [0, 1], 0])
    }
}
