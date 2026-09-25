import ZephraCore

/// The live memory check, asked twice: before the weights are read in, and before a run is
/// started over them.
///
/// `MemoryFit` says whether a Mac could ever hold a model, and the picker greys what it cannot.
/// This is the other question — whether the Mac has the memory *now* — and it is asked because
/// a browser, a compiler and the model loaded five minutes ago do not appear in any catalog
/// figure. A refusal here is a sentence on the canvas; the alternative, twice measured, is the
/// kernel refusing to wire the memory and MLX aborting the app from Metal's completion queue.
extension GenerationStore {
    /// The guard this Mac's budget makes.
    var memoryGuard: MemoryGuard { MemoryGuard(budget: memoryBudget) }

    /// How `model`'s weights should be loaded right now, and why they cannot be, or nil when
    /// they can. Reads the machine once and says in the log what it read and what it decided,
    /// since the same refusal on two Macs is two different stories about what was holding the
    /// memory.
    ///
    /// The residency handed back is what the load must actually use: under Automatic the guard
    /// steps a resident answer down to streaming where the machine has not the room for it,
    /// which is a load rather than a refusal and is logged as one line saying both figures.
    /// `forced` is a residency the store has already decided on — a run that stepped down, or a
    /// retry that did — and it still goes through the shortfall check against that residency,
    /// so a Mac that cannot stream it either is refused with the streamed figure, which is what
    /// the load that was going to be attempted would have taken.
    func loadResidency(
        for model: ModelDescriptor, forcing forced: WeightResidency? = nil
    ) -> (residency: WeightResidency, shortfall: MemoryShortfall?) {
        let machine = machineMemory?.read()
        let snapshot = runtime?.memorySnapshot() ?? .zero
        let tile = vaeTile(for: model)
        let answer =
            forced.map {
                (
                    residency: $0,
                    shortfall: memoryGuard.loadShortfall(
                        for: model, residency: $0, mode: weightResidencyPolicy.mode, tile: tile,
                        machine: machine, runtime: snapshot)
                )
            }
            ?? memoryGuard.loadResidency(
                for: model, policy: weightResidencyPolicy, tile: tile, machine: machine,
                runtime: snapshot)
        if answer.shortfall == nil, answer.residency != weightResidencyPolicy.residency(for: model) {
            logStepDown(model, tile: tile, machine: machine, snapshot: snapshot)
        }
        // What the load will do with this answer is said by the load itself, in
        // `+Preparation.load`: this is also asked by `residencyToStepDownTo(_:)`, which loads
        // nothing, and a Try Again over a resident model writing "will be resident" would be a
        // line about a load that never happened.
        log("load of \(model.id)", machine: machine, snapshot: snapshot, shortfall: answer.shortfall)
        return answer
    }

    /// The one line that says a load was stepped down rather than refused: what holding the
    /// weights would have wanted, what the Mac had, and what reading them from disk wants
    /// instead. Without it a Mac that quietly streamed and one that quietly did not are the
    /// same three log lines.
    private func logStepDown(
        _ model: ModelDescriptor, tile: Int?, machine: MachineMemory?, snapshot: MemorySnapshot
    ) {
        guard
            let resident = memoryGuard.loadShortfall(
                for: model, residency: .resident, mode: weightResidencyPolicy.mode, tile: tile,
                machine: machine, runtime: snapshot)
        else { return }
        logger.info(
            "memory before load of \(model.id, privacy: .public): resident needs \(ByteCount.gigabytes(resident.neededBytes), privacy: .public), \(ByteCount.gigabytes(resident.freeBytes), privacy: .public) free; streaming instead, needs \(ByteCount.gigabytes(model.streamedPeakBytes), privacy: .public)"
        )
    }

    /// Why the job in hand cannot be run right now, or nil when it can. The job carries its own
    /// model and settings, so a run queued behind a switch is judged by what it will actually
    /// ask for rather than by whatever the capsule holds by then.
    func runShortfall(for job: QueuedGeneration) -> MemoryShortfall? {
        runShortfall(for: job.model, settings: job.settings)
    }

