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
        let made = InferenceActor(registry: registry)
        inference = made
        return made
    }

    /// Finds or downloads the model, loads it, and warms up. Call once from the root view.
    /// Calling it again once the engine is running is a no-op, so a re-rendered root is free.
    ///
    /// What is on disk is checked first, so the picker can label every model before the long
    /// load takes over the inference queue.
    public func bootstrap() async {
        await refreshAvailability()
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
        guard let inference = inferenceActor() else { return nil }
        switch state {
        case .idle, .failed: break
        default: return nil
        }
        // A swap passes through .idle while the old weights go back; only the swap may load.
        if isSwappingModel, !asSwap { return nil }
        transition(to: .checkingModel)
        let task = Task { await self.load(model, on: inference) }
        bootstrapTask = task
        return task
    }

    /// The body of a load, from finding the weights to the throwaway first generation.
    private func load(_ model: ModelDescriptor, on inference: InferenceActor) async {
        let pump = EngineEventPump { [weak self] event in self?.applyLoadEvent(event) }
        do {
            try await pump.run { sink in try await inference.prepare(model, events: sink) }
            try Task.checkCancellation()
            if warmsUpAfterLoad {
                transition(to: .warmingUp)
                try await inference.warmUp(model)
            }
            loadedDescriptor = model
            transition(to: .ready)
        } catch is CancellationError {
            transition(to: .idle)
        } catch BackendRegistryError.noBackend(let id) {
            transition(to: .failed(.noBackend(id)))
        } catch let error as BackendError {
            transition(to: .failed(.backend(error)))
        } catch {
            transition(to: .failed(.backend(.loadFailed(error.localizedDescription))))
        }
        await refreshAvailability()
    }
}
