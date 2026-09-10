import Foundation
import MLX
import MLXNN

/// A residual block of the latent upsampler: convolve, normalise, activate, convolve,
/// normalise, then activate the sum with the residual.
///
/// Not the autoencoder's block. That one normalises before each convolution with a
/// parameterless pixel norm and adds the residual last; this one normalises after, with an
/// affine GroupNorm of 32 the checkpoint carries as `norm1` and `norm2`, and runs SiLU over the
/// sum rather than handing it back raw. The convolutions are the reference's plain `Conv3d`
/// with zero padding on every axis, time included, so the frame count never changes and no
/// frame is repeated at either end -- which is why the block takes MLXNN's `Conv3d` directly
/// rather than `LTX2VideoConv3d`, whose edge padding in time is the autoencoder's own.
///
/// Activations are channels-last, `[batch, frames, height, width, channels]`, and the kernels
/// `[out, kd, kh, kw, in]`, which is how the pack stores them.
final class LTX2UpsamplerResBlock: Module {
    @ModuleInfo(key: "conv1") var firstConv: Conv3d
    @ModuleInfo(key: "norm1") var firstNorm: GroupNorm
    @ModuleInfo(key: "conv2") var secondConv: Conv3d
    @ModuleInfo(key: "norm2") var secondNorm: GroupNorm

    init(channels: Int) {
        _firstConv.wrappedValue = Conv3d(
            inputChannels: channels, outputChannels: channels, kernelSize: 3, padding: 1)
        _firstNorm.wrappedValue = .ltx2Upsampler(channels: channels)
        _secondConv.wrappedValue = Conv3d(
            inputChannels: channels, outputChannels: channels, kernelSize: 3, padding: 1)
        _secondNorm.wrappedValue = .ltx2Upsampler(channels: channels)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = silu(firstNorm(firstConv(x)))
        h = secondNorm(secondConv(h))
        return silu(h + x)
    }
}
