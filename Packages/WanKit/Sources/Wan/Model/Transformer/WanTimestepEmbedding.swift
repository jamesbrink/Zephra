import Foundation
import MLX
import MLXNN

/// Turns a timestep into the vector the modulation is driven by.
///
/// A sinusoidal projection into `freq_dim` channels, cosines first and no frequency shift
/// (`Timesteps(flip_sin_to_cos: true, downscale_freq_shift: 0)`), then two linears with a SiLU
/// between them, both with biases (`TimestepEmbedding`). The timestep arrives in the model's
/// own units, 0 to 1000, and nothing here scales it.
///
/// Runs in float32 whatever the stream is: diffusers keeps `time_embedder` in float32 under a
/// bfloat16 load (`_keep_in_fp32_modules`) and casts its output to the stream afterwards, and
/// the input here is a handful of distinct timesteps, so the width costs nothing.
final class WanTimestepEmbedding: Module {
    /// Base of the frequency ladder.
    static let maxPeriod: Double = 10000

    @ModuleInfo(key: "linear_1") var input: Linear
    @ModuleInfo(key: "linear_2") var output: Linear

    /// The frequency ladder, one per output pair, built on the CPU in doubles so every entry
    /// rounds to the float32 the reference's own `exp` lands on.
    let ladder: [Float]

    init(frequencyChannels: Int, embeddingDim: Int) {
        let half = frequencyChannels / 2
        ladder = (0..<half).map { index in
            Float(Foundation.exp(-Foundation.log(Self.maxPeriod) * Double(index) / Double(half)))
        }
        _input.wrappedValue = Linear(frequencyChannels, embeddingDim, bias: true)
        _output.wrappedValue = Linear(embeddingDim, embeddingDim, bias: true)
    }

    /// The embedding for `timesteps`, `[count]` in, `[count, dim]` out, in float32.
    func callAsFunction(_ timesteps: MLXArray) -> MLXArray {
        output(silu(input(sinusoid(timesteps))))
    }

    /// The sinusoidal projection in float32, cosines first.
    func sinusoid(_ timesteps: MLXArray) -> MLXArray {
        let angles = timesteps.asType(.float32).reshaped([-1, 1]) * MLXArray(ladder)
        return MLX.concatenated([MLX.cos(angles), MLX.sin(angles)], axis: -1)
    }
}
