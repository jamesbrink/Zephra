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
    ///
    /// The comparison is against the policy's static answer, which is what makes an explicit
    /// change of preference the one thing that reloads a model the guard stepped down to
    /// streaming at its load: choosing Never over such a model asks for it held, and the guard
    /// is asked again on the way in — and refuses, with the preference as the remedy, if the
    /// Mac still has not the room.
    public func setWeightResidencyPolicy(_ policy: WeightResidencyPolicy) {
        guard policy != weightResidencyPolicy else { return }
        weightResidencyPolicy = policy
        guard let loadedDescriptor, let loadedResidency,
            policy.residency(for: loadedDescriptor) != loadedResidency,
            acceptsWork, !isDraining, !isUpscaling, queue.isEmpty
        else { return }
        logger.info(
            "weights of \(loadedDescriptor.id, privacy: .public) will be \(policy.residency(for: loadedDescriptor).rawValue, privacy: .public)"
        )
        reload(loadedDescriptor, thenDrain: false)
    }
}
