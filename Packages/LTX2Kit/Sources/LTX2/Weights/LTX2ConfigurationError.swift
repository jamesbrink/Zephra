import Foundation

/// What can be wrong with a pack's configuration before a weight is read.
public enum LTX2ConfigurationError: Error, Equatable, Sendable {
    /// `layer_types` names a different number of layers than `num_hidden_layers`.
    case layerTypesDoNotMatchDepth(types: Int, layers: Int)
    /// A file the pack must carry is not there.
    case missingFile(URL)
}
