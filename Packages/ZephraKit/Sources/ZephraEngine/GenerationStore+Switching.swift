import ZephraCore

/// Changing which model the store drives, at runtime, without losing work.
extension GenerationStore {
    /// Chooses a different model for the generations that follow.
    ///
    /// Does nothing if it is already the chosen model. The prompt and the seed survive;
    /// everything else in `settings` is clamped to what the new model accepts. With the engine
    /// idle the weights are swapped straight away. With a generation running or queued nothing
    /// is interrupted: the running image finishes on its model, queued entries keep theirs, and
    /// the new choice takes effect for whatever is generated next. Nothing is persisted here:
    /// which model was chosen is the app's business.
    public func switchModel(to descriptor: ModelDescriptor) {
        guard descriptor.id != self.descriptor.id else { return }
        logger.info("model chosen: \(descriptor.id, privacy: .public)")
        self.descriptor = descriptor
        settings = descriptor.capabilities.clamp(settings)
        guard !isDraining, queue.isEmpty else { return }
        reload(descriptor, thenDrain: false)
    }

    /// Releases whatever is loaded and loads `model` instead, then, if asked, carries on down
    /// the queue. The old weights go back before the new ones are asked for, so two sets are
    /// never resident at once. A load already under way is abandoned first.
    func reload(_ model: ModelDescriptor, thenDrain: Bool) {
        isSwitchingForQueue = thenDrain
        let pending = bootstrapTask
        pending?.cancel()
        transition(to: .idle)
        switchTask = Task {
            // The cancelled load may still be finishing a step, and may still land on .ready
            // for the model being left behind, so the state is settled again after it is done.
            await pending?.value
            await self.inference?.unload()
            self.loadedDescriptor = nil
            self.transition(to: .idle)
            await self.load(model)
            guard thenDrain else { return }
            if self.state == .ready {
                self.drain()
            } else {
                self.isSwitchingForQueue = false
                self.queue.removeAll()
            }
        }
    }
}
