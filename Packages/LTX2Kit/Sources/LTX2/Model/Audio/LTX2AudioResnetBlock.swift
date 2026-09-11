import Foundation
import MLX
import MLXNN

/// A residual block in the audio autoencoder: pixel-norm, SiLU, a causal convolution, twice,
/// then add, with a one-by-one shortcut where the width changes.
///
/// The norms are the same parameterless root-mean-square over channels the video decoder
/// uses, at this autoencoder's own epsilon (`LTX2AudioDecoderLayout.normEpsilon`); the
/// shortcut is `nin_shortcut`, a causal convolution of kernel one, which pads nothing.
final class LTX2AudioResnetBlock: Module {
    @ModuleInfo(key: "conv1") var firstConv: LTX2AudioCausalConv2d
    @ModuleInfo(key: "conv2") var secondConv: LTX2AudioCausalConv2d
    @ModuleInfo(key: "nin_shortcut") var shortcut: LTX2AudioCausalConv2d?

    private let eps: Float

    init(inputChannels: Int, outputChannels: Int, eps: Float) {
        self.eps = eps
        _firstConv.wrappedValue = LTX2AudioCausalConv2d(inputChannels: inputChannels, outputChannels: outputChannels)
        _secondConv.wrappedValue = LTX2AudioCausalConv2d(inputChannels: outputChannels, outputChannels: outputChannels)
        _shortcut.wrappedValue = inputChannels == outputChannels
            ? nil
            : LTX2AudioCausalConv2d(inputChannels: inputChannels, outputChannels: outputChannels, kernel: 1)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = firstConv(silu(Self.normalized(x, eps: eps)))
        h = secondConv(silu(Self.normalized(h, eps: eps)))
        return (shortcut.map { $0(x) } ?? x) + h
    }

    /// `x / sqrt(mean(x², channels) + eps)` over the last axis.
    static func normalized(_ x: MLXArray, eps: Float) -> MLXArray {
        x * MLX.rsqrt(MLX.mean(x * x, axis: -1, keepDims: true) + eps)
    }
}
