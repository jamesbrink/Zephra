import ZephraCore

/// Where the weights live: resident, or streamed from disk on every step.
extension GenerationStore {
    /// Adopts `policy` for every load from now on and, if the loaded model would be held the
    /// other way under it, reloads that model so the change is felt without a relaunch.
    ///
    /// The reload goes through the same swap path a change of model does, so the old weights
    /// are released before the new ones are read and nothing running is interrupted: with a
    /// generation running or queued the new residency waits for the next load, the way a
    /// model chosen mid-run does.
    public func setWeightResidencyPolicy(_ policy: WeightResidencyPolicy) {
        guard policy != weightResidencyPolicy else { return }
        weightResidencyPolicy = policy
        guard let loadedDescriptor, let loadedResidency,
            policy.residency(for: loadedDescriptor) != loadedResidency,
            !isChangingModelDirectory, !isDraining, !isUpscaling, queue.isEmpty
        else { return }
        logger.info(
            "weights of \(loadedDescriptor.id, privacy: .public) will be \(policy.residency(for: loadedDescriptor).rawValue, privacy: .public)"
        )
        reload(loadedDescriptor, thenDrain: false)
    }
}
