import Foundation
import MLX
import MLXNN

/// The Snake activation with a learned amplitude: `x + sin²(αx) / (β + ε)`, one α and β per
/// channel, both stored as logarithms. Periodic, which is what lets a vocoder learn the
/// harmonics of a waveform where a ReLU would learn edges.
final class LTX2SnakeBeta: Module {
    @ParameterInfo(key: "alpha") var alpha: MLXArray
    @ParameterInfo(key: "beta") var beta: MLXArray

    private let eps: Float = 1e-9

    init(channels: Int) {
        _alpha.wrappedValue = MLXArray.zeros([channels])
        _beta.wrappedValue = MLXArray.zeros([channels])
    }

    /// Over `[batch, samples, channels]`.
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let frequency = MLX.exp(alpha.asType(x.dtype))
        let amplitude = MLX.exp(beta.asType(x.dtype))
        let wave = MLX.sin(x * frequency)
        return x + wave * wave / (amplitude + eps)
    }
}
