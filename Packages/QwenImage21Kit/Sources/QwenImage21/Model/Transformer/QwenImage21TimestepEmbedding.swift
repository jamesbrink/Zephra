import Foundation
import MLX
import MLXNN

/// Turns a noise level into the conditioning vector the whole model modulates by,
/// `time_text_embed`.
///
/// Two things here are 2.1's own and neither fails loudly if it is taken from elsewhere.
///
/// **Cosines occupy the first half of the channels and sines the second.** diffusers' ordinary
/// `Timesteps` puts sine first, so a helper lifted from another family's port is wrong here in a
/// way that still produces a smooth, plausible embedding.
///
/// **The timestep is scaled by 1000 inside the sinusoid**, through `time_factor`, and the
/// pipeline hands over `t / 1000`, so the angle is the raw training timestep. The sinusoid is
/// built in float32 whatever the stream is, as the reference's `timestep.float()` does, and cast
/// to the stream's dtype before the projection, which is where `timesteps_proj.to(dtype)` puts
/// the rounding.
final class QwenImage21TimestepEmbedding: Module {
    /// Channels the sinusoid produces before the projection widens it.
    static let projectionChannels = 256
    /// The noise level arrives on a zero-to-one scale and is stretched back onto the training
    /// scale here.
    static let timeFactor: Float = 1000
    /// Base of the frequency ladder.
    static let maxPeriod: Float = 10000

    @ModuleInfo(key: "timestep_embedder") var projection: QwenImage21TimestepProjection

    init(embeddingDim: Int, channels: Int = QwenImage21TimestepEmbedding.projectionChannels) {
        _projection.wrappedValue = QwenImage21TimestepProjection(
            channels: channels, embeddingDim: embeddingDim)
    }

    /// The conditioning for one batch of noise levels: `[rows]` in, `[rows, dim]` out.
    func callAsFunction(_ timestep: MLXArray, projectionDType: DType) -> MLXArray {
        projection(Self.sinusoid(timestep).asType(projectionDType))
    }

    /// The frequency ladder, computed once on the CPU.
    ///
    /// The timestep reaching the sinusoid is up to 1000, so a frequency one float32 unit in the
    /// last place away from the reference's moves the angle by 1e-4 radians and the cosine with
    /// it, and every modulated layer downstream carries it. The exponent is built in **float32**
    /// because the reference builds it in a float32 tensor, and only the exponential is taken in
    /// double and rounded once, which is as close as this gets without reimplementing float32
    /// `exp`. What is left is a handful of last-place differences; `ModulationTests` states the
    /// margin they cost.
    static let ladder: [Float] = {
        let half = Float(projectionChannels / 2)
        return (0..<(projectionChannels / 2)).map { index in
            Float(Foundation.exp(Double(-Foundation.log(maxPeriod) * Float(index) / half)))
        }
    }()

    /// The sinusoidal projection, **cosines first**.
    static func sinusoid(_ timestep: MLXArray) -> MLXArray {
        let scaled = (timestep.reshaped([-1, 1]).asType(.float32) * timeFactor)
        let angles = scaled * MLXArray(ladder)
        return MLX.concatenated([MLX.cos(angles), MLX.sin(angles)], axis: -1)
    }
}
