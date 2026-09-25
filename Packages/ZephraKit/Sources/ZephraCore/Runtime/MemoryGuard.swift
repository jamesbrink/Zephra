/// The check before a load and before a run: has this Mac, right now, the memory the next
/// thing Zephra is about to ask Metal for?
///
/// `MemoryFit` answers a catalog question — could this Mac ever hold that model — and it is
/// answered against a budget that does not move. This answers the other half: the budget is
/// what the GPU *may* keep, not what is going spare while a browser, a compiler and the model
/// loaded five minutes ago are holding it. On 2026-09-13 a 16 GB mini asked for more than the
/// kernel would wire and MLX threw from Metal's completion queue, where no `catch` reaches it;
/// the only place to stop that is here, before the allocation.
///
/// A value type over a budget, so a refusal is a pure function of four readings and is tested
/// without a GPU.
public struct MemoryGuard: Sendable {
    /// What this Mac's GPU may keep resident.
    public let budget: MemoryBudget

    public init(budget: MemoryBudget) {
        self.budget = budget
    }

    /// What getting `descriptor`'s weights in would take, or nil when there is room for it.
    ///
    /// The free figure is the smaller of the budget and what the machine could find: Zephra's
    /// own active and cached bytes count as free because the load releases the old model
    /// first, and a reading that cannot be had (`machine` nil) leaves the budget half of the
    /// question alone rather than guessing at the machine.
    public func loadShortfall(
        for descriptor: ModelDescriptor,
        residency: WeightResidency,
        mode: WeightResidencyMode,
        tile: Int?,
        machine: MachineMemory?,
        runtime: MemorySnapshot
    ) -> MemoryShortfall? {
        let needed = peakBytes(of: descriptor, residency: residency, tile: tile)
        let free = freeForLoad(machine: machine, runtime: runtime)
        guard needed > free else { return nil }
        return MemoryShortfall(
            modelName: descriptor.fullName, neededBytes: needed, freeBytes: free,
            phase: .load, remedy: remedy(for: descriptor, residency: residency, mode: mode))
    }

    /// What one run at `settings` would take on top of the weights already in, or nil when
    /// there is room for it.
    ///
    /// Only the transient is charged: the weights are in by now, so what is left to find is
    /// the difference between the measured peak and what is being held, scaled by how much
    /// bigger this request is than the one the peak was measured at. A machine that cannot be
    /// read refuses nothing here — the load has already been through the budget.
    public func runShortfall(
        for descriptor: ModelDescriptor,
        residency: WeightResidency,
        mode: WeightResidencyMode,
        tile: Int?,
        settings: GenerationSettings,
        machine: MachineMemory?,
        runtime: MemorySnapshot
    ) -> MemoryShortfall? {
        guard let machine else { return nil }
        let needed = transientBytes(
            of: descriptor, residency: residency, tile: tile, settings: settings, runtime: runtime)
        let free = machine.availableBytes + Int64(runtime.cacheBytes)
        guard needed > free else { return nil }
        return MemoryShortfall(
            modelName: descriptor.fullName, neededBytes: needed, freeBytes: free,
            phase: .run, remedy: remedy(for: descriptor, residency: residency, mode: mode))
    }

    /// The budget, or the machine's own figure where that is smaller. Zephra's own allocator
    /// is counted back in: a model being replaced is released before the next one is read.
    private func freeForLoad(machine: MachineMemory?, runtime: MemorySnapshot) -> Int64 {
        let ceiling = Int64(budget.bytes)
        guard let machine else { return ceiling }
        let ours = Int64(runtime.activeBytes) + Int64(runtime.cacheBytes)
        return min(ceiling, machine.availableBytes + ours)
    }

    /// What to tell the person, which is a question about the **mode** and not only about
    /// the residency this load was tried at.
    ///
    /// Streaming is worth suggesting only where the weights are held resident by a choice —
    /// `Never` in Settings > Performance — and reading them from disk would fit the budget.
    /// Under `automatic` a refusal has already been through `loadResidency`, which steps down
    /// to streaming itself, so a refusal there means even streaming did not fit and sending
    /// the person to a preference they are already on is no remedy at all: that is what a
    /// 16 GB Mac was told on 2026-09-13. Everywhere else the memory simply is not there, and
    /// the answer is to free some.
    func remedy(
        for descriptor: ModelDescriptor, residency: WeightResidency, mode: WeightResidencyMode
    ) -> MemoryShortfall.Remedy {
        guard mode == .never, residency == .resident, descriptor.streamedPeakBytes > 0,
            Double(descriptor.streamedPeakBytes) <= budget.bytes
        else { return .quitOtherApps }
        return .streamFromDisk
    }
}
