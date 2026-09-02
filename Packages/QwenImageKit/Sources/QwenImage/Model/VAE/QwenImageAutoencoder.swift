import Foundation
import MLX
import MLXNN

/// Qwen-Image's autoencoder, decoding only.
///
/// Text-to-image never encodes: the pipeline starts from noise, and only editing needs an image
/// turned into latents. So the encoder is not built and its weights are not loaded.
public final class QwenImageAutoencoder: Module {
    @ModuleInfo(key: "post_quant_conv") var postQuantization: Conv2d
    @ModuleInfo(key: "decoder") var decoder: QwenImageVAEDecoder

    // Held as plain floats, not MLXArrays: a bare MLXArray property on a Module is treated as a
    // learnable parameter, and these are configuration.
    private let latentsMean: [Float]
    private let latentsStandardDeviation: [Float]

    /// Builds the decoder described by `configuration`. Weights arrive separately.
    public init(_ configuration: QwenImageVAEConfiguration) {
        _postQuantization.wrappedValue = Conv2d(
            inputChannels: configuration.zDim, outputChannels: configuration.zDim,
            kernelSize: 1)
        _decoder.wrappedValue = QwenImageVAEDecoder(configuration)
        latentsMean = configuration.latentsMean.map(Float.init)
        latentsStandardDeviation = configuration.latentsStd.map(Float.init)
    }

    /// Turns latents into an image in the range -1 to 1.
    ///
    /// - Parameter latents: `[batch, channels, height, width]`, as the denoising loop leaves
    ///   them — still on the normalised scale the transformer works in.
    /// - Returns: `[batch, height, width, 3]`.
    public func decode(_ latents: MLXArray) -> MLXArray {
        // Undo the per-channel normalisation the latent space is expressed in. Getting this
        // wrong washes the image out or oversaturates it rather than failing.
        let channelsLast = latents.transposed(0, 2, 3, 1)
        let denormalized =
            channelsLast * MLXArray(latentsStandardDeviation) + MLXArray(latentsMean)
        let pixels = decoder(postQuantization(denormalized))
        return MLX.clip(pixels, min: MLXArray(Float(-1)), max: MLXArray(Float(1)))
    }

    /// Loads decoder weights, converting them from the published 3-D video layout.
    public func load(weights: [String: MLXArray]) throws {
        let wanted = Set(parameters().flattened().map(\.0))
        let relevant = weights.filter { wanted.contains($0.key) }
        try update(
            parameters: ModuleParameters.unflattened(QwenImageVAEWeights.sanitized(relevant)),
            verify: .all)
    }
}
