import Foundation
import MLX
import MLXNN

/// Doubles the picture at the end of a decoder stage, `upsampler` in the checkpoint:
/// `QwenImage21Resample` in its `upsample2d` or `upsample3d` mode.
///
/// Nearest-exact doubling, then a padded 3 x 3 convolution. The width it writes is the stage's
/// own: the residual layout passes `upsample_out_dim=out_dim` rather than taking the
/// constructor's `dim // 2` default, so nothing narrows here.
///
/// As on the way down, the `3d` mode's `time_conv` is unreachable for a still image — there the
/// cache holds the sentinel `"Rep"` on the first and only chunk, and that branch merely
/// replaces it. See `QwenImage21CausalConv`.
final class QwenImage21Upsample: Module {
    @ModuleInfo(key: "resample") var resample: (QwenImage21SpatialResize, Conv2d)

    init(channels: Int) {
        _resample.wrappedValue = (
            QwenImage21SpatialResize(upsamples: true),
            Conv2d(
                inputChannels: channels, outputChannels: channels, kernelSize: 3, padding: 1)
        )
    }

    /// `[batch, height, width, channels]` to `[batch, height * 2, width * 2, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        resample.1(resample.0(x))
    }
}
