import ZephraCore

/// Running a job again when the GPU threw it away for somebody else's fault.
///
/// An innocent victim (`BackendError.deviceVictim`) is the driver recovering from a fault in
/// another process — WindowServer under Screen Sharing, on every one bender has recorded — and
/// discarding this process's command buffer on the way. The weights are fine and the next run
/// works, which is why the failure's remedy was Try Again. Pressing it is not a decision
/// anybody needs to make, so the store makes it: the job goes back to the head of the queue
/// with the same seed and settings, under the same batch, and the picture that comes out is
/// the one that would have.
///
/// Once. A second victim on the same job fails as every other lost run does, with the same
/// sentence, because a Mac whose GPU is reset under it twice in a row should say so rather
/// than loop. A lost GPU (`.deviceLost`) is answered before this is asked and never reruns.
extension GenerationStore {
    /// Whether `error` is a victim fault this job may be run again for, and if so, runs it:
    /// queued at the head, the frame cleared, the queue drained.
    ///
    /// Only while the run is still `.generating` — a Stop that landed beside the fault has
    /// already emptied the queue and asked for the run to end, and a rerun would undo it — and
    /// only while the store takes work at all. Called from the run's own catch, on a task the
    /// fault cancelled, so nothing here may check cancellation; `drain` starts the rerun on a
    /// task of its own.
    func rerunAfterVictimFault(_ job: QueuedGeneration, error: BackendError) -> Bool {
        guard case .deviceVictim(let text) = error, !job.rerunAfterFault,
            case .generating = state, acceptsWork
        else { return false }
        logger.error(
            "the GPU discarded this run as the victim of another process's fault (\(text, privacy: .public)); running it again"
        )
        queue.insert(job.rerunningAfterFault(), at: 0)
        running = nil
        clearLivePreview()
        drain()
        return true
    }
}
