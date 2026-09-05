import Foundation
import MLX
import MLXNN

/// Turns a scalar noise level into the conditioning vector the whole model modulates by.
///
/// A sinusoidal projection into 256 channels, then a two-layer MLP up to the model's width. The
/// three constants are the ones the reference passes and none of them is a default: the
/// timestep is scaled by 1000 before the sinusoid, cosines come before sines, and there is no
/// frequency shift. Both linears are bias-free, as every linear in this transformer is.
///
/// The scaling is unconditional here. `mflux`'s port scales only on some paths, which makes the
/// same sigma mean two different things depending on how it arrived.
final class Flux2TimestepEmbedding: Module {
    /// Channels the sinusoid produces, before the MLP widens it.
    static let projectionChannels = 256
    /// The noise level arrives on a 0-to-1 scale and is stretched onto the training scale here.
    static let timestepScale: Float = 1000
    /// Base of the frequency ladder.
    static let maxPeriod: Float = 10000

    @ModuleInfo(key: "linear_1") var input: Linear
    @ModuleInfo(key: "linear_2") var output: Linear

    init(embeddingDim: Int, channels: Int = Flux2TimestepEmbedding.projectionChannels) {
        _input.wrappedValue = Linear(channels, embeddingDim, bias: false)
        _output.wrappedValue = Linear(embeddingDim, embeddingDim, bias: false)
    }

    /// The conditioning vector for one batch of noise levels, `[batch]` in, `[batch, dim]` out.
    ///
    /// The timestep arrives already in the stream's dtype, and the float32 sinusoid is cast to
    /// `projectionDType` before the first linear, which is the order the reference does it in:
    /// `timestep.to(hidden_states.dtype) * 1000`, then `timesteps_proj.to(timestep.dtype)`.
    /// Under bfloat16 both roundings are visible — 0.77 becomes 768 rather than 770 at the
    /// sinusoid — so `TransformerParityTests` pins them against a bfloat16 fixture.
    func callAsFunction(_ timestep: MLXArray, projectionDType: DType) -> MLXArray {
        output(silu(input(Self.sinusoid(timestep).asType(projectionDType))))
    }

    /// The frequency ladder, one per output pair, built on the CPU in doubles.
    ///
    /// It is 128 numbers computed once, and the precision matters more than it looks. The
    /// timestep reaching the sinusoid is up to 1000, so a frequency that is one float32 unit in
    /// the last place away from the reference's moves the angle by 1e-4 radians, and the cosine
    /// with it. Rounding a double `exp` once lands on the same float32 the reference's own
    /// `exp` does; letting MLX evaluate `exp` in float32 does not always, and the resulting
    /// 6e-5 in the conditioning is amplified by every modulated layer downstream.
    static let ladder: [Float] = {
        let half = Float(projectionChannels / 2)
        return (0..<(projectionChannels / 2)).map { index in
            Float(Foundation.exp(Double(-log(maxPeriod) * Float(index) / half)))
        }
    }()

    /// The sinusoidal projection, **cosines first**.
    ///
    /// The timestep is scaled by 1000 in its own dtype, as the reference scales it, and the
    /// angles are then built in float32 whatever that dtype was: the far end of the ladder is
    /// a frequency of 1e-4, and at bfloat16 the smallest angles collapse to each other, so
    /// neighbouring steps of a four-step schedule stop being distinguishable.
    static func sinusoid(_ timestep: MLXArray) -> MLXArray {
        let scaled = (timestep.reshaped([-1, 1]) * timestepScale).asType(.float32)
        let angles = scaled * MLXArray(ladder)
        return MLX.concatenated([MLX.cos(angles), MLX.sin(angles)], axis: -1)
    }
}