    /// Why one request on one model cannot be run right now, or nil when it can.
    ///
    /// `residency` asks the question of a way of loading other than the one in force, which is
    /// what "would this run fit if the weights were read from disk instead" is.
    ///
    /// `logging` is false for a multi-host **offer** — the estimate a paired phone polls every
    /// few seconds while nothing is running — since that is not a decision about any work and
    /// logging it at info buries the one line that is: a real run's own admission, from
    /// `run(_:on:)`, or `enqueue`'s on a phone's actual submit. That line carries what the run
    /// charged — the guard's own `transientBytes`, which already folds in the per-reference
    /// prefix cache and its pass count — so a two-reference run's line shows the two pictures
    /// were charged.
    func runShortfall(
        for model: ModelDescriptor, settings: GenerationSettings,
        residency: WeightResidency? = nil, logging: Bool = true
    ) -> MemoryShortfall? {
        // A run on a model that is not the one in is a swap and then a run: the weights in now
        // go back first, so they are neither what this run is charged on top of nor memory it
        // has to find room beside.
        if residency == nil, model.id != loadedDescriptor?.id {
            return swapRunShortfall(for: model, settings: settings, logging: logging)
        }
        let machine = machineMemory?.read()
        let snapshot = runtime?.memorySnapshot() ?? .zero
        let residency = residency ?? loadedResidency ?? weightResidencyPolicy.residency(for: model)
        let tile = vaeTile(for: model)
        let shortfall = memoryGuard.runShortfall(
            for: model, residency: residency, mode: weightResidencyPolicy.mode,
            tile: tile, settings: settings, machine: machine, runtime: snapshot)
        guard logging else { return shortfall }
        let charged = memoryGuard.transientBytes(
            of: model, residency: residency, tile: tile, settings: settings, runtime: snapshot)
        log("run of \(model.id)", machine: machine, snapshot: snapshot, shortfall: shortfall,
            chargedBytes: charged)
        return shortfall
    }

    /// The refusal for a model this Mac cannot hold at all, from the budget alone: what
    /// `startLoading` answers before a byte is fetched, and what a paired device is told.
    ///
    /// Nil for a model the Mac can hold some way — held whole, tiled, or read from disk — even
    /// when the preference in force would load it the one way that does not fit. That case is
    /// the live check's, since it is a choice and not the machine.
    func staticShortfall(for model: ModelDescriptor) -> MemoryShortfall? {
        guard !canSelect(model) else { return nil }
        return memoryGuard.loadShortfall(
            for: model, residency: weightResidencyPolicy.residency(for: model),
            mode: weightResidencyPolicy.mode, tile: vaeTile(for: model), machine: nil,
            runtime: .zero)
    }

    /// One line per decision, so `make logs` says what the Mac looked like when it refused —
    /// or when it did not, which is the line that makes the next refusal legible. `chargedBytes`
    /// is a run's own figure, what the guard charged this request on top of the weights; nil for
    /// a load, which has no per-request charge to name.
    func log(
        _ what: String, machine: MachineMemory?, snapshot: MemorySnapshot,
        shortfall: MemoryShortfall?, chargedBytes: Int64? = nil
    ) {
        let reading = machine.map {
            "machine \(ByteCount.gigabytes($0.availableBytes)) free of "
                + "\(ByteCount.gigabytes($0.physicalBytes))"
        } ?? "machine unread"
        let ours =
            "zephra active \(ByteCount.gigabytes(Int64(snapshot.activeBytes))) "
            + "cache \(ByteCount.gigabytes(Int64(snapshot.cacheBytes)))"
        guard let shortfall else {
            let charge = chargedBytes.map { ", charging \(ByteCount.gigabytes($0))" } ?? ""
            logger.info("memory before \(what, privacy: .public): \(reading, privacy: .public), \(ours, privacy: .public)\(charge, privacy: .public) — admitted")
            return
        }
        logger.error(
            "memory before \(what, privacy: .public): \(reading, privacy: .public), \(ours, privacy: .public); needs \(ByteCount.gigabytes(shortfall.neededBytes), privacy: .public) of \(ByteCount.gigabytes(shortfall.freeBytes), privacy: .public) — refused"
        )
    }
}
