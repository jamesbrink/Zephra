import Foundation
import MLX
import MLXNN

/// The latent's per-channel mean and standard deviation, which the decoder multiplies back
/// in before its first convolution: the transformer works in normalised latent space and the
/// autoencoder in its own.
///
/// The official checkpoint spells these `std-of-means` and `mean-of-means`; the MLX pack this
/// port loads renames them `std` and `mean`, which is what the keys here are. Initialised to
/// the identity (zero mean, unit spread), so a tree that failed to load them would decode the
/// normalised latent as if it were raw -- which is exactly what the parity fixture's
/// randomised statistics exist to catch.
final class LTX2PerChannelStatistics: Module {
    @ParameterInfo(key: "mean") var mean: MLXArray
    @ParameterInfo(key: "std") var std: MLXArray

    init(channels: Int) {
        _mean.wrappedValue = MLXArray.zeros([channels])
        _std.wrappedValue = MLXArray.ones([channels])
    }

    /// The latent in the autoencoder's own space, channels last.
    func denormalised(_ latent: MLXArray) -> MLXArray {
        latent * std.asType(latent.dtype) + mean.asType(latent.dtype)
    }
}
