import Foundation
import ZephraCore

/// Getting the model onto the machine and into memory: the one long operation that has to
/// finish before anything else can start. Split out of `GenerationStore.swift` so the observed
/// surface of the store stays readable on its own.
extension GenerationStore {
    /// The actor every backend call goes through, built on first use from the registry. Nil for
    /// a preview store, which has no registry and so can never reach a backend at all.
    func inferenceActor() -> InferenceActor? {
        guard let registry else { return nil }
        if let inference { return inference }
        let made = InferenceActor(
            registry: registry, locations: locations, upscaler: upscalerFactory,
            runtime: runtime)
        inference = made
        return made
    }

    /// Finds or downloads the model, loads it, and warms up. Call once from the root view.
    /// Calling it again once the engine is running is a no-op, so a re-rendered root is free.
    ///
    /// What is on disk is checked first, so the picker can label every model before the long
    /// load takes over the inference queue, and so a saved choice that is no longer on the
    /// disk gives way to one that is instead of failing at launch.
    public func bootstrap() async {
        await surveyAvailability()
        await load(descriptor, asSwap: false)
    }

    /// Loads `model` and waits for it, unless a load is already under way. `asSwap` marks the
    /// load a model swap makes for itself; nothing else may load while a swap is in flight.
    func load(_ model: ModelDescriptor, asSwap: Bool) async {
        guard let task = startLoading(model, asSwap: asSwap) else { return }
        await task.value
    }

    /// Starts the same work as `bootstrap` without waiting for it, for a button that only has
    /// to kick it off: the remedy after a failure, and the resume after a cancelled download.
    public func retry() {
        startLoading(descriptor, asSwap: false)
    }

    /// Begins a load unless one is already under way, handing back the task that runs it. The
    /// store keeps that task so `cancel()` has something to cancel while the model is loading.
    /// A preview store has no backend to build, so it never starts anything.
    @discardableResult
    private func startLoading(_ model: ModelDescriptor, asSwap: Bool) -> Task<Void, Never>? {
        guard acceptsWork, !isStoppingPreparation, let inference = inferenceActor() else { return nil }
        switch state {
        case .idle, .failed: break
        default: return nil
        }
        // A swap passes through .idle while the old weights go back; only the swap may load.
        if isSwappingModel, !asSwap { return nil }
        // Another model's weights are up — a generation on it failed, and a picture's model
        // has been chosen since — so this is a swap, not a load: the old lease goes back
        // first, or Settings > Models would show it in use for the rest of the session.
        if let loadedDescriptor, loadedDescriptor.id != model.id, !asSwap {
            reload(model, thenDrain: false)
            return switchTask
        }
        // Retry after a generation failure: the weights are up and the lease is held, so
        // there is nothing to fetch, build or load. Answer ready and touch neither the pool
        // nor the actor; a second borrow of the same request could never be given back.
        if isResident(model) {
            transition(to: .ready)
            return nil
        }
        transition(to: .checkingModel)
        let identity = UUID()
        loadIdentity = identity
        preparingModel = model
        let task = Task { await self.load(model, on: inference, identity: identity) }
        bootstrapTask = task
        return task
    }

    /// Whether `model` is loaded the way the policy asks and its lease is the one this store
    /// holds, so a load would find everything already done.
    private func isResident(_ model: ModelDescriptor) -> Bool {
        loadedDescriptor?.id == model.id
            && loadedResidency == weightResidencyPolicy.residency(for: model)
            && acquiredModel?.model.id == model.id
            && acquiredModel?.locations == locations
    }
}
