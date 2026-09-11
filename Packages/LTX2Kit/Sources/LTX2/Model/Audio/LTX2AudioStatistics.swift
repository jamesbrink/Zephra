import Foundation
import MLX
import MLXNN

/// The audio latent's per-channel mean and standard deviation over the packed width, the
/// pair the transformer's audio tokens are normalised by and the decoder's input is
/// denormalised with.
///
/// Over the packed `channels * melBins` width rather than the latent channels alone: the
/// reference registers `latents_mean` and `latents_std` at `base_channels`, 128, and applies
/// them to the packed token before unpacking. The pack names them `_mean_of_means` and
/// `_std_of_means`, which `LTX2AudioVAEWeights` renames, since mlx-swift drops an
/// underscored parameter from every walk of the tree.
public final class LTX2AudioStatistics: Module {
    @ParameterInfo(key: "mean") var mean: MLXArray
    @ParameterInfo(key: "std") var std: MLXArray

    init(width: Int) {
        _mean.wrappedValue = MLXArray.zeros([width])
        _std.wrappedValue = MLXArray.ones([width])
    }

    /// Packed tokens `[batch, frames, width]` from the transformer's space back to the
    /// decoder's.
    public func denormalised(_ tokens: MLXArray) -> MLXArray {
        tokens * std.asType(tokens.dtype) + mean.asType(tokens.dtype)
    }
}
