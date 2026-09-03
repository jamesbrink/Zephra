import Foundation
import MLX
import MLXNN

/// Halves both spatial axes with a strided convolution.
///
/// The padding is asymmetric on purpose. diffusers builds the encoder's downsamplers with
/// `downsample_padding=0`, which makes the reference pad one row at the bottom and one column
/// at the right before a stride-2 3x3 convolution with no padding of its own. Padding both
/// sides instead — the obvious reading of "padding 1" — shifts the sampling grid half a cell
/// and corrupts the top and left borders of every latent, which looks like a subtle framing
/// error rather than a failure.
final class Flux2VAEDownsample: Module {
    @ModuleInfo(key: "conv") var convolution: Conv2d

    init(channels: Int) {
        _convolution.wrappedValue = Conv2d(
            inputChannels: channels, outputChannels: channels,
            kernelSize: 3, stride: 2, padding: 0)
    }

    /// Halves `x`, `[batch, height, width, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let padded = MLX.padded(
            x, widths: [IntOrPair(0), IntOrPair((0, 1)), IntOrPair((0, 1)), IntOrPair(0)])
        return convolution(padded)
    }
}
