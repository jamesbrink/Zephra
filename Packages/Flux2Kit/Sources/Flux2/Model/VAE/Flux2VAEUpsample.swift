import Foundation
import MLX
import MLXNN

/// Doubles both spatial axes: nearest-neighbour, then a 3x3 convolution.
///
/// The width is unchanged. This is diffusers' `Upsample2D` with `use_conv` and no transpose,
/// so the interpolation carries no weights and the convolution is the whole of the checkpoint's
/// `upsamplers.0.conv`.
final class Flux2VAEUpsample: Module {
    @ModuleInfo(key: "conv") var convolution: Conv2d

    init(channels: Int) {
        _convolution.wrappedValue = Conv2d(
            inputChannels: channels, outputChannels: channels, kernelSize: 3, padding: 1)
    }

    /// Doubles `x`, `[batch, height, width, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let (batch, height, width, channels) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let doubled =
            MLX.broadcast(
                x.reshaped([batch, height, 1, width, 1, channels]),
                to: [batch, height, 2, width, 2, channels]
            )
            .reshaped([batch, height * 2, width * 2, channels])
        return convolution(doubled)
    }
}
