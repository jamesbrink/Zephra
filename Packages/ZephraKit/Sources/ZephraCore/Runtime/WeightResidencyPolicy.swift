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
    /// Under `automatic` the answer is streamed whenever the model does not fit resident: one
    /// that fits with its weights held, tiled or not, stays resident, and everything else
    /// streams. A model too large even streamed streams too — loading it resident to page was
    /// how a 16 GB Mac aborted, and the live `MemoryGuard` is what refuses it, not this.
    public func residency(for descriptor: ModelDescriptor) -> WeightResidency {
        guard descriptor.streamedPeakBytes > 0 else { return .resident }
        switch mode {
        case .never:
            return .resident
        case .always:
            return .streamed
        case .automatic:
            return MemoryFit(descriptor: descriptor, budget: budget).fitsResident
                ? .resident : .streamed
        }
    }
}
