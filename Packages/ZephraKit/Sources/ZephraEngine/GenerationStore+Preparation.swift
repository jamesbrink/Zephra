import Foundation
import ZephraCore

/// The body of a load and its undoing: borrowing the weights, preparing them on the actor,
/// and giving the lease back. Split out of `GenerationStore+Loading.swift`, which keeps the
/// entry points.
extension GenerationStore {
    /// The body of a load, from finding the weights to the throwaway first generation.
    func load(_ model: ModelDescriptor, on inference: InferenceActor, identity: UUID) async {
        guard let registry else { return }
        let pump = EngineEventPump { [weak self] event in
            guard let self, self.loadIdentity == identity else { return }
            self.applyLoadEvent(event)
        }
        var acquired: AcquiredModel?
        let installedOnly = isSwitchingForQueue && queue.first?.requiresInstalledModel == true
        // A lease already held for this model is reused rather than borrowed again: one
        // request is borrowed once, whatever path reaches here.
        let held = acquiredModel.flatMap { $0.model.id == model.id && $0.locations == locations ? $0 : nil }
        do {
            if var held {
                held.installedOnly = installedOnly
                acquired = held
            } else {
                acquired = try await downloads.acquire(model, registry: registry, locations: locations, installedOnly: installedOnly) { [weak self] event in
                    guard let self, self.loadIdentity == identity else { return }
                    self.applyLoadEvent(.download(event))
                }
            }
            try Task.checkCancellation()
            guard let acquired else { throw CancellationError() }
            // The last gate before the weights are read: the files are here, and the question
            // is whether this Mac has the memory for them this minute. Asked after the
            // download rather than before it because a download is worth keeping whatever the
            // machine is doing, and a load is not. It answers with the residency to load at,
            // not only with a refusal: under Automatic a resident load the machine has not the
            // room for steps down to streaming rather than failing.
            let (residency, shortfall) = loadResidency(for: model, forcing: residencyOverride)
            residencyOverride = nil
            if let shortfall { throw shortfall }
            // Said here rather than inside the guard, because the guard is also asked by
            // `residencyToStepDownTo(_:)`, which loads nothing: a Try Again over a model already
            // resident would otherwise write "will be resident" for a load that never happened,
            // which is the same kind of wrong reading the line was added to fix. This is where a
            // load actually begins. Same sentence `setWeightResidencyPolicy` writes, so the two
            // paths say one thing.
            logger.info(
                "weights of \(model.id, privacy: .public) will be \(residency.rawValue, privacy: .public)"
            )
            let builtExists = locations.builtCandidates(for: model).contains {
                $0.standardizedFileURL == acquired.directory.standardizedFileURL
            }
            try await downloads.transfers.reserveBuild(acquired.id,
                bytes: builtExists || installedOnly ? 0 : model.builtBytes, at: acquired.locations.root)
            let timingStarted = ContinuousClock.now
            let directory = try await pump.run { sink in
                try await inference.prepare(acquired, residency: residency, events: sink)
            }
            await downloads.transfers.finishBuild(acquired.id)
            try Task.checkCancellation()
            if warmsUpAfterLoad {
                if loadIdentity == identity { transition(to: .warmingUp) }
                try await inference.warmUp(model, tile: vaeTile(for: model))
            }
            try Task.checkCancellation()
            guard loadIdentity == identity else { throw CancellationError() }
            acquiredModel = acquired
            loadedDirectory = directory
            loadedResidency = residency
            loadedDescriptor = model
            let revision = timingRevision(at: directory) ?? identity.uuidString
            timingRevisions[model.id] = revision
            timingDirectories[model.id] = directory
            timings.recordPreparation(model: model.id, revision: revision, residency: residency.rawValue,
                seconds: (ContinuousClock.now - timingStarted).seconds)
            // A load that lands on the chosen model is what a picture's choice was waiting for.
            if model.id == descriptor.id { modelAwaitsGenerate = false }
            transition(to: .ready)
        } catch {
            // Classified before anything is undone, because the undoing is itself three command
            // buffers — the backend's arrays dropped, Metal synchronized, the allocator's cache
            // handed back — and a load that failed *because* the driver has stopped running this
            // process's work is the one path guaranteed to reach here with the device gone.
            noteIfDeviceLost(error)
            // Even a failed load may have allocated weights. Settle them before releasing
            // their disk lease; suppressing obsolete UI events must not suppress cleanup. Never
            // over a lost GPU, where the weights go back when the process does.
            if !deviceLost { await inference.unload() }
            if let acquired {
                await downloads.release(acquired)
                // One release per lease: a held lease that failed is no longer held.
                if acquiredModel?.id == acquired.id { acquiredModel = nil }
            }
            if loadIdentity == identity {
                loadedDescriptor = nil
                loadedDirectory = nil
                loadedResidency = nil
                switch error {
                case is CancellationError: transition(to: .idle)
                case let shortfall as MemoryShortfall:
                    transition(to: .failed(.insufficientMemory(shortfall)))
                case BackendRegistryError.noBackend(let id): transition(to: .failed(.noBackend(id)))
                case BackendError.deviceLost:
                    // Already noticed above, before the undoing, so the transition lands on the
                    // one state a Mac with no GPU has and nothing offers to load again.
                    transition(to: .failed(.deviceLost))
                case let error as BackendError: transition(to: .failed(.backend(error)))
                default: transition(to: .failed(.backend(.loadFailed(error.localizedDescription))))
                }
            }
        }
        if loadIdentity == identity {
            preparingModel = nil
            bootstrapTask = nil
        }
        await refreshAvailability()
    }

    /// Drops the weights and gives the disk lease back, leaving the state alone: every caller
    /// settles that for itself. The primitive under the public `unloadModel()`, under a model
    /// swap, under a stopped preparation and under shutdown.
    ///
    /// Nothing at all over a lost GPU. The rule belongs here rather than at the five doors above
    /// it, because each of them is reachable in the window a loss opens — the loss happens
    /// *during* the load or run the door's own task is waiting on, after its `acceptsWork` check
    /// — and `inference.unload()` is three more command buffers submitted into a channel the
    /// driver is refusing, outside any `catchingDeviceErrors` boundary. The weights and the
    /// lease go back when the process does, which is seconds away.
    func releaseModel() async {
        guard !deviceLost else {
            logger.info("nothing released: the GPU is lost for this launch and submits no more")
            return
        }
        let started = ContinuousClock.now
        let model = loadedDescriptor?.id
        await inference?.unload()
        if let acquiredModel {
            await downloads.release(acquiredModel)
            // The foreground request is settled by the time `acquire` returns, so its release
            // drops it from the pool exactly when this was its only borrow.
            assert(!downloads.isRetained(acquiredModel.id),
                   "a resident model's lease was borrowed more than once")
        }
        if let model { timings.recordUnload(model: model, seconds: (ContinuousClock.now - started).seconds) }
        acquiredModel = nil
        loadedDescriptor = nil
        loadedDirectory = nil
        loadedResidency = nil
    }
}
