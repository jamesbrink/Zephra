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
    ///
    /// This is the **static** answer, from a budget that does not move, and it stays static
    /// because that is what the model menu's note, the Performance tab's caption and the
    /// timing keys are about: what this Mac could do with this model, not what it happens to
    /// have free this minute. `MemoryGuard.loadResidency(for:policy:tile:machine:runtime:)`
    /// adds the other half at the load, stepping a resident answer down to streamed under
    /// `automatic` when the machine has not the room for it right now.
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
