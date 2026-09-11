import Foundation

/// The shape of the audio autoencoder's decoder, with LTX-2.5's values as the one instance.
///
/// The pack ships no configuration for it, so the shape is written down here from the
/// checkpoint's own tensors: a 128-channel base widened by `(1, 2, 4)` over three levels, two
/// residual blocks plus one per level, eight latent channels over sixteen latent mel bins that
/// decode to sixty-four, four mel frames a latent frame, and a stereo mel out.
public struct LTX2AudioDecoderLayout: Hashable, Sendable {
    /// Latent channels per latent mel bin.
    public var latentChannels: Int
    /// Latent mel bins; the decoder widens them by the level count's power of two.
    public var latentMelBins: Int
    /// The channel width the first level is a multiple of.
    public var baseChannels: Int
    /// The width multiplier of each level, lowest first.
    public var multipliers: [Int]
    /// Residual blocks per level, one more than the encoder's.
    public var blocksPerLevel: Int
    /// Mel channels out: two, one per stereo channel.
    public var outputChannels: Int
    /// Mel frames one latent frame decodes to, the first frame on its own.
    public var temporalFactor: Int
    /// The pixel norm's epsilon, the reference's 1e-6 for this autoencoder.
    public var normEpsilon: Float

    public init(
        latentChannels: Int, latentMelBins: Int, baseChannels: Int, multipliers: [Int],
        blocksPerLevel: Int, outputChannels: Int, temporalFactor: Int, normEpsilon: Float
    ) {
        self.latentChannels = latentChannels
        self.latentMelBins = latentMelBins
        self.baseChannels = baseChannels
        self.multipliers = multipliers
        self.blocksPerLevel = blocksPerLevel
        self.outputChannels = outputChannels
        self.temporalFactor = temporalFactor
        self.normEpsilon = normEpsilon
    }

    /// The real LTX-2.5 audio decoder.
    public static let ltx25 = LTX2AudioDecoderLayout(
        latentChannels: 8, latentMelBins: 16, baseChannels: 128, multipliers: [1, 2, 4],
        blocksPerLevel: 3, outputChannels: 2, temporalFactor: 4, normEpsilon: 1e-6)

    /// Channels at `level`.
    public func channels(at level: Int) -> Int { baseChannels * multipliers[level] }

    /// Mel bins out: the latent bins doubled at every level but the lowest.
    public var melBins: Int { latentMelBins << (multipliers.count - 1) }

    /// Mel frames `latentFrames` decode to: four a frame, less the three the causal first
    /// frame does without.
    public func melFrames(forLatentFrames latentFrames: Int) -> Int {
        max(latentFrames * temporalFactor - (temporalFactor - 1), 1)
    }

    /// The packed width the transformer's audio tokens have: every channel of every bin.
    public var packedChannels: Int { latentChannels * latentMelBins }
}
