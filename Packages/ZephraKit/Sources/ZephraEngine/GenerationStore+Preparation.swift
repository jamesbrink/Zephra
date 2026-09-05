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
        let residency = weightResidencyPolicy.residency(for: model)
        // A lease already held for this model is reused rather than borrowed again: one
        // request is borrowed once, whatever path reaches here.
        let held = acquiredModel.flatMap { $0.model.id == model.id && $0.locations == locations ? $0 : nil }
        do {
            if let held {
                acquired = held
            } else {
                acquired = try await downloads.acquire(model, registry: registry, locations: locations) { [weak self] event in
                    guard let self, self.loadIdentity == identity else { return }
                    self.applyLoadEvent(.download(event))
                }
            }
            try Task.checkCancellation()
            guard let acquired else { throw CancellationError() }
            let builtExists = locations.builtCandidates(for: model).contains {
                $0.standardizedFileURL == acquired.directory.standardizedFileURL
            }
            try await downloads.transfers.reserveBuild(acquired.id,
                bytes: builtExists ? 0 : model.builtBytes, at: acquired.locations.root)
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
            transition(to: .ready)
        } catch {
            // Even a failed load may have allocated weights. Settle them before releasing
            // their disk lease; suppressing obsolete UI events must not suppress cleanup.
            await inference.unload()
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
                case BackendRegistryError.noBackend(let id): transition(to: .failed(.noBackend(id)))
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

    func unloadModel() async {
        await inference?.unload()
        if let acquiredModel {
            await downloads.release(acquiredModel)
            // The foreground request is settled by the time `acquire` returns, so its release
            // drops it from the pool exactly when this was its only borrow.
            assert(!downloads.isRetained(acquiredModel.id),
                   "a resident model's lease was borrowed more than once")
        }
        acquiredModel = nil
        loadedDescriptor = nil
        loadedDirectory = nil
        loadedResidency = nil
    }
}
