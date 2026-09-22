import Foundation
import MLX

/// The latent's per-channel mean and standard deviation from `vae/config.json`, which stand
/// between the autoencoder's space and the transformer's.
///
/// The reference pipeline keeps these outside the autoencoder: `_encode_vae_image` hands back
/// the posterior's mode and the pipeline subtracts `latents_mean` and divides by `latents_std`
/// before the transformer sees it; before `decode` it runs the same the other way,
/// `latents * latents_std + latents_mean`. This type is that pair of lines.
///
/// The statistics are **read from the published file**, never written down here: there are 64
/// of each, none of them near zero or one, and a statistic transcribed wrong shifts every
/// colour by a plausible amount instead of failing.
public struct QwenImage21LatentNormalization: Hashable, Sendable {
    public let mean: [Float]
    public let std: [Float]

    public init(mean: [Float], std: [Float]) {
        precondition(mean.count == std.count, "one mean and one deviation per channel")
        self.mean = mean
        self.std = std
    }

    public init(_ configuration: QwenImage21VAEConfiguration) {
        self.init(
            mean: configuration.latentsMean.map(Float.init),
            std: configuration.latentsStd.map(Float.init))
    }

    /// The latent in the transformer's space: `(z - mean) / std`. Applied after an encode.
    ///
    /// - Parameter latent: channels last, `[batch, height, width, channels]`, which is how the
    ///   autoencoder hands one back.
    public func normalize(_ latent: MLXArray) -> MLXArray {
        (latent - row(mean, like: latent)) / row(std, like: latent)
    }

    /// The latent in the autoencoder's space: `z * std + mean`. Applied before a decode.
    public func denormalize(_ latent: MLXArray) -> MLXArray {
        latent * row(std, like: latent) + row(mean, like: latent)
    }

    /// `values` shaped to broadcast along the last axis of a channels-last latent.
    private func row(_ values: [Float], like latent: MLXArray) -> MLXArray {
        MLXArray(values).reshaped([1, 1, 1, values.count]).asType(latent.dtype)
    }
}
