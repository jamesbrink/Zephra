import Foundation

/// What can be wrong with a snapshot's configuration before a single weight is read.
///
/// Each case is an invariant the rest of the package assumes and that produces a plausible but
/// wrong image, rather than a crash, when it is violated.
public enum QwenImageConfigurationError: Error, LocalizedError, Equatable {
    /// The rotary axes must partition the head's width exactly.
    case ropeAxesDoNotSumToHeadDim(axes: [Int], headDim: Int)
    /// Each rotary axis is split into cosine and sine halves, so each must be even.
    case ropeAxisIsOdd(axes: [Int])
    /// The latent normalization must name every latent channel.
    case latentStatisticsDoNotCoverChannels(
        mean: Int, standardDeviation: Int, channels: Int)
    /// The attention shapes assume these divide.
    case textEncoderHeadsDoNotDivide(hidden: Int, heads: Int, keyValueHeads: Int)
    /// A configuration file the snapshot must carry is not there.
    case missingConfiguration(name: String, directory: URL)

    public var errorDescription: String? {
        switch self {
        case .ropeAxesDoNotSumToHeadDim(let axes, let headDim):
            "Rotary axes \(axes) sum to \(axes.reduce(0, +)), not the head width \(headDim)."
        case .ropeAxisIsOdd(let axes):
            "Rotary axes \(axes) must all be even; each is split into a cosine and a sine half."
        case .latentStatisticsDoNotCoverChannels(let mean, let deviation, let channels):
            "The VAE names \(mean) latent means and \(deviation) deviations for \(channels) channels."
        case .textEncoderHeadsDoNotDivide(let hidden, let heads, let keyValueHeads):
            "A \(hidden)-wide encoder cannot be split into \(heads) heads over \(keyValueHeads) key-value heads."
        case .missingConfiguration(let name, let directory):
            "No \(name) in \(directory.path(percentEncoded: false))."
        }
    }
}
