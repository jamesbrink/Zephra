import Foundation

/// One directory of a snapshot whose linear weights get packed, and the rules deciding how.
///
/// Rules are tried in order and the first match wins, so a component reads as a short list of
/// exceptions followed by what happens to everything else. That ordering is the whole interface:
/// put the narrow rules first.
public struct QuantizedComponent: Hashable, Sendable {
    /// The subdirectory the component's shards live in, in both the source and the output.
    public let directoryName: String
    /// Exceptions, most specific first.
    public let rules: [WeightPrecisionRule]
    /// What happens to a tensor no rule claims, or nil to leave the rest of the component alone.
    public let fallback: QuantizationPrecision?
    /// Tensors left out of the build entirely.
    ///
    /// Distinct from a rule that resolves to no precision: that one copies the tensor across
    /// unpacked, which is right for a norm the model reads at full width and wrong for a
    /// component nothing ever loads. A checkpoint often carries both.
    public let omitted: [NamePattern]
    /// Low-rank adapter files merged into these weights before they are packed.
    ///
    /// Merging at build time rather than at load is what lets a distilled variant ship as an
    /// ordinary quantized snapshot: the runtime never learns an adapter existed. Every weight an
    /// adapter names must exist in the component, or the build fails rather than applying half a
    /// distillation.
    public let adapters: [URL]

    /// Creates a component whose tensors are packed at `fallback` except where `rules` say
    /// otherwise.
    public init(
        directoryName: String,
        rules: [WeightPrecisionRule] = [],
        fallback: QuantizationPrecision?,
        omitted: [NamePattern] = [],
        adapters: [URL] = []
    ) {
        self.directoryName = directoryName
        self.rules = rules
        self.fallback = fallback
        self.omitted = omitted
        self.adapters = adapters
    }

    /// Whether this tensor is left out of the build entirely.
    public func omits(_ tensorName: String) -> Bool {
        omitted.contains { $0.matches(tensorName) }
    }

    /// How finely to pack `tensorName`, or nil to copy it across untouched.
    ///
    /// This answers only whether we *want* the tensor packed. Whether MLX *can* pack it is
    /// `QuantizableWeight`'s question, and it is asked afterwards, because the answer depends on
    /// the group size this returns.
    public func precision(for tensorName: String) -> QuantizationPrecision? {
        for rule in rules where rule.pattern.matches(tensorName) {
            return rule.precision
        }
        return fallback
    }

    /// The precisions this component can produce, for a summary line.
    var declaredPrecisions: [QuantizationPrecision] {
        (rules.compactMap(\.precision) + [fallback].compactMap { $0 })
    }
}
