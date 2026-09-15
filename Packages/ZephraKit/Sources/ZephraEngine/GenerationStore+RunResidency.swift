import ZephraCore

/// Reading the weights from disk rather than refusing a run.
///
/// `MemoryGuard.loadResidency` already steps a resident load down to streaming before the
/// weights are read. These two do the same thing after them: once at the run check, where a
/// request that has not the room over resident weights is a load rather than a sentence, and
/// once at Try Again, where the Mac the retry finds may be a fuller one than the load found.
extension GenerationStore {
    /// Whether this job's refusal can be answered by reading the weights from disk, and if so,
    /// does it: the job goes back to the head of the queue and the model is reloaded streamed
    /// under it.
    func stepDownToStreaming(for job: QueuedGeneration) -> Bool {
        guard weightResidencyPolicy.mode == .automatic,
            loadedResidency == .resident,
            loadedDescriptor?.id == job.model.id,
            job.model.streamedPeakBytes > 0,
            runShortfall(for: job.model, settings: job.settings, residency: .streamed) == nil
        else { return false }
        logger.info(
            "run of \(job.model.id, privacy: .public) has not the room over resident weights; reloading streamed"
        )
        residencyOverride = .streamed
        queue.insert(job, at: 0)
        running = nil
        clearLivePreview()
        reload(job.model, thenDrain: true)
        return true
    }

    /// The residency a model already loaded resident should be reloaded at, or nil when it
    /// should stay as it is. Only ever `.streamed`, only under Automatic, and only when the
    /// guard now says streaming fits and holding does not.
    func residencyToStepDownTo(_ model: ModelDescriptor) -> WeightResidency? {
        guard weightResidencyPolicy.mode == .automatic, loadedResidency == .resident,
            model.streamedPeakBytes > 0
        else { return nil }
        let answer = loadResidency(for: model)
        guard answer.shortfall == nil, answer.residency == .streamed else { return nil }
        return .streamed
    }
}
