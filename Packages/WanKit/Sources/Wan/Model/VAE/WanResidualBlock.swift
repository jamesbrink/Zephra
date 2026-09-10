import Foundation
import MLX
import MLXNN

/// A residual block in the video autoencoder: normalise, SiLU, convolve, twice, then add the
/// input back, through a 1 x 1 x 1 convolution when the block changes width.
///
/// Both convolutions are causal and carry frames between chunks; the shortcut is a point-wise
/// convolution and reads no neighbours, so it carries nothing. Dropout is configured at zero
/// and does not exist here.
final class WanResidualBlock: Module {
    @ModuleInfo(key: "norm1") var norm1: WanRMSNorm
    @ModuleInfo(key: "conv1") var conv1: WanCausalConv3d
    @ModuleInfo(key: "norm2") var norm2: WanRMSNorm
    @ModuleInfo(key: "conv2") var conv2: WanCausalConv3d
    @ModuleInfo(key: "conv_shortcut") var convShortcut: WanCausalConv3d?

    init(inputChannels: Int, outputChannels: Int) {
        _norm1.wrappedValue = WanRMSNorm(channels: inputChannels)
        _conv1.wrappedValue = WanCausalConv3d(
            inputChannels: inputChannels, outputChannels: outputChannels, kernelSize: 3, padding: 1)
        _norm2.wrappedValue = WanRMSNorm(channels: outputChannels)
        _conv2.wrappedValue = WanCausalConv3d(
            inputChannels: outputChannels, outputChannels: outputChannels, kernelSize: 3, padding: 1)
        _convShortcut.wrappedValue = inputChannels == outputChannels
            ? nil
            : WanCausalConv3d(inputChannels: inputChannels, outputChannels: outputChannels, kernelSize: 1)
    }

    func callAsFunction(_ x: MLXArray, cache: WanFeatureCache) -> MLXArray {
        let shortcut = convShortcut.map { $0(x) } ?? x
        var h = conv1(silu(norm1(x)), cache: cache)
        h = conv2(silu(norm2(h)), cache: cache)
        return h + shortcut
    }
}
