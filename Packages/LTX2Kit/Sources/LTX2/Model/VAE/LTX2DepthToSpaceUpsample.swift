import Foundation
import MLX
import MLXNN

/// Stretches a clip by convolving to `stride.factor` times the channels and folding those
/// channels into the frame, height and width axes: `up_blocks.N.conv` in the checkpoint.
///
/// A temporal doubling makes `2F` frames of which the first is dropped, so three of them take
/// `F'` latent frames to `8 (F' - 1) + 1` pixel frames, which is where the `8k + 1` frame rule
/// comes from. The fold's channel order is the reference's: for one output channel, the
/// `stride.factor` input channels run over time, then height, then width, and a shuffle in any
/// other order decodes to a tiled mess of the right size.
final class LTX2DepthToSpaceUpsample: Module {
    @ModuleInfo(key: "conv") var conv: LTX2VideoConv3d
    let stride: LTX2VideoDecoderLayout.Stride

    init(inputChannels: Int, outputChannels: Int, stride: LTX2VideoDecoderLayout.Stride) {
        self.stride = stride
        _conv.wrappedValue = LTX2VideoConv3d(
            inputChannels: inputChannels, outputChannels: outputChannels * stride.factor)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let shuffled = Self.shuffled(conv(x), stride: stride)
        return stride.temporal > 1 ? shuffled[0..., (stride.temporal - 1)...] : shuffled
    }

    /// `[b, f, h, w, c·t·s·s]` to `[b, f·t, h·s, w·s, c]`, channels-last throughout.
    static func shuffled(_ x: MLXArray, stride: LTX2VideoDecoderLayout.Stride) -> MLXArray {
        let (batch, frames, height, width) = (x.dim(0), x.dim(1), x.dim(2), x.dim(3))
        let channels = x.dim(4) / stride.factor
        let (t, s) = (stride.temporal, stride.spatial)
        return x.reshaped([batch, frames, height, width, channels, t, s, s])
            .transposed(0, 1, 5, 2, 6, 3, 7, 4)
            .reshaped([batch, frames * t, height * s, width * s, channels])
    }
}
