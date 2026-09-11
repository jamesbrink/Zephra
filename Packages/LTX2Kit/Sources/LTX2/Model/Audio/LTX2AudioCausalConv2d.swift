import Foundation
import MLX
import MLXNN

/// A two-dimensional convolution over a spectrogram, causal along time.
///
/// The audio autoencoder's activations are `[batch, time, mel, channels]`, and its
/// `causality_axis` is `"height"`, which is the time axis in that layout: time is padded by
/// `kernel - 1` **before** and nothing after, so a frame never reads one that comes later,
/// and the mel axis is padded evenly. Zero padding, unlike the video autoencoder's edge
/// padding: a spectrogram's edges are silence, not a frame to repeat. The kernel is
/// `[out, kt, km, in]`, MLX's own order, which is how the pack stores it.
final class LTX2AudioCausalConv2d: Module {
    @ModuleInfo(key: "conv") var conv: Conv2d

    private let kernel: Int

    init(inputChannels: Int, outputChannels: Int, kernel: Int = 3) {
        self.kernel = kernel
        _conv.wrappedValue = Conv2d(
            inputChannels: inputChannels, outputChannels: outputChannels, kernelSize: IntOrPair(kernel), padding: IntOrPair(0))
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        guard kernel > 1 else { return conv(x) }
        let mel = kernel - 1
        return conv(MLX.padded(x, widths: [0, [kernel - 1, 0], [mel / 2, mel - mel / 2], 0]))
    }
}
