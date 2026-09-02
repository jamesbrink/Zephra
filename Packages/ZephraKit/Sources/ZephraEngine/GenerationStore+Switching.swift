import ZephraCore

/// Changing which model the store drives, at runtime, without losing work.
extension GenerationStore {
    /// Whether a different model may be chosen right now.
    ///
    /// A generation in flight or waiting says no. Switching would have to throw that work away,
    /// and losing a queued prompt silently is worse than a menu that is briefly unavailable, so
    /// stopping first is left as the user's decision. A download or a load has nothing to lose,
    /// so switching out of one is allowed and simply abandons it.
    public var canSwitchModel: Bool {
        !isRunning && queue.isEmpty
    }

    /// Loads a different model in place of the current one.
    ///
    /// Does nothing if it is already the current model, or if `canSwitchModel` is false. The
    /// prompt and the seed survive; everything else in `settings` is clamped to what the new
    /// model accepts. The old weights are released before the new ones are asked for, so two
    /// sets are never resident at once. Nothing is persisted here: which model was chosen is
    /// the app's business, and the app hands the descriptor back at the next launch.
    public func switchModel(to descriptor: ModelDescriptor) {
        guard canSwitchModel, descriptor.id != self.descriptor.id else { return }
        logger.info("switching model to \(descriptor.id, privacy: .public)")
        let pending = bootstrapTask
        pending?.cancel()
        self.descriptor = descriptor
        settings = descriptor.capabilities.clamp(settings)
        transition(to: .idle)
        switchTask = Task {
            // The cancelled load may still be finishing a step, and may still land on .ready
            // for the model being left behind, so the state is settled again after it is done.
            await pending?.value
            await self.inference?.unload()
            self.transition(to: .idle)
            await self.bootstrap()
        }
    }
}
