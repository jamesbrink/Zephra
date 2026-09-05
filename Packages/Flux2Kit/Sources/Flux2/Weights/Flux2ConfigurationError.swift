import Foundation

/// What can be wrong with a snapshot's configuration before a single weight is read.
///
/// Each case is an invariant the rest of the package assumes and that produces a plausible but
/// wrong image, rather than a crash, when it is violated.
public enum Flux2ConfigurationError: Error, LocalizedError, Equatable {
    /// The rotary axes must partition the head's width exactly.
    case ropeAxesDoNotSumToHeadDim(axes: [Int], headDim: Int)
    /// Each rotary axis is split into cosine and sine halves, so each must be even.
    case ropeAxisIsOdd(axes: [Int])
    /// The text stream's width must be the encoder's width times the number of layers tapped.
    case jointDimIsNotTheTaps(joint: Int, hidden: Int, taps: Int)
    /// The encoder must have at least as many layers as the deepest tap.
    case hiddenStateTapBeyondStack(tap: Int, layers: Int)
    /// The attention shapes assume these divide.
    case textEncoderHeadsDoNotDivide(heads: Int, keyValueHeads: Int)
    /// Group normalisation needs the group count to divide every stage's width.
    case groupsDoNotDivideChannels(groups: Int, channels: [Int])
    /// The latent is packed two by two; anything else changes the channel count.
    case unexpectedPatchSize([Int])
    /// A configuration file the snapshot must carry is not there.
    case missingConfiguration(name: String, directory: URL)
    /// A field the port reads but implements only one value of asks for another.
    case unsupportedValue(field: String, value: String)
    /// The transformer's channels per token must be the latent's channels times the patch.
    case channelsDoNotMatchLatent(inChannels: Int, latentChannels: Int, patch: Int)

    public var errorDescription: String? {
        switch self {
        case .ropeAxesDoNotSumToHeadDim(let axes, let headDim):
            "Rotary axes \(axes) sum to \(axes.reduce(0, +)), not the head width \(headDim)."
        case .ropeAxisIsOdd(let axes):
            "Rotary axes \(axes) must all be even; each is split into a cosine and a sine half."
        case .jointDimIsNotTheTaps(let joint, let hidden, let taps):
            "The transformer reads \(joint)-wide text, but \(taps) taps of a \(hidden)-wide encoder make \(hidden * taps)."
        case .hiddenStateTapBeyondStack(let tap, let layers):
            "The conditioning taps layer \(tap) of an encoder with \(layers) layers."
        case .textEncoderHeadsDoNotDivide(let heads, let keyValueHeads):
            "\(heads) query heads cannot be grouped over \(keyValueHeads) key-value heads."
        case .groupsDoNotDivideChannels(let groups, let channels):
            "\(groups) normalisation groups do not divide every stage width in \(channels)."
        case .unexpectedPatchSize(let size):
            "The autoencoder packs latents \(size) at a time; this port assumes 2 by 2."
        case .missingConfiguration(let name, let directory):
            "No \(name) in \(directory.path(percentEncoded: false))."
        case .unsupportedValue(let field, let value):
            "This port does not implement \(field) = \(value); the image would be silently wrong."
        case .channelsDoNotMatchLatent(let inChannels, let latentChannels, let patch):
            "The transformer takes \(inChannels) channels a token, but a \(latentChannels)-channel latent packed \(patch) by \(patch) gives \(latentChannels * patch * patch)."
        }
    }
}
