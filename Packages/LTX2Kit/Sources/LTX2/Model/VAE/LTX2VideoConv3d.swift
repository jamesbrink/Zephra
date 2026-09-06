import Foundation
import MLX
import MLXNN

/// A three-deep convolution over a clip, padded the way the decoder's checkpoint expects.
///
/// Space is zero-padded by one on each side, which `Conv3d` does itself. Time is padded by
/// repeating the first frame before and the last frame after: the decoder is **non-causal**
/// (`decoder_causal: false`), so each frame reads one neighbour either side, and a clip of one
/// frame reads itself three times. Zero-padding time instead darkens the first and last frames,
/// and reflect-padding space, which an older LTX decoder used, drifts the whole clip; both are
/// wrong for this checkpoint.
///
/// Activations are channels-last, `[batch, frames, height, width, channels]`, which is what MLX's
/// `Conv3d` reads, and the kernel is `[out, kd, kh, kw, in]`, which is how the pack stores it.
final class LTX2VideoConv3d: Module {
    @ModuleInfo(key: "conv") var conv: Conv3d

    init(inputChannels: Int, outputChannels: Int) {
        _conv.wrappedValue = Conv3d(
            inputChannels: inputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: [0, 1, 1])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        conv(MLX.padded(x, widths: [0, [1, 1], 0, 0, 0], mode: .edge))
    }
}
