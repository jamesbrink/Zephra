/// A run on a model that is not the one loaded: a swap first, then the run.
extension MemoryGuard {
    /// What one run at `settings` on `descriptor` would take when its weights are not in yet,
    /// or nil when there is room for it.
    ///
    /// `runShortfall` charges only the transient, over weights already in, and finds room for it
    /// beside them. Neither half holds before a swap: the weights in now are another model's and
    /// go back before this one's are read, so they are memory this run may count as free, and
    /// this model's own weights are memory it still has to find. So the charge is the weights
    /// held the way `residency` holds them plus the scaled transient on top — the measured peak
    /// at the default size — against the machine's free memory with Zephra's own allocator
    /// counted back in, which is what `loadShortfall` counts. The budget is not a ceiling here,
    /// for the reason it is not one in `runShortfall`: the load's own check has that half.
    ///
    /// A machine that cannot be read refuses nothing, as in `runShortfall`.
    public func swapRunShortfall(
        for descriptor: ModelDescriptor,
        residency: WeightResidency,
        mode: WeightResidencyMode,
        tile: Int?,
        settings: GenerationSettings,
        machine: MachineMemory?,
        runtime: MemorySnapshot
    ) -> MemoryShortfall? {
        guard let machine else { return nil }
        let needed = swapRunBytes(
            of: descriptor, residency: residency, tile: tile, settings: settings)
        let free = machine.availableBytes + Int64(runtime.activeBytes) + Int64(runtime.cacheBytes)
        guard needed > free else { return nil }
        return MemoryShortfall(
            modelName: descriptor.fullName, neededBytes: needed, freeBytes: free,
            phase: .run, remedy: remedy(for: descriptor, residency: residency, mode: mode))
    }

    /// The weights a load at `residency` holds, plus the run on top of them.
    public func swapRunBytes(
        of descriptor: ModelDescriptor, residency: WeightResidency, tile: Int?,
        settings: GenerationSettings
    ) -> Int64 {
        let held =
            residency == .streamed && descriptor.streamedPeakBytes > 0
            ? descriptor.streamedResidentBytes : descriptor.residentBytes
        // `.zero` so the transient is measured against the descriptor's own held figure, not
        // against the allocator, which is holding the model about to be released.
        return held
            + transientBytes(
                of: descriptor, residency: residency, tile: tile, settings: settings,
                runtime: .zero)
    }
}
