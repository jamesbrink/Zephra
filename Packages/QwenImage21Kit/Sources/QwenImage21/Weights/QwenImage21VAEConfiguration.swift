import Foundation

/// `vae/config.json`: the shape of `AutoencoderKLQwenImage21`, and the statistics its latents
/// are normalised by.
///
/// **In and out channels are four.** That is 2.1's headline feature: the autoencoder carries an
/// alpha channel through, so a generation ends in a straight-alpha RGBA picture rather than an
/// opaque one. A port that reads three here is a port that silently drops transparency.
///
/// `latentsMean` and `latentsStd` are read from the file rather than written down, because a
/// wrong statistic shifts every colour by a plausible amount instead of failing.
public struct QwenImage21VAEConfiguration: Hashable, Sendable, Decodable {
    /// Width of the encoder's first stage.
    public let baseDim: Int
    /// Width of the decoder's last stage. The decoder is wider than the encoder in 2.1.
    public let decoderBaseDim: Int
    /// Latent channels.
    public let zDim: Int
    /// The width multiplier at each stage.
    public let dimMult: [Int]
    /// Residual blocks per stage.
    public let numResBlocks: Int
    /// Which stages halve the time axis. Kept because the published file carries it; the image
    /// specialisation has one frame, so nothing here ever halves anything.
    public let temperalDownsample: [Bool]
    /// Whether the stages carry a residual path. 2.1 ships true.
    public let isResidual: Bool
    /// Channels in a picture: four, with alpha.
    public let inChannels: Int
    /// Channels out of a picture: four, with alpha.
    public let outChannels: Int
    /// Pixels a latent cell covers along each edge.
    public let scaleFactorSpatial: Int
    /// Per-channel mean subtracted after encoding and added back before decoding.
    public let latentsMean: [Double]
    /// Per-channel deviation divided out after encoding and multiplied back before decoding.
    public let latentsStd: [Double]

    enum CodingKeys: String, CodingKey {
        case baseDim = "base_dim"
        case decoderBaseDim = "decoder_base_dim"
        case zDim = "z_dim"
        case dimMult = "dim_mult"
        case numResBlocks = "num_res_blocks"
        case temperalDownsample = "temperal_downsample"
        case isResidual = "is_residual"
        case inChannels = "in_channels"
        case outChannels = "out_channels"
        case scaleFactorSpatial = "scale_factor_spatial"
        case latentsMean = "latents_mean"
        case latentsStd = "latents_std"
    }

    /// The stage widths, encoder side: `baseDim` times each multiplier.
    public var encoderDims: [Int] { dimMult.map { baseDim * $0 } }

    /// Refuses the two values the port implements only one of: four picture channels, since
    /// three would mean the alpha path is dead code and nothing would say so, and one statistic
    /// per latent channel.
    public func validated() throws -> Self {
        guard inChannels == 4, outChannels == 4 else {
            throw QwenImage21ConfigurationError.unsupportedValue(
                field: "in_channels/out_channels", value: "\(inChannels)/\(outChannels)")
        }
        guard latentsMean.count == zDim, latentsStd.count == zDim else {
            throw QwenImage21ConfigurationError.latentStatisticsAreTheWrongLength(
                mean: latentsMean.count, std: latentsStd.count, channels: zDim)
        }
        return self
    }
}
