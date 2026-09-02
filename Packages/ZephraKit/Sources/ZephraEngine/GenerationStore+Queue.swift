import ZephraCore

/// Starting, queueing, and stopping generations. Every queued entry names its own model, so the
/// queue can hold work for several models and the engine swaps weights between them as it goes.
extension GenerationStore {
    /// Whether a generation is in flight, including one that is being stopped.
    var isRunning: Bool {
        switch state {
        case .generating, .cancelling: true
        default: false
        }
    }

    /// Whether the engine is working down the queue: rendering, or swapping models to render.
    var isDraining: Bool { isRunning || isSwitchingForQueue }

    /// Queues a generation with the current settings on the current model, and starts it at once
    /// if nothing else is running. Does nothing unless `canQueue`.
    public func generate() {
        guard canQueue else { return }
        let request = descriptor.capabilities.clamp(settings)
        queue.append(QueuedGeneration(model: descriptor, settings: request))
        if isDraining {
            logger.info("queued generation, \(self.queue.count) waiting")
        } else {
            drain()
        }
    }

    /// Takes the next queued generation and runs it, swapping models first if it needs a model
    /// other than the one loaded. With the queue empty, brings the loaded model in line with the
    /// chosen one, so a switch made mid-run lands as soon as the run is over.
    func drain() {
        guard let next = queue.first else {
            isSwitchingForQueue = false
            if descriptor.id != loadedDescriptor?.id { reload(descriptor, thenDrain: false) }
            return
        }
        if next.model.id == loadedDescriptor?.id {
            isSwitchingForQueue = false
            queue.removeFirst()
            start(next.settings)
        } else {
            reload(next.model, thenDrain: true)
        }
    }

    /// Stops whatever the engine is busy with.
    ///
    /// During a generation that means finishing the current step and dropping the queue: the
    /// backend only looks for a cancel between denoising steps, so `.cancelling` can sit there
    /// for one step's worth. During a download, a load, or a warm-up it means abandoning that
    /// and returning to `.idle`, from where the canvas offers to start again.
    public func cancel() {
        switch state {
        case .generating:
            queue.removeAll()
            transition(to: .cancelling)
            generationTask?.cancel()
        case .checkingModel, .downloading, .loading, .warmingUp:
            queue.removeAll()
            isSwitchingForQueue = false
            bootstrapTask?.cancel()
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
