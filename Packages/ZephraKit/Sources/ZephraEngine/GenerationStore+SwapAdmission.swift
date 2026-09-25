import ZephraCore

/// The memory check for a run on a model that is not loaded yet — what a paired phone's
/// request on another model is, and every run the queue will swap in for.
extension GenerationStore {
    /// Why a run on `model`, which is not the model in, cannot be had right now, or nil.
    ///
    /// The residency is the one the swap's load will choose, stepped down to streaming under
    /// Automatic where holding the weights would not leave room for the run — the same step
    /// `stepDownToStreaming(for:)` makes once the weights are in — so a request the Mac would
    /// run after stepping down is not refused before it gets the chance.
    func swapRunShortfall(
        for model: ModelDescriptor, settings: GenerationSettings, logging: Bool
    ) -> MemoryShortfall? {
        let machine = machineMemory?.read()
        let snapshot = runtime?.memorySnapshot() ?? .zero
        let tile = vaeTile(for: model)
        let mode = weightResidencyPolicy.mode
        let chosen = memoryGuard.loadResidency(
            for: model, policy: weightResidencyPolicy, tile: tile, machine: machine,
            runtime: snapshot
        ).residency
        func shortfall(at residency: WeightResidency) -> MemoryShortfall? {
            memoryGuard.swapRunShortfall(
                for: model, residency: residency, mode: mode, tile: tile, settings: settings,
                machine: machine, runtime: snapshot)
        }
        var residency = chosen
        var answer = shortfall(at: chosen)
        if answer != nil, mode == .automatic, chosen == .resident, model.streamedPeakBytes > 0 {
            residency = .streamed
            answer = shortfall(at: .streamed)
        }
        guard logging else { return answer }
        let charged = memoryGuard.swapRunBytes(
            of: model, residency: residency, tile: tile, settings: settings)
        log("run of \(model.id) after a swap", machine: machine, snapshot: snapshot,
            shortfall: answer, chargedBytes: charged)
        return answer
    }
}
