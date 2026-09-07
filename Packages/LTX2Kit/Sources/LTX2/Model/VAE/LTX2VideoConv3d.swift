import Foundation
import MLX
import MLXNN

/// A three-deep convolution over a clip, padded the way the autoencoder's checkpoint expects.
///
/// Space is zero-padded by one on each side, which `Conv3d` does itself. Time is padded by
/// repeating a frame, and which frame is the one difference between the two halves of the
/// autoencoder. The decoder is **non-causal** (`decoder_causal: false`): the first frame goes
/// before and the last frame after, so each frame reads one neighbour either side and a clip of
/// one frame reads itself three times. The encoder is **causal**: the first frame is repeated
/// `kernel - 1` times at the front and nothing is added at the back, so a cell never reads a
/// frame that comes after it — which is what lets one picture encode to one latent frame that
/// means the same thing it would at the head of a longer clip.
///
/// Zero-padding time instead darkens the first and last frames, and reflect-padding space, which
/// an older LTX decoder used, drifts the whole clip; both are wrong for this checkpoint.
///
/// Activations are channels-last, `[batch, frames, height, width, channels]`, which is what MLX's
/// `Conv3d` reads, and the kernel is `[out, kd, kh, kw, in]`, which is how the pack stores it.
final class LTX2VideoConv3d: Module {
    @ModuleInfo(key: "conv") var conv: Conv3d

    /// Frames repeated at the front, and at the back when it is not causal: `kernel - 1` of them
    /// for a causal convolution, half that either side otherwise.
    private let causal: Bool

    init(inputChannels: Int, outputChannels: Int, causal: Bool = false) {
        self.causal = causal
        _conv.wrappedValue = Conv3d(
            inputChannels: inputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: [0, 1, 1])
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let time: IntOrPair = causal ? [2, 0] : [1, 1]
        return conv(MLX.padded(x, widths: [0, time, 0, 0, 0], mode: .edge))
    }
}
