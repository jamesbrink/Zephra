import Foundation
import MLX
import MLXNN

/// Halves both spatial axes, keeping the width.
///
/// The reference pads the bottom and right edge by one and then strides a 3x3 convolution by
/// two with no padding of its own. That asymmetry is the whole of it: pad evenly instead and
/// every feature shifts half a cell, which shows up as an image that drifts rather than as an
/// error.
///
/// `timeConv` is loaded and never used, exactly as in `QwenImageVAEUpsample`. The reference has
/// two downsample modes, one of which also halves the time axis, and the checkpoint carries its
/// weights for two of the three stages. For the first chunk of a sequence — and a still image is
/// only ever the first chunk — the reference itself skips that convolution, caching the input
/// instead. It stays in the tree so the weights have somewhere to land and nothing is silently
/// unaccounted for.
final class QwenImageVAEDownsample: Module {
    @ModuleInfo(key: "resample") var resample: [Module]
    @ModuleInfo(key: "time_conv") var timeConv: Conv2d?

    init(channels: Int, halvesTime: Bool) {
        // Slot 0 is the reference's zero pad, which carries no weights; the pad is applied in
        // `callAsFunction` because it is asymmetric and MLX's Conv2d padding is not.
        _resample.wrappedValue = [
            Identity(),
            Conv2d(
                inputChannels: channels, outputChannels: channels,
                kernelSize: 3, stride: 2, padding: 0),
        ]
        _timeConv.wrappedValue =
            halvesTime
            ? Conv2d(inputChannels: channels, outputChannels: channels, kernelSize: 1)
            : nil
    }

    /// Downsamples `[batch, height, width, channels]` to half the height and width, rounded up.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        guard let convolution = resample[1] as? Conv2d else {
            preconditionFailure("the resampler's slot 1 must be its convolution")
        }
        return convolution(MLX.padded(x, widths: [[0, 0], [0, 1], [0, 1], [0, 0]]))
    }
}
