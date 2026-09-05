import ZephraCore

/// Starting, queueing, and stopping generations. Every queued entry names its own model, so the
/// queue can hold work for several models and the engine swaps weights between them as it goes.
extension GenerationStore {
    /// Whether a generation is in flight, including one that is being stopped.
    var isRunning: Bool {
        // An upscale that is stopping is also in `.cancelling`, and it is not a generation:
        // counting it as one would let Generate queue work behind a model that never loaded.
        guard !isUpscaling, !isStoppingPreparation else { return false }
        switch state {
        case .generating, .cancelling: return true
        default: return false
        }
    }

    /// Whether the engine is working down the queue: rendering, or swapping models to render.
    var isDraining: Bool { isRunning || isSwitchingForQueue }

    /// Queues one generation with the current settings on the current model, and starts it at
    /// once if nothing else is running. Does nothing unless `canQueue`.
    public func generate() { generate(count: 1) }

    /// Takes the next queued generation and runs it, swapping models first if it needs a model
    /// other than the one loaded. With the queue empty, brings the loaded model in line with the
    /// chosen one, so a switch made mid-run lands as soon as the run is over.
    func drain() {
        // Closed during a deletion too; `deleteModelStorage` drains again on its way out.
        guard acceptsWork else { return }
        guard let next = queue.first else {
            isSwitchingForQueue = false
            if descriptor.id != loadedDescriptor?.id { reload(descriptor, thenDrain: false) }
            return
        }
        if next.model.id == loadedDescriptor?.id {
            isSwitchingForQueue = false
            queue.removeFirst()
            running = next
            start(next.settings)
        } else {
            reload(next.model, thenDrain: true)
        }
    }

    /// Stops whatever the engine is busy with.
    ///
    /// During a generation that means finishing the current step and dropping the queue: the
    /// backend only looks for a cancel between denoising steps, so `.cancelling` can sit there
    /// for one step's worth. During a download, a load, a warm-up, or the unload half of a
    /// model swap it means abandoning that and returning to `.idle`, from where the canvas
    /// offers to start again.
    public func cancel() {
        switch state {
        case .generating:
            queue.removeAll()
            // The rest of the run is abandoned the moment stopping is asked for, so the queue
            // in the sidebar empties at once rather than a step later, when the backend
            // notices. The image itself finishes its current step and is then thrown away.
            running = nil
            // The frame goes with it: the picture on the canvas is being abandoned, and
            // leaving it up through the step it takes the backend to notice reads as a run
            // still going.
            clearLivePreview()
            transition(to: .cancelling)
            generationTask?.cancel()
        case .upscaling:
            // Nothing is queued during an upscale, so there is nothing to empty: the run itself
            // is what stops, and the store puts back the state it was in before it started.
            transition(to: .cancelling)
            upscaleTask?.cancel()
        case .checkingModel, .downloading, .building, .loading, .warmingUp:
            stopPreparation(discard: true)
        case .idle where isSwappingModel:
            stopPreparation(discard: true)
        case .idle, .ready, .cancelling, .failed:
            break
        }
    }

    /// Takes one waiting generation out of the queue.
    public func removeFromQueue(_ id: QueuedGeneration.ID) {
        queue.removeAll { $0.id == id }
    }

    /// Empties the queue without touching the running generation.
    public func clearQueue() { queue.removeAll() }
}
