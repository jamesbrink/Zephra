import Foundation
import MLX
import MLXNN

/// A residual block in either tower: normalise, activate, convolve, twice, then add.
///
/// The shortcut reads the block's **input**, not the normalised copy, and it exists only where
/// the block changes width. That is why the checkpoint carries `conv_shortcut` for four blocks
/// out of the twenty-two and for none of the rest, and why building it unconditionally would
/// fail the load rather than quietly mis-decode.
final class Flux2VAEResnetBlock: Module {
    @ModuleInfo(key: "norm1") var firstNorm: GroupNorm
    @ModuleInfo(key: "conv1") var firstConv: Conv2d
    @ModuleInfo(key: "norm2") var secondNorm: GroupNorm
    @ModuleInfo(key: "conv2") var secondConv: Conv2d
    @ModuleInfo(key: "conv_shortcut") var shortcut: Conv2d?

    init(inputChannels: Int, outputChannels: Int, groups: Int) {
        _firstNorm.wrappedValue = .flux2(channels: inputChannels, groups: groups)
        _firstConv.wrappedValue = Conv2d(
            inputChannels: inputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: 1)
        _secondNorm.wrappedValue = .flux2(channels: outputChannels, groups: groups)
        _secondConv.wrappedValue = Conv2d(
            inputChannels: outputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: 1)
        _shortcut.wrappedValue =
            inputChannels == outputChannels
            ? nil
            : Conv2d(
                inputChannels: inputChannels, outputChannels: outputChannels, kernelSize: 1)
    }

    /// Transforms `x`, `[batch, height, width, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = firstConv(silu(firstNorm(x)))
        h = secondConv(silu(secondNorm(h)))
        return h + (shortcut?(x) ?? x)
    }
}
