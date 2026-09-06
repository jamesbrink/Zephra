import Foundation
import MLX
import MLXNN

/// A residual block in the video decoder: normalise, activate, convolve, twice, then add.
///
/// The decoder never changes width inside a block (every stage's blocks are square), so there
/// is no shortcut convolution and no LayerNorm on the residual; those exist in the reference
/// class for the encoder's use and the checkpoint carries none of them here. Both norms are
/// the parameterless `LTX2PixelNorm`, which is why the checkpoint holds only `conv1` and
/// `conv2` under `res_blocks.N`.
final class LTX2ResnetBlock3D: Module {
    @ModuleInfo(key: "conv1") var firstConv: LTX2VideoConv3d
    @ModuleInfo(key: "conv2") var secondConv: LTX2VideoConv3d

    init(channels: Int) {
        _firstConv.wrappedValue = LTX2VideoConv3d(inputChannels: channels, outputChannels: channels)
        _secondConv.wrappedValue = LTX2VideoConv3d(inputChannels: channels, outputChannels: channels)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = firstConv(silu(LTX2PixelNorm.apply(x)))
        h = secondConv(silu(LTX2PixelNorm.apply(h)))
        return h + x
    }
}
