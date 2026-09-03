import Foundation
import MLX
import MLXNN

/// A residual block in the autoencoder: normalise, activate, convolve, twice, then add.
///
/// The shortcut reads the block's **input**, not the normalised copy, and it only exists when
/// the block changes width — which is why the checkpoint carries `conv_shortcut` for some blocks
/// and not others.
final class QwenImageVAEResidualBlock: Module {
    @ModuleInfo(key: "norm1") var firstNorm: QwenImageVAENorm
    @ModuleInfo(key: "conv1") var firstConv: Conv2d
    @ModuleInfo(key: "norm2") var secondNorm: QwenImageVAENorm
    @ModuleInfo(key: "conv2") var secondConv: Conv2d
    @ModuleInfo(key: "conv_shortcut") var shortcut: Conv2d?

    init(inputChannels: Int, outputChannels: Int) {
        _firstNorm.wrappedValue = QwenImageVAENorm(inputChannels, imagesOnly: false)
        _firstConv.wrappedValue = Conv2d(
            inputChannels: inputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: 1)
        _secondNorm.wrappedValue = QwenImageVAENorm(outputChannels, imagesOnly: false)
        _secondConv.wrappedValue = Conv2d(
            inputChannels: outputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: 1)
        _shortcut.wrappedValue =
            inputChannels == outputChannels
            ? nil
            : Conv2d(
                inputChannels: inputChannels, outputChannels: outputChannels, kernelSize: 1)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let residual = shortcut?(x) ?? x
        var h = firstConv(silu(firstNorm(x)))
        h = secondConv(silu(secondNorm(h)))
        return h + residual
    }
}
