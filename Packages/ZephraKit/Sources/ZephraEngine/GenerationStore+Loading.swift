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
        // Under on-demand the launch surveys the disk and stops there: the chosen model stays
        // chosen, nothing is read in, and Load or a press of Generate is what asks for it.
        guard loadingMode == .automatic else { return }
        await load(descriptor, asSwap: false)
    }

    /// Loads the chosen model now. What the Load control presses, and the door a paired
    /// device's `Command.loadModel` comes in through. Under `.onDemand` this and a press of
    /// Generate are the only two ways weights reach memory.
    public func loadModel() {
        guard acceptsWork, !isDraining, !isUpscaling, !isStoppingPreparation,
            canLoad(descriptor)
        else { return }
        // An explicit Load is the explicit choice a picture's adoption was waiting for, exactly
        // as a menu pick is and as Generate is.
        modelAwaitsGenerate = false
        startLoading(descriptor, asSwap: false)
    }

    /// Whether Unload would do anything: weights are in and nothing is moving them already.
    public var canUnload: Bool {
        acceptsWork && !isDraining && !isUpscaling && !isSwappingModel && !isStoppingPreparation
            && loadedDescriptor != nil
    }

    /// Gives the weights and their disk lease back, leaving the chosen model chosen.
    public func unloadModel() {
        guard canUnload else { return }
        // `isSwappingModel` is exactly the right flag: the state passes through `.idle` while
        // the weights go back, and nothing else may load meanwhile.
        isSwappingModel = true
        transition(to: .idle)
        switchTask = Task {
            await self.releaseModel()
            // A swap asked for while this was settling owns the flag; only this unload gives
            // it up, the rule `reload` and `stopPreparation` both follow.
            if !Task.isCancelled { self.isSwappingModel = false }
            self.modelAwaitsGenerate = false
            self.transition(to: .idle)
        }
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
        // A model this Mac cannot hold any way at all is refused here, before a byte of it is
        // fetched: greying it in the picker is the first answer, and this is the one that
        // holds when a saved choice, a picture or a phone names it anyway.
        if let shortfall = staticShortfall(for: model) {
            transition(to: .failed(.insufficientMemory(shortfall)))
            return nil
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
            // The device came back, or the memory did not. Asking the guard again is what makes
            // a retry after a fault on a resident model under Automatic land streamed rather
            // than answering ready over weights this Mac no longer has the room to run on.
            if let stepped = residencyToStepDownTo(model) {
                residencyOverride = stepped
                reload(model, thenDrain: !queue.isEmpty)
                return switchTask
            }
            transition(to: .ready)
            // A job the run check refused is still waiting; Try Again is what gives it its turn.
            if !queue.isEmpty { drain() }
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

    /// Whether `model` is loaded and its lease is the one this store holds, so a load would
    /// find everything already done.
    ///
    /// How it is loaded is deliberately not compared against the policy's answer. A load the
    /// guard stepped down to streaming — because this Mac had not the room to hold it at that
    /// moment — is loaded and working, and the static answer still says resident; making that
    /// a reload would read the whole model again on the next press of Generate and find the
    /// same thing. A change of residency is felt through `setWeightResidencyPolicy`, which
    /// reloads on an explicit change of preference, and through a model switch. Nowhere else.
    private func isResident(_ model: ModelDescriptor) -> Bool {
        loadedDescriptor?.id == model.id && loadedResidency != nil
            && acquiredModel?.model.id == model.id
            && acquiredModel?.locations == locations
    }
}
