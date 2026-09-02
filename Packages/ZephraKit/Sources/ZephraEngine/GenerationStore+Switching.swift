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
    /// never resident at once. A load or an earlier swap already under way is cancelled and
    /// waited for first, so two quick picks in the menu never race each other's unload.
    func reload(_ model: ModelDescriptor, thenDrain: Bool) {
        isSwitchingForQueue = thenDrain
        isSwappingModel = true
        let pendingLoad = bootstrapTask
        let pendingSwitch = switchTask
        pendingLoad?.cancel()
        pendingSwitch?.cancel()
        transition(to: .idle)
        switchTask = Task {
            // The cancelled work may still be finishing a step, and may still land on .ready
            // for the model being left behind, so the state is settled again after it is done.
            await pendingSwitch?.value
            await pendingLoad?.value
            guard !Task.isCancelled else { return }
            await self.inference?.unload()
            self.loadedDescriptor = nil
            self.transition(to: .idle)
            guard !Task.isCancelled else { return }
            await self.load(model, asSwap: true)
            // A superseded or stopped swap leaves the flag to whoever superseded or stopped it.
            if !Task.isCancelled {
                self.isSwappingModel = false
            }
            guard thenDrain, !Task.isCancelled else { return }
            if self.state == .ready {
                self.drain()
            } else {
                self.isSwitchingForQueue = false
                self.queue.removeAll()
            }
        }
    }
}
