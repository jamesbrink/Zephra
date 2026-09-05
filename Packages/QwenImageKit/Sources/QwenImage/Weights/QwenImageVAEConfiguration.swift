import Foundation

/// `vae/config.json`: the shape of the 3-D causal autoencoder.
///
/// Note `temperalDownsample`. The misspelling is in the published config, so it is in the coding
/// key too; renaming it here would simply stop the file decoding.
public struct QwenImageVAEConfiguration: Hashable, Sendable, Decodable {
    /// Feature width at full resolution, multiplied up by `dimMult` at each stage.
    public let baseDim: Int
    /// Latent channels.
    public let zDim: Int
    /// Width multiplier per stage, coarsest last.
    public let dimMult: [Int]
    /// Residual blocks per stage.
    public let numResBlocks: Int
    /// Resolutions carrying an attention block. Empty for Qwen-Image: the only attention in the
    /// autoencoder is the one in the middle block.
    public let attnScales: [Double]
    /// Which stages also halve the time axis. A still image is one frame, so these are no-ops on
    /// the frame axis, but they still decide how the convolutions are shaped.
    public let temperalDownsample: [Bool]
    /// Per-channel mean of the latent distribution, used to denormalize before decoding.
    public let latentsMean: [Double]
    /// Per-channel standard deviation of the latent distribution.
    public let latentsStd: [Double]

    /// How much smaller the latent is than the image, on each spatial axis.
    public var spatialScale: Int { 1 << (dimMult.count - 1) }

    enum CodingKeys: String, CodingKey {
        case baseDim = "base_dim"
        case zDim = "z_dim"
        case dimMult = "dim_mult"
        case numResBlocks = "num_res_blocks"
        case attnScales = "attn_scales"
        case temperalDownsample = "temperal_downsample"
        case latentsMean = "latents_mean"
        case latentsStd = "latents_std"
    }

    /// Checks that the per-channel normalization covers every latent channel — getting this
    /// wrong yields a washed-out or oversaturated image rather than an error — and that no
    /// stage asks for an attention block, which the port does not build outside the middle.
    public func validated() throws -> Self {
        guard attnScales.isEmpty else {
            throw QwenImageConfigurationError.unsupportedValue(
                field: "attn_scales", value: String(describing: attnScales))
        }
        guard latentsMean.count == zDim, latentsStd.count == zDim else {
            throw QwenImageConfigurationError.latentStatisticsDoNotCoverChannels(
                mean: latentsMean.count, standardDeviation: latentsStd.count, channels: zDim)
        }
        return self
    }
}
