/// Turns a preference and a machine into where a model's weights should live.
///
/// A value type with no state of its own so the decision is testable without a GPU, the way
/// `VAETilingPolicy` is: give it a mode and a memory budget, ask it about a model, and it says
/// resident or streamed. A model whose family cannot stream — `streamedPeakBytes` of zero — is
/// resident under every mode, which is what keeps a family that never learned to stream from
/// ever being asked to.
public struct WeightResidencyPolicy: Hashable, Sendable {
    /// What the user chose.
    public let mode: WeightResidencyMode
    /// What this Mac's GPU may keep resident.
    public let budget: MemoryBudget

    public init(mode: WeightResidencyMode, budget: MemoryBudget) {
        self.mode = mode
        self.budget = budget
    }

    /// Where `descriptor`'s weights should live on this Mac.
    ///
    /// Under `automatic` the answer is streamed exactly when the catalog's verdict is
    /// `fitsStreamed`: a model that fits resident, tiled or not, stays resident, and one that
    /// does not fit even streamed is loaded resident and left to page, since streaming would
    /// not save it and the person chose it knowing the picker's figure.
    public func residency(for descriptor: ModelDescriptor) -> WeightResidency {
        guard descriptor.streamedPeakBytes > 0 else { return .resident }
        switch mode {
        case .never:
            return .resident
        case .always:
            return .streamed
        case .automatic:
            return MemoryFit(descriptor: descriptor, budget: budget).requiresStreaming
                ? .streamed : .resident
        }
    }
}
