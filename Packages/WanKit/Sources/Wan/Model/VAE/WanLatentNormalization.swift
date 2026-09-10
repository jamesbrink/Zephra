import Foundation
import MLX

/// The latent's per-channel mean and standard deviation from `vae/config.json`, which stand
/// between the autoencoder's space and the transformer's.
///
/// The reference pipeline keeps these outside the autoencoder: `encode` hands back the raw
/// mean and the pipeline subtracts `latents_mean` and multiplies by `1 / latents_std` before
/// the transformer sees it; before `decode` it runs the same the other way. This type is that
/// pair of lines, over a latent held channels-first as every loop holds it, `[batch, channels,
/// frames, height, width]`.
public struct WanLatentNormalization: Hashable, Sendable {
    public let mean: [Float]
    public let std: [Float]

    public init(mean: [Float], std: [Float]) {
        precondition(mean.count == std.count, "one mean and one standard deviation per channel")
        self.mean = mean
        self.std = std
    }

    public init(_ configuration: WanVAEConfiguration) {
        self.init(mean: configuration.latentsMean, std: configuration.latentsStd)
    }

    /// The real release's statistics.
    public static let wan22 = WanLatentNormalization(.wan22)

    /// The latent in the transformer's space: `(z - mean) / std`.
    public func normalize(_ latent: MLXArray) -> MLXArray {
        (latent - column(mean, like: latent)) / column(std, like: latent)
    }

    /// The latent in the autoencoder's space: `z * std + mean`.
    public func denormalize(_ latent: MLXArray) -> MLXArray {
        latent * column(std, like: latent) + column(mean, like: latent)
    }

    /// `values` shaped to broadcast down the channel axis of a channels-first latent.
    private func column(_ values: [Float], like latent: MLXArray) -> MLXArray {
        MLXArray(values).reshaped([1, values.count, 1, 1, 1]).asType(latent.dtype)
    }
}
