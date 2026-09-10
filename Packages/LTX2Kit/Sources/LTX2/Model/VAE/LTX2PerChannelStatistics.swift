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
///
/// The latent upsampler works in the autoencoder's space too, so `LTX2LatentUpsampler` is
/// handed the decoder's pair and runs both directions around its network; that is why the
/// type is public and carries the inverse as well.
public final class LTX2PerChannelStatistics: Module {
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

    /// The latent back in the transformer's space, channels last: the inverse of
    /// `denormalised`, as the generation pipeline normalises a latent handed to it.
    func normalised(_ latent: MLXArray) -> MLXArray {
        (latent - mean.asType(latent.dtype)) / std.asType(latent.dtype)
    }
}
