import Foundation
import MLX
import MLXNN

/// The latent's per-channel mean and standard deviation, which the encoder divides out of what
/// it produces: the autoencoder works in its own space and the transformer in a normalised one.
///
/// A different pair from the decoder's, under different names. The pack spells the decoder's
/// `per_channel_statistics.{mean,std}` and the encoder's `._mean_of_means` and `._std_of_means`,
/// leading underscores and all, because the official checkpoint registers them as buffers with
/// those names. This tree drops the underscores, because mlx-swift's parameter filter drops any
/// key that begins with one: spelled the pack's way these two would load and normalise
/// correctly and then be invisible to `parameters()` — so nothing that walks the tree would
/// evaluate them, and the key check that exists to notice a missing statistic would not see
/// them either. `LTX2VAEWeights` renames them at the door, both ways.
///
/// Getting either wrong leaves the pair at the identity and hands the transformer a latent
/// scaled wrongly by a factor per channel, which is exactly what the parity fixture's
/// randomised statistics exist to catch.
final class LTX2EncoderStatistics: Module {
    @ParameterInfo(key: "mean_of_means") var mean: MLXArray
    @ParameterInfo(key: "std_of_means") var std: MLXArray

    init(channels: Int) {
        _mean.wrappedValue = MLXArray.zeros([channels])
        _std.wrappedValue = MLXArray.ones([channels])
    }

    /// The latent in the transformer's space, channels last.
    func normalised(_ latent: MLXArray) -> MLXArray {
        (latent - mean.asType(latent.dtype)) / std.asType(latent.dtype)
    }
}
