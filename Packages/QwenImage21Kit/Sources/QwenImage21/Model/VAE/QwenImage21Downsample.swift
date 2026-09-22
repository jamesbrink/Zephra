import Foundation
import MLX
import MLXNN

/// Halves the picture at the end of an encoder stage, `downsampler` in the checkpoint:
/// `QwenImage21Resample` in its `downsample2d` or `downsample3d` mode.
///
/// A row and a column of zeros after the frame, then an unpadded stride-two 3 x 3 convolution
/// that keeps the stage's width. Nothing else: the `downsample3d` mode also builds a
/// `time_conv`, and for a still image it is never reached — the reference's feature cache holds
/// `None` at that index on the only chunk there is, and that branch merely records the
/// activation and moves on. `QwenImage21CausalConv` says why in full, and
/// `QwenImage21VAEWeights` drops the six tensors it would need.
final class QwenImage21Downsample: Module {
    @ModuleInfo(key: "resample") var resample: (QwenImage21SpatialResize, Conv2d)

    init(channels: Int) {
        _resample.wrappedValue = (
            QwenImage21SpatialResize(upsamples: false),
            Conv2d(
                inputChannels: channels, outputChannels: channels, kernelSize: 3, stride: 2)
        )
    }

    /// `[batch, height, width, channels]` to `[batch, height / 2, width / 2, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        resample.1(resample.0(x))
    }
}
