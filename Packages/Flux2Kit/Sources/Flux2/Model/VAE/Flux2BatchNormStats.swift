import Foundation
import MLX
import MLXNN

/// The running statistics FLUX.2 normalises its latent with.
///
/// There is no scaling factor and no shift factor here, the way every other diffusion
/// autoencoder in this codebase has one. Instead the checkpoint carries a batch norm's running
/// mean and variance over the **packed** 128-channel latent, with no affine weight or bias at
/// all, and the transformer works in the space those put it in. Skipping this step does not
/// fail: it hands the transformer a latent off by a per-channel scale, and four denoising steps
/// later that is a washed-out image with no obvious cause.
///
/// Stated in packed NCHW because that is the space the reference states them in — after
/// `patchify`, before the tokens are flattened.
final class Flux2BatchNormStats: Module {
    @ParameterInfo(key: "running_mean") var mean: MLXArray
    @ParameterInfo(key: "running_var") var variance: MLXArray

    private let eps: Float

    init(channels: Int, eps: Float) {
        self.eps = eps
        _mean.wrappedValue = MLXArray.zeros([channels])
        _variance.wrappedValue = MLXArray.ones([channels])
    }

    /// `[batch, 128, height, width]` packed latent to the transformer's space.
    func normalize(_ packed: MLXArray) -> MLXArray {
        let (centre, spread) = broadcastable()
        return ((packed.asType(.float32) - centre) / spread).asType(packed.dtype)
    }

    /// The inverse, for the latent the denoising loop leaves behind.
    func denormalize(_ packed: MLXArray) -> MLXArray {
        let (centre, spread) = broadcastable()
        return (packed.asType(.float32) * spread + centre).asType(packed.dtype)
    }

    /// The two statistics as `[1, channels, 1, 1]` in float32.
    ///
    /// The checkpoint stores them in bfloat16, which has eight bits of mantissa; taking a square
    /// root at that precision and dividing a whole latent by it is a needless loss when the
    /// tensors involved are 128 numbers long.
    private func broadcastable() -> (MLXArray, MLXArray) {
        let shape = [1, mean.dim(0), 1, 1]
        return (
            mean.asType(.float32).reshaped(shape),
            MLX.sqrt(variance.asType(.float32).reshaped(shape) + eps)
        )
    }
}
