import Foundation

/// `vae/config.json`: the shape of the Wan 2.2 video autoencoder.
///
/// Only the residual (2.2) layout is ported, `is_residual: true` with an averaged-down shortcut
/// around every encoder stage and a duplicated-up one around every decoder stage; the 2.1
/// layout without them shares no checkpoint with this model and is refused at read time. So is
/// any `attn_scales` entry, since this checkpoint attends only in the mid block.
public struct WanVAEConfiguration: Hashable, Sendable {
    /// Width of the encoder's first stage; each later stage is this times `dimMult`.
    public let baseDim: Int
    /// The same for the decoder, which is wider than the encoder in 2.2.
    public let decoderBaseDim: Int
    /// Stage widths as multiples of the base, first to last on the way in.
    public let dimMult: [Int]
    /// Residual blocks per encoder stage; a decoder stage holds one more.
    public let numResBlocks: Int
    /// Whether the downsampler after each stage but the last also halves time; the decoder
    /// doubles time in the mirror image.
    public let temporalDownsample: [Bool]
    /// Latent channels; the encoder writes twice as many, a mean and a log-variance.
    public let zDim: Int
    /// Channels `conv_in` reads: three colours times the patch squared.
    public let inChannels: Int
    /// Channels `conv_out` writes, unpatchified back to three colours.
    public let outChannels: Int
    /// The spatial pixel shuffle at both doors.
    public let patchSize: Int
    /// Per-channel mean of the latent, which the transformer works without.
    public let latentsMean: [Float]
    /// Per-channel standard deviation of the latent.
    public let latentsStd: [Float]

    /// Widths of the encoder's stages, `conv_in`'s output first.
    var encoderWidths: [Int] { ([1] + dimMult).map { baseDim * $0 } }
    /// Widths of the decoder's stages, `conv_in`'s output first: the encoder's read backwards.
    var decoderWidths: [Int] { ([dimMult[dimMult.count - 1]] + dimMult.reversed()).map { decoderBaseDim * $0 } }

    /// Pixels per latent cell: the patch times a halving per downsampler.
    public var spatialCompression: Int { patchSize << (dimMult.count - 1) }
    /// Pixel frames per latent frame after the first.
    public var temporalCompression: Int { 1 << temporalDownsample.filter { $0 }.count }

    /// Latent frames a clip of `pixelFrames` encodes to: the first frame alone, then one per
    /// `temporalCompression`.
    public func latentFrames(forPixelFrames pixelFrames: Int) -> Int {
        1 + (pixelFrames - 1) / temporalCompression
    }

    /// Pixel frames a latent of `latentFrames` decodes to.
    public func pixelFrames(forLatentFrames latentFrames: Int) -> Int {
        1 + (latentFrames - 1) * temporalCompression
    }

    public init(
        baseDim: Int, decoderBaseDim: Int, dimMult: [Int], numResBlocks: Int,
        temporalDownsample: [Bool], zDim: Int, inChannels: Int, outChannels: Int, patchSize: Int,
        latentsMean: [Float], latentsStd: [Float]
    ) {
        self.baseDim = baseDim
        self.decoderBaseDim = decoderBaseDim
        self.dimMult = dimMult
        self.numResBlocks = numResBlocks
        self.temporalDownsample = temporalDownsample
        self.zDim = zDim
        self.inChannels = inChannels
        self.outChannels = outChannels
        self.patchSize = patchSize
        self.latentsMean = latentsMean
        self.latentsStd = latentsStd
    }

    /// Reads a release's `vae/config.json`.
    public init(readingFrom url: URL) throws {
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        guard file.isResidual == true else { throw WanVAEConfigurationError.notResidual }
        guard file.attnScales?.isEmpty ?? true else { throw WanVAEConfigurationError.attentionOutsideMidBlock }
        guard file.latentsMean.count == file.zDim, file.latentsStd.count == file.zDim else {
            throw WanVAEConfigurationError.statisticsDoNotMatchLatent(
                means: file.latentsMean.count, stds: file.latentsStd.count, channels: file.zDim)
        }
        self.init(
            baseDim: file.baseDim, decoderBaseDim: file.decoderBaseDim ?? file.baseDim,
            dimMult: file.dimMult, numResBlocks: file.numResBlocks,
            temporalDownsample: file.temperalDownsample, zDim: file.zDim,
            inChannels: file.inChannels, outChannels: file.outChannels,
            patchSize: file.patchSize ?? 1, latentsMean: file.latentsMean, latentsStd: file.latentsStd)
    }

    struct File: Decodable {
        let baseDim, numResBlocks, zDim, inChannels, outChannels: Int
        let decoderBaseDim, patchSize: Int?
        let dimMult: [Int]
        let attnScales: [Float]?
        let temperalDownsample: [Bool]
        let isResidual: Bool?
        let latentsMean, latentsStd: [Float]
        enum CodingKeys: String, CodingKey {
            case baseDim = "base_dim", decoderBaseDim = "decoder_base_dim", dimMult = "dim_mult"
            case numResBlocks = "num_res_blocks", attnScales = "attn_scales"
            // The reference spells it this way, and the file follows the reference.
            case temperalDownsample = "temperal_downsample", zDim = "z_dim"
            case inChannels = "in_channels", outChannels = "out_channels", patchSize = "patch_size"
            case isResidual = "is_residual", latentsMean = "latents_mean", latentsStd = "latents_std"
        }
    }
}
