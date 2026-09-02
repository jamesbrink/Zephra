import Foundation

/// Everything family-specific about building one quantized snapshot.
///
/// A backend package declares one of these and hands it over; nothing else in the quantizer
/// knows which model it is converting. Adding a family means adding a plan, not a code path.
public struct QuantizationPlan: Hashable, Sendable {
    /// The components to pack, in the order they are converted.
    public let components: [QuantizedComponent]
    /// Directories copied across whole, weights and all — the tokenizer, the scheduler, and
    /// any component left at full precision because packing it costs quality for no real saving.
    public let verbatimDirectories: [String]

    /// Creates a plan.
    public init(components: [QuantizedComponent], verbatimDirectories: [String]) {
        self.components = components
        self.verbatimDirectories = verbatimDirectories
    }

    /// Whether every packed tensor in the plan uses one precision, which is what decides how
    /// much the manifest's top-level `bits` and `group_size` can be trusted to say.
    public var isUniform: Bool {
        Set(components.flatMap(\.declaredPrecisions)).count <= 1
    }

    /// How the plan reads in a log line.
    public var summary: String {
        components
            .map { component in
                let precisions = Set(component.declaredPrecisions)
                    .sorted { $0.bits > $1.bits }
                    .map(\.summary)
                    .joined(separator: " and ")
                return "\(component.directoryName) \(precisions.isEmpty ? "verbatim" : precisions)"
            }
            .joined(separator: "; ")
    }
}
