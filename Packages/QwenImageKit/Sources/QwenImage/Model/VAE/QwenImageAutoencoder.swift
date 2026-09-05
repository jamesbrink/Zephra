import Foundation
import MLX
import MLXNN
import ZephraMLX

/// Qwen-Image's autoencoder, both ways.
///
/// Text-to-image never encodes — the pipeline starts from noise — but starting from a picture
/// does, so the encoder is built and loaded alongside the decoder. It costs 107 MB: measured
/// from the shipped 4-bit build's `vae/diffusion_pytorch_model.safetensors`, where the 84
/// encoder tensors plus `quant_conv` come to 107.2 MB of bfloat16 against the decoder's 146.6 MB.
/// That is half a percent of the model's 21.5 GB, which is why it is unconditional rather than
/// lazy: a nil module rebuilt on demand would have to keep the shard mapped for the life of the
/// pipeline to have anything to fill itself from, and would buy a rounding error.
public final class QwenImageAutoencoder: Module {
    @ModuleInfo(key: "post_quant_conv") var postQuantization: Conv2d
    @ModuleInfo(key: "quant_conv") var quantization: Conv2d
    @ModuleInfo(key: "decoder") var decoder: QwenImageVAEDecoder
    @ModuleInfo(key: "encoder") var encoder: QwenImageVAEEncoder

    // Held as plain floats, not MLXArrays: a bare MLXArray property on a Module is treated as a
    // learnable parameter, and these are configuration.
    private let latentsMean: [Float]
    private let latentsStandardDeviation: [Float]
    private let latentChannels: Int
    // From the configuration, so a tiled decode of a doll's-house autoencoder cuts the tiles to
    // the size that autoencoder actually produces; on the published model, eight.
    private let pixelsPerCell: Int

    /// Builds the autoencoder described by `configuration`. Weights arrive separately.
    public init(_ configuration: QwenImageVAEConfiguration) {
        _postQuantization.wrappedValue = Conv2d(
            inputChannels: configuration.zDim, outputChannels: configuration.zDim,
            kernelSize: 1)
        // Twice as wide as its sibling: `quant_conv` sees the mean and the log-variance the
        // encoder produces together, and `post_quant_conv` sees only the sampled latent.
        _quantization.wrappedValue = Conv2d(
            inputChannels: configuration.zDim * 2, outputChannels: configuration.zDim * 2,
            kernelSize: 1)
        _decoder.wrappedValue = QwenImageVAEDecoder(configuration)
        _encoder.wrappedValue = QwenImageVAEEncoder(configuration)
        latentsMean = configuration.latentsMean.map(Float.init)
        latentsStandardDeviation = configuration.latentsStd.map(Float.init)
        latentChannels = configuration.zDim
        pixelsPerCell = configuration.spatialScale
    }

    /// Turns latents into an image in the range -1 to 1.
    ///
    /// - Parameters:
    ///   - latents: `[batch, channels, height, width]`, as the denoising loop leaves them —
    ///     still on the normalised scale the transformer works in.
    ///   - tile: The latent-space tile edge to decode in, or nil to decode the whole latent
    ///     exactly. The decode allocates in proportion to the image, not to the weights, so
    ///     this is the knob that decides a generation's peak; the host chooses it per run.
    /// - Returns: `[batch, height, width, 3]`.
    public func decode(_ latents: MLXArray, tile: Int? = nil) -> MLXArray {
        let denormalized = denormalized(latents)
        // Tiling is applied around the whole decode, `post_quant_conv` included: it is a 1x1
        // convolution, so it commutes with taking a tile and there is nothing to be gained by
        // holding the full-resolution result of it live.
        let pixels =
            if let tile, tile < Swift.max(denormalized.dim(1), denormalized.dim(2)) {
                TiledDecode.run(denormalized, tile: tile, scale: pixelsPerCell) {
                    decoder(postQuantization($0))
                }
            } else {
                decoder(postQuantization(denormalized))
            }
        return MLX.clip(pixels, min: MLXArray(Float(-1)), max: MLXArray(Float(1)))
    }

    /// The same decode with the tiling never applied: what a preview frame takes, a latent
    /// pooled to 32 cells an edge being smaller than any tile worth cutting.
    func decodeUntiled(_ latents: MLXArray) -> MLXArray {
        MLX.clip(
            decoder(postQuantization(denormalized(latents))),
            min: MLXArray(Float(-1)), max: MLXArray(Float(1)))
    }

    /// The latent on the autoencoder's own scale, channels last.
    ///
    /// Undoing the per-channel normalisation the latent space is expressed in is what this is:
    /// getting it wrong washes the image out or oversaturates it rather than failing.
    private func denormalized(_ latents: MLXArray) -> MLXArray {
        latents.transposed(0, 2, 3, 1) * MLXArray(latentsStandardDeviation)
            + MLXArray(latentsMean)
    }

    /// Turns an image into latents on the scale the denoising loop works in.
    ///
    /// The exact inverse of `decode`, read bottom to top: encode, `quant_conv`, take the
    /// distribution's mode, normalise. Taking the mode — the first `zDim` channels, which are
    /// the mean — rather than sampling from the distribution is what keeps a seeded generation
    /// reproducible; the reference offers both and image-to-image pipelines use the mode.
    ///
    /// - Parameter pixels: `[batch, height, width, 3]` in the range -1 to 1, which is the shape
    ///   and the scale `decode` returns.
    /// - Returns: `[batch, channels, height / 8, width / 8]`, ready for
    ///   `QwenImageLatentPacking.pack`.
    public func encode(_ pixels: MLXArray) -> MLXArray {
        let parameters = quantization(encoder(pixels))
        let mode = parameters[0..., 0..., 0..., 0 ..< latentChannels]
        let normalized =
            (mode - MLXArray(latentsMean)) / MLXArray(latentsStandardDeviation)
        return normalized.transposed(0, 3, 1, 2)
    }

    /// Loads the autoencoder's weights, converting them from the published 3-D video layout.
    public func load(weights: [String: MLXArray]) throws {
        let wanted = Set(parameters().flattened().map(\.0))
        let relevant = weights.filter { wanted.contains($0.key) }
        try update(
            parameters: ModuleParameters.unflattened(QwenImageVAEWeights.sanitized(relevant)),
            verify: .all)
    }
}
