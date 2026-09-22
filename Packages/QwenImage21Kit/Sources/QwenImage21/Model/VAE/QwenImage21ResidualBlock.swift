import Foundation
import MLX
import MLXNN

/// A residual block: normalise, SiLU, convolve, twice, then add the input back, through a
/// 1 x 1 convolution when the block changes width.
///
/// The reference's order is `h = conv_shortcut(x)`, then `conv1(SiLU(norm1(x)))`, then
/// `conv2(dropout(SiLU(norm2(x))))`, then `x + h`. `conv_shortcut` is `nn.Identity` when the
/// widths match, and the checkpoint has nothing under it there. Dropout is configured at zero
/// in every published configuration and so does not exist here.
final class QwenImage21ResidualBlock: Module {
    @ModuleInfo(key: "norm1") var norm1: QwenImage21VAENorm
    @ModuleInfo(key: "conv1") var conv1: QwenImage21CausalConv
    @ModuleInfo(key: "norm2") var norm2: QwenImage21VAENorm
    @ModuleInfo(key: "conv2") var conv2: QwenImage21CausalConv
    @ModuleInfo(key: "conv_shortcut") var convShortcut: QwenImage21CausalConv?

    init(inputChannels: Int, outputChannels: Int) {
        _norm1.wrappedValue = QwenImage21VAENorm(channels: inputChannels)
        _conv1.wrappedValue = QwenImage21CausalConv(
            inputChannels: inputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: 1)
        _norm2.wrappedValue = QwenImage21VAENorm(channels: outputChannels)
        _conv2.wrappedValue = QwenImage21CausalConv(
            inputChannels: outputChannels, outputChannels: outputChannels,
            kernelSize: 3, padding: 1)
        _convShortcut.wrappedValue =
            inputChannels == outputChannels
            ? nil
            : QwenImage21CausalConv(
                inputChannels: inputChannels, outputChannels: outputChannels, kernelSize: 1)
    }

    /// `[batch, height, width, channels]` in, the block's output width out.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let shortcut = convShortcut.map { $0(x) } ?? x
        return conv2(silu(norm2(conv1(silu(norm1(x)))))) + shortcut
    }
}
