import Foundation

/// What can be wrong with a snapshot's configuration before a single weight is read.
///
/// Each case is an invariant the rest of the package assumes and that produces a plausible but
/// wrong image, rather than a crash, when it is violated.
public enum QwenImage21ConfigurationError: Error, LocalizedError, Equatable {
    /// A configuration file the snapshot must carry is not there.
    case missingConfiguration(name: String, directory: URL)
    /// A file is there but is not the JSON this port reads.
    case malformedConfiguration(name: String, directory: URL)
    /// A field the port reads but implements only one value of asks for another.
    case unsupportedValue(field: String, value: String)
    /// The rotary axes must partition the head's width exactly.
    case ropeAxesDoNotSumToHeadDim(axes: [Int], headDim: Int)
    /// Each rotary axis is split into cosine and sine halves, so each must be even.
    case ropeAxisIsOdd(axes: [Int])
    /// The text stream arriving from the encoder must be the transformer's own width.
    case contextWidthIsNotTheEncoder(context: Int, hidden: Int)
    /// The transformer's channels a token must be the latent's channels: 2.1 does not patchify.
    case channelsDoNotMatchLatent(inChannels: Int, latentChannels: Int)
    /// Attention shapes assume the query heads group over the key-value heads.
    case headsDoNotDivide(heads: Int, keyValueHeads: Int)
    /// The per-channel latent statistics must be one value per latent channel.
    case latentStatisticsAreTheWrongLength(mean: Int, std: Int, channels: Int)
    /// `model_index.json` names a component this port does not implement.
    case unexpectedComponentClass(component: String, className: String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration(let name, let directory):
            "No \(name) in \(directory.path(percentEncoded: false))."
        case .malformedConfiguration(let name, let directory):
            "\(name) in \(directory.path(percentEncoded: false)) is not the JSON this port reads."
        case .unsupportedValue(let field, let value):
            "This port does not implement \(field) = \(value); the image would be silently wrong."
        case .ropeAxesDoNotSumToHeadDim(let axes, let headDim):
            "Rotary axes \(axes) sum to \(axes.reduce(0, +)), not the head width \(headDim)."
        case .ropeAxisIsOdd(let axes):
            "Rotary axes \(axes) must all be even; each is split into a cosine and a sine half."
        case .contextWidthIsNotTheEncoder(let context, let hidden):
            "The transformer reads \(context)-wide text from a \(hidden)-wide encoder."
        case .channelsDoNotMatchLatent(let inChannels, let latentChannels):
            "The transformer takes \(inChannels) channels a token from a \(latentChannels)-channel latent; 2.1 has no patchify to make up the difference."
        case .headsDoNotDivide(let heads, let keyValueHeads):
            "\(heads) query heads cannot be grouped over \(keyValueHeads) key-value heads."
        case .latentStatisticsAreTheWrongLength(let mean, let std, let channels):
            "The latent statistics are \(mean) means and \(std) deviations for \(channels) channels."
        case .unexpectedComponentClass(let component, let className):
            "model_index.json names \(component) as \(className), which this port does not implement."
        }
    }
}
