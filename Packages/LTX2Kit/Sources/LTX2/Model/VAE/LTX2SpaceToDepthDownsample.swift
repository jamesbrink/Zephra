import Foundation
import MLX
import MLXNN

/// Shrinks a clip by folding time and space into the channel axis: `down_blocks.N.conv` in the
/// checkpoint, the encoder's answer to `LTX2DepthToSpaceUpsample`.
///
/// Two branches summed. The skip folds the input as it is and averages the folded channels down
/// to the output width in contiguous groups. The convolution runs at stride one to
/// `out / stride.factor` channels and is folded to `out` by the same rearrangement, which is why
/// the checkpoint's kernels here are narrower than the stage they feed: 64, 256, 128 and 128
/// outputs for stages of 256, 512, 1024 and 1024.
///
/// A temporal halving prepends the first frame once before either branch, so `8k + 1` frames
/// come out as `k + 1` rather than losing the odd one: the causal convolution keeps the first
/// frame on its own, which is the whole reason one picture has a latent frame of its own to be
/// held in.
final class LTX2SpaceToDepthDownsample: Module {
    @ModuleInfo(key: "conv") var conv: LTX2VideoConv3d

    let stride: LTX2VideoEncoderLayout.Stride
    /// Folded channels averaged into one output channel on the skip branch.
    private let groupSize: Int

    init(inputChannels: Int, outputChannels: Int, stride: LTX2VideoEncoderLayout.Stride) {
        self.stride = stride
        groupSize = inputChannels * stride.factor / outputChannels
        _conv.wrappedValue = LTX2VideoConv3d(
            inputChannels: inputChannels,
            outputChannels: outputChannels / stride.factor,
            causal: true)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var input = x
        if stride.temporal > 1 {
            input = MLX.concatenated([input[0..., 0..<1], input], axis: 1)
        }
        var skip = Self.folded(input, stride: stride)
        if groupSize > 1 {
            let shape = skip.shape
            skip = MLX.mean(
                skip.reshaped(shape.dropLast() + [shape[4] / groupSize, groupSize]), axis: -1)
        }
        return Self.folded(conv(input), stride: stride) + skip
    }

    /// `[b, f·t, h·s, w·s, c]` to `[b, f, h, w, c·t·s·s]`, the exact inverse of
    /// `LTX2DepthToSpaceUpsample.shuffled`: for one input channel, the `stride.factor` output
    /// channels run over time, then height, then width.
    static func folded(_ x: MLXArray, stride: LTX2VideoEncoderLayout.Stride) -> MLXArray {
        let (batch, channels) = (x.dim(0), x.dim(4))
        let (t, s) = (stride.temporal, stride.spatial)
        let (frames, height, width) = (x.dim(1) / t, x.dim(2) / s, x.dim(3) / s)
        return x.reshaped([batch, frames, t, height, s, width, s, channels])
            .transposed(0, 1, 3, 5, 7, 2, 4, 6)
            .reshaped([batch, frames, height, width, channels * stride.factor])
    }
}
