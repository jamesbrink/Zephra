import Foundation
import MLX
import MLXNN

/// Turns a noise level into the vector every adaptive norm is driven by.
///
/// A sinusoidal projection into 256 channels, cosines first and no frequency shift, then two
/// linears with a SiLU between them, both with biases. The sigma arrives on a 0-to-1 scale and
/// is stretched by `timestepScale` (1000) here, which is where the reference pipeline does it:
/// its scheduler's timesteps are its sigmas times a thousand.
///
/// The checkpoint nests this under `emb.timestep_embedder`; `LTX2TransformerWeights` folds the
/// inner name away so the module tree is one level rather than two.
final class LTX2TimestepEmbedding: Module {
    /// Channels the sinusoid produces, before the MLP widens it.
    static let projectionChannels = 256
    /// Base of the frequency ladder.
    static let maxPeriod: Double = 10000

    @ModuleInfo(key: "linear1") var input: Linear
    @ModuleInfo(key: "linear2") var output: Linear

    private let timestepScale: Float

    init(embeddingDim: Int, timestepScale: Float) {
        self.timestepScale = timestepScale
        _input.wrappedValue = Linear(Self.projectionChannels, embeddingDim, bias: true)
        _output.wrappedValue = Linear(embeddingDim, embeddingDim, bias: true)
    }

    /// The conditioning vector for one batch of noise levels, `[batch]` in, `[batch, dim]` out,
    /// in `dtype`: the float32 sinusoid is cast before the first linear, as the reference casts
    /// `timesteps_proj.to(hidden_dtype)`.
    func callAsFunction(_ sigma: MLXArray, dtype: DType) -> MLXArray {
        output(silu(input(sinusoid(sigma).asType(dtype))))
    }

    /// The frequency ladder, one per output pair, built on the CPU in doubles so every entry
    /// rounds to the float32 the reference's own `exp` lands on.
    static let ladder: [Float] = {
        let half = Double(projectionChannels / 2)
        return (0..<(projectionChannels / 2)).map { index in
            Float(Foundation.exp(-Foundation.log(maxPeriod) * Double(index) / half))
        }
    }()

    /// The sinusoidal projection in float32, cosines first.
    func sinusoid(_ sigma: MLXArray) -> MLXArray {
        let scaled = sigma.asType(.float32).reshaped([-1, 1]) * timestepScale
        let angles = scaled * MLXArray(Self.ladder)
        return MLX.concatenated([MLX.cos(angles), MLX.sin(angles)], axis: -1)
    }
}
