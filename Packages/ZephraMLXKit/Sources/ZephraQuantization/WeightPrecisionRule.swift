import Foundation

/// One decision about a family of tensors: pack them this finely, or leave them alone.
///
/// A skip is not a separate mechanism here. It is a rule that resolves to no precision, which
/// is what lets one ordered list express both "never touch the norms" and "keep the modulation
/// layers at eight bits while everything else goes to four".
public struct WeightPrecisionRule: Hashable, Sendable {
    /// Which tensors this rule speaks for.
    public let pattern: NamePattern
    /// How finely to pack them, or nil to copy them across untouched.
    public let precision: QuantizationPrecision?

    /// Creates a rule. Pass a nil precision to exclude the matching tensors from packing.
    public init(_ pattern: NamePattern, precision: QuantizationPrecision?) {
        self.pattern = pattern
        self.precision = precision
    }

    /// The tensors that no published export packs, whatever the architecture.
    ///
    /// Norms and embeddings are small, are read at full width, and lose disproportionately when
    /// squeezed. Packing one also breaks the loader: it decides what was quantized by looking
    /// for a matching `.scales` key, so a tensor packed here that the reference build left alone
    /// stops the module tree matching the weights.
    public static let normsAndEmbeddings: [WeightPrecisionRule] = [
        WeightPrecisionRule(.contains("embed"), precision: nil),
        WeightPrecisionRule(.contains("norm"), precision: nil),
    ]
}
