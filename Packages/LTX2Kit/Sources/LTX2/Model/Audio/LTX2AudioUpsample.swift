import Foundation
import MLX
import MLXNN

/// Doubles a spectrogram along time and mel: nearest-neighbour, a causal convolution, and the
/// first row of time dropped, which is how the reference keeps the doubled sequence causal
/// (`LTX2AudioUpsample` with `causality_axis: "height"`).
final class LTX2AudioUpsample: Module {
    @ModuleInfo(key: "conv") var conv: LTX2AudioCausalConv2d

    init(channels: Int) {
        _conv.wrappedValue = LTX2AudioCausalConv2d(inputChannels: channels, outputChannels: channels)
    }

    /// `[batch, time, mel, channels]` to `[batch, 2 * time - 1, 2 * mel, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let doubled = MLX.repeated(MLX.repeated(x, count: 2, axis: 1), count: 2, axis: 2)
        return conv(doubled)[0..., 1..., 0..., 0...]
    }
}
