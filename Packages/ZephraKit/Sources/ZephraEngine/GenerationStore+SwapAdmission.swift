import ZephraCore

/// The memory check for a run on a model that is not loaded yet — a paired phone's request on
/// another model, or on any model while nothing is in — which is a load and then a run.
extension GenerationStore {
    /// Why a run on `model`, which is not the model in, cannot be had right now, or nil.
    ///
    /// The load's own verdict comes first, since it is the check `+Preparation.load` will make
    /// and the swap-run figure has no budget ceiling of its own: a request admitted here and
    /// refused by its load would empty the queue under a phone that was told yes. Past that,
    /// the run is charged at the residency the load will choose, stepped down to streaming
    /// under Automatic where holding the weights would not leave room for it — the same step
    /// `stepDownToStreaming(for:)` makes once the weights are in — so a request the Mac would
    /// run after stepping down is not refused before it gets the chance.
    func swapRunShortfall(
        for model: ModelDescriptor, settings: GenerationSettings, logging: Bool
    ) -> MemoryShortfall? {
        let machine = machineMemory?.read()
        let snapshot = runtime?.memorySnapshot() ?? .zero
        let tile = vaeTile(for: model)
        let mode = weightResidencyPolicy.mode
        let load = memoryGuard.loadResidency(
            for: model, policy: weightResidencyPolicy, tile: tile, machine: machine,
            runtime: snapshot)
        func shortfall(at residency: WeightResidency) -> MemoryShortfall? {
            memoryGuard.swapRunShortfall(
                for: model, residency: residency, mode: mode, tile: tile, settings: settings,
                machine: machine, runtime: snapshot)
        }
        var residency = load.residency
        var answer = load.shortfall ?? shortfall(at: residency)
        if load.shortfall == nil, answer != nil, mode == .automatic, residency == .resident,
            model.streamedPeakBytes > 0
        {
            residency = .streamed
            answer = shortfall(at: .streamed)
        }
        guard logging else { return answer }
        let charged = memoryGuard.swapRunBytes(
            of: model, residency: residency, tile: tile, settings: settings)
        let what = loadedDescriptor == nil ? "before its load" : "after a swap"
        log("run of \(model.id) \(what)", machine: machine, snapshot: snapshot,
            shortfall: answer, chargedBytes: charged)
        return answer
    }
}
