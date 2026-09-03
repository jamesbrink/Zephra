import Foundation
import MLX
import MLXNN

/// Turns a scalar timestep into the conditioning vector every block modulates by.
///
/// A sinusoidal projection into 256 channels, then a two-layer MLP up to the model's width. The
/// three constants are the ones the reference passes and none of them is a default: the
/// timestep is scaled by 1000 before the sinusoid, cosines come before sines, and there is no
/// frequency shift.
final class QwenImageTimestepEmbedding: Module {
    /// Channels the sinusoid produces, before the MLP widens it.
    static let projectionChannels = 256
    /// The timestep arrives on a 0-to-1 scale and is stretched onto the training scale here.
    static let timestepScale: Float = 1000
    /// Half-life of the frequency ladder.
    static let maxPeriod: Float = 10000

    @ModuleInfo(key: "linear_1") var input: Linear
    @ModuleInfo(key: "linear_2") var output: Linear

    init(embeddingDim: Int) {
        _input.wrappedValue = Linear(Self.projectionChannels, embeddingDim, bias: true)
        _output.wrappedValue = Linear(embeddingDim, embeddingDim, bias: true)
    }

    func callAsFunction(_ timestep: MLXArray) -> MLXArray {
        output(silu(input(Self.sinusoid(timestep))))
    }

    /// The sinusoidal projection, cosines first.
    static func sinusoid(_ timestep: MLXArray) -> MLXArray {
        let half = projectionChannels / 2
        let exponent =
            -log(maxPeriod) * MLXArray(Array(0..<half).map(Float.init)) / Float(half)
        let frequencies = MLX.exp(exponent)
        let angles = timestep.reshaped([-1, 1]).asType(.float32) * frequencies * timestepScale
        return MLX.concatenated([MLX.cos(angles), MLX.sin(angles)], axis: -1)
    }
}
