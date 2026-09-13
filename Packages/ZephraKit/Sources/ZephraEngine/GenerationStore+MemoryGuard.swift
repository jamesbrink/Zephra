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

    /// Why `model` cannot be loaded the way `residency` asks for it right now, or nil when it
    /// can. Reads the machine once and says in the log what it read and what it decided, since
    /// the same refusal on two Macs is two different stories about what was holding the memory.
    func loadShortfall(
        for model: ModelDescriptor, residency: WeightResidency
    ) -> MemoryShortfall? {
        let machine = machineMemory?.read()
        let snapshot = runtime?.memorySnapshot() ?? .zero
        let shortfall = memoryGuard.loadShortfall(
            for: model, residency: residency, tile: vaeTile(for: model), machine: machine,
            runtime: snapshot)
        log("load of \(model.id)", machine: machine, snapshot: snapshot, shortfall: shortfall)
        return shortfall
    }

    /// Why the job in hand cannot be run right now, or nil when it can. The job carries its own
    /// model and settings, so a run queued behind a switch is judged by what it will actually
    /// ask for rather than by whatever the capsule holds by then.
    func runShortfall(for job: QueuedGeneration) -> MemoryShortfall? {
        runShortfall(for: job.model, settings: job.settings)
    }

    /// Why one request on one model cannot be run right now, or nil when it can.
    func runShortfall(
        for model: ModelDescriptor, settings: GenerationSettings
    ) -> MemoryShortfall? {
        let machine = machineMemory?.read()
        let snapshot = runtime?.memorySnapshot() ?? .zero
        let residency = loadedResidency ?? weightResidencyPolicy.residency(for: model)
        let shortfall = memoryGuard.runShortfall(
            for: model, residency: residency, tile: vaeTile(for: model), settings: settings,
            machine: machine, runtime: snapshot)
        log("run of \(model.id)", machine: machine, snapshot: snapshot, shortfall: shortfall)
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
            tile: vaeTile(for: model), machine: nil, runtime: .zero)
    }

    /// One line per decision, so `make logs` says what the Mac looked like when it refused —
    /// or when it did not, which is the line that makes the next refusal legible.
    private func log(
        _ what: String, machine: MachineMemory?, snapshot: MemorySnapshot,
        shortfall: MemoryShortfall?
    ) {
        let reading = machine.map {
            "machine \(ByteCount.gigabytes($0.availableBytes)) free of "
                + "\(ByteCount.gigabytes($0.physicalBytes))"
        } ?? "machine unread"
        let ours =
            "zephra active \(ByteCount.gigabytes(Int64(snapshot.activeBytes))) "
            + "cache \(ByteCount.gigabytes(Int64(snapshot.cacheBytes)))"
        guard let shortfall else {
            logger.info("memory before \(what, privacy: .public): \(reading, privacy: .public), \(ours, privacy: .public) — admitted")
            return
        }
        logger.error(
            "memory before \(what, privacy: .public): \(reading, privacy: .public), \(ours, privacy: .public); needs \(ByteCount.gigabytes(shortfall.neededBytes), privacy: .public) of \(ByteCount.gigabytes(shortfall.freeBytes), privacy: .public) — refused"
        )
    }
}
