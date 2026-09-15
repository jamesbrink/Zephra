import Foundation
import ZephraCore

/// The four ways a generation ends: finished and published, stopped, lost to a backend failure,
/// or refused before it began. Split out of `GenerationStore+Generation.swift`, which keeps the
/// run itself; getting the result onto disk is `GenerationStore+Saving.swift`.
extension GenerationStore {
    /// Returns to `.ready`, then works on down the queue. Every way a run can end goes through
    /// here so the queue never stalls.
    func finish() {
        running = nil
        clearLivePreview()
        transition(to: .ready)
        drain()
    }

    /// Everything a failed generation puts down: the queue, the run, and the frame it was last
    /// showing. One place rather than two, because the two `catch` clauses differ only in how
    /// they name the error.
    func fail(with error: EngineError) {
        queue.removeAll()
        dropChains()
        running = nil
        clearLivePreview()
        transition(to: .failed(error))
    }

    /// What one job's refusal puts down: that press of Generate and nothing else. A run the GPU
    /// lost is a reason to stop everything (`fail(with:)`); one request this Mac has not the
    /// memory for this minute is not a reason to throw away the four queued behind it.
    ///
    /// What is left does not drain on: `.failed` is a sentence somebody has to read, and a
    /// `.generating` arriving on top of it would take it away before anybody had. The next press
    /// of Generate drains the survivors, and so does Try Again.
    func failJob(_ job: QueuedGeneration, with error: EngineError) {
        // Every seed of one press owns a chain of its own — `generate(count:)` plans one per
        // seed — so the batch takes all of them with it. A `ChainProgress` left behind holds a
        // clip's PNG frames that nothing will ever read again.
        for entry in queue where entry.batchID == job.batchID {
            if let chain = entry.chain { chains[chain.chainID] = nil }
        }
        if let chain = job.chain { chains[chain.chainID] = nil }
        queue.removeAll { $0.batchID == job.batchID }
        running = nil
        clearLivePreview()
        transition(to: .failed(error))
    }

    /// Publishes a finished image straight away and only then starts writing it, so the canvas
    /// never waits on the file system.
    ///
    /// It reaches the canvas only while the canvas is following the run. A result that lands
    /// while the user is looking at something else still enters history, the wall, and the
    /// library; what it does not do is yank the picture out from under them.
    ///
    /// The batch and the model are the job's own rather than `running`'s or the store's: a
    /// cancel empties `running` and a switch moves `descriptor` before the run is over.
    ///
    /// A clip arrives as its poster and its MP4; the poster is the picture everything below
    /// handles, and the MP4 rides along to be written beside it.
    func complete(
        _ media: GeneratedMedia, job: QueuedGeneration, settings: GenerationSettings, duration: Duration,
        profile: WorkloadTimingKey?, execution: Double
    ) {
        var video: GeneratedVideo?
        if case .video(let clip) = media { video = clip }
        let image = GeneratedImage(
            pngData: media.posterPNG,
            settings: Self.published(settings),
            modelID: job.model.id,
            duration: duration,
            batchID: job.batchID,
            video: video
        )
        if followsRun { current = image }
        history.insert(image, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        lastDuration = duration
        save(image, timing: profile.map { WorkloadTimings.Sample(key: $0, execution: execution,
            finalization: max(0, duration.seconds - execution)) })
        finish()
    }
}
