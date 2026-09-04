import Foundation
import MLX
import MLXNN
import ZephraMLX

/// FLUX.2's autoencoder, both towers, in the packed space the transformer reads.
///
/// Both public entry points speak packed latents rather than raw ones, because packing and the
/// batch-norm statistics are inseparable: the statistics are stated over the 128 packed channels
/// and mean nothing over the 32 unpacked ones. Keeping the pair inside the autoencoder is what
/// stops a caller from applying one without the other.
///
/// The encoder is built and loaded even for text-to-image, where nothing calls it. It is 42 of
/// the model's 84 million parameters and about 84 MB, which buys single-image editing with no
/// second load path and no second availability check.
public final class Flux2Autoencoder: Module {
    @ModuleInfo(key: "encoder") var encoder: Flux2VAEEncoder
    @ModuleInfo(key: "quant_conv") var quantization: Conv2d
    @ModuleInfo(key: "post_quant_conv") var postQuantization: Conv2d
    @ModuleInfo(key: "decoder") var decoder: Flux2VAEDecoder
    @ModuleInfo(key: "bn") var statistics: Flux2BatchNormStats

    /// How many pixels one latent cell becomes along each edge, for the published model: three
    /// spatial halvings, so eight, and a 64-cell tile decodes a 512-pixel square.
    public static let spatialScale = 8

    /// Latent-space tile edge for the decode, or nil to decode the whole latent exactly.
    ///
    /// The decode allocates in proportion to the image, not to the weights, so this is the knob
    /// that decides a generation's peak. Starts from `ZEPHRA_VAE_TILE` so the benchmark and the
    /// command line can set it; a host assigns it per model and the next decode picks it up.
    /// Written from the main actor and read on the inference queue: a word-sized optional cannot
    /// tear, and the worst a race can do is decode one image with the previous setting.
    public nonisolated(unsafe) static var latentTile: Int? = TiledDecode.environmentTile

    private let latentChannels: Int
    // Read from the configuration rather than from `spatialScale`, so a tiled decode of a
    // doll's-house autoencoder cuts the tiles to the size that autoencoder actually produces.
    private let pixelsPerCell: Int

    /// Builds both towers as `configuration` describes them. Weights arrive separately.
    public init(_ configuration: Flux2VAEConfiguration) {
        latentChannels = configuration.latentChannels
        pixelsPerCell = configuration.spatialScale
        _encoder.wrappedValue = Flux2VAEEncoder(configuration)
        // Two 1x1 convolutions the reference keeps outside the towers. The first sees the mean
        // and the log-variance together, so it is twice the latent width on both sides.
        _quantization.wrappedValue = Conv2d(
            inputChannels: 2 * configuration.latentChannels,
            outputChannels: 2 * configuration.latentChannels, kernelSize: 1)
        _postQuantization.wrappedValue = Conv2d(
            inputChannels: configuration.latentChannels,
            outputChannels: configuration.latentChannels, kernelSize: 1)
        _decoder.wrappedValue = Flux2VAEDecoder(configuration)
        _statistics.wrappedValue = Flux2BatchNormStats(
            channels: configuration.packedChannels, eps: configuration.batchNormEps)
    }

    /// Turns an image into the packed, normalised latent the transformer conditions on.
    ///
    /// The **mean** of the posterior, never a sample: the reference asks for `argmax`, so a
    /// reference image encodes to the same latent every time and editing is reproducible.
    ///
    /// - Parameter image: `[batch, 3, height, width]` NCHW in the range -1 to 1.
    /// - Returns: `[batch, 128, height / 16, width / 16]`.
    public func encodePacked(_ image: MLXArray) -> MLXArray {
        let moments = quantization(encoder(image.transposed(0, 2, 3, 1)))
        let mean = moments[0..., 0..., 0..., 0..<latentChannels].transposed(0, 3, 1, 2)
        return statistics.normalize(Flux2LatentPacking.patchify(mean))
    }

    /// Turns a packed latent back into pixels.
    ///
    /// - Parameter packed: `[batch, 128, height, width]`, as the denoising loop leaves it.
    /// - Returns: `[batch, height * 16, width * 16, 3]` NHWC in the range -1 to 1.
    public func decodePacked(_ packed: MLXArray) -> MLXArray {
        let latents = unpacked(packed).transposed(0, 2, 3, 1)
        // Tiling wraps `post_quant_conv` as well: it is a 1x1 convolution, so it commutes with
        // taking a tile, and holding its full-resolution result live would waste the point.
        // The tile is measured on the unpacked latent, so a 64-cell tile still means 512 pixels.
        let pixels =
            if let tile = Self.latentTile,
                tile < Swift.max(latents.dim(1), latents.dim(2))
            {
                TiledDecode.run(latents, tile: tile, scale: pixelsPerCell) {
                    decoder(postQuantization($0))
                }
            } else {
                decoder(postQuantization(latents))
            }
        return MLX.clip(pixels, min: MLXArray(Float(-1)), max: MLXArray(Float(1)))
    }

    /// The packed latent denormalised and unpacked, which is the halfway house `decodePacked`
    /// passes through. Its own name because a preview frame pools it there, between the two.
    ///
    /// - Parameter packed: `[batch, 128, height, width]`.
    /// - Returns: `[batch, 32, height * 2, width * 2]` NCHW.
    func unpacked(_ packed: MLXArray) -> MLXArray {
        Flux2LatentPacking.unpatchify(statistics.denormalize(packed))
    }

    /// The second half of `decodePacked`, never tiled: what a preview frame takes, a latent of
    /// at most 32 cells an edge being smaller than any tile worth cutting.
    ///
    /// - Parameter latents: `[batch, 32, height, width]` NCHW, as `unpacked` returns them.
    /// - Returns: `[batch, height * 8, width * 8, 3]` NHWC in the range -1 to 1.
    func decodeUntiled(_ latents: MLXArray) -> MLXArray {
        MLX.clip(
            decoder(postQuantization(latents.transposed(0, 2, 3, 1))),
            min: MLXArray(Float(-1)), max: MLXArray(Float(1)))
    }

    /// Loads the published weights, transposed and renamed for this tree.
    ///
    /// Filtering happens after the rename, not before, or `to_out.0` would be dropped as
    /// unknown. What survives has to cover every parameter exactly: `verify: .all` fails on a
    /// tensor the tree has no place for as well as on one the tree wants and the file lacks.
    public func load(weights: [String: MLXArray]) throws {
        let converted = Flux2VAEWeights.sanitized(weights)
        let wanted = Set(parameters().flattened().map(\.0))
        try update(
            parameters: ModuleParameters.unflattened(converted.filter { wanted.contains($0.key) }),
            verify: .all)
    }
}
