import Foundation
import ZephraCore

/// Running a generation and recording the result. Split out of `GenerationStore.swift` to
/// keep the observed surface of the store readable on its own; getting the result onto disk
/// is `GenerationStore+Saving.swift`.
extension GenerationStore {
    /// Kicks off `job` on the inference actor. Only the queue calls this.
    func start(_ job: QueuedGeneration) {
        guard let inference else { return }
        clearLivePreview()
        transition(to: .generating(GenerationProgressEvent(phase: .preparing, fraction: 0)))
        generationTask = Task { await self.run(job, on: inference) }
    }

    /// Returns to `.ready`, then works on down the queue. Every way a run can end goes through
    /// here so the queue never stalls.
    private func finish() {
        running = nil
        clearLivePreview()
        transition(to: .ready)
        drain()
    }

    /// Drives one generation from start to finish. The activity assertion keeps the Mac awake:
    /// a generation is a long stretch of silent Metal work with no user input behind it.
    func run(_ job: QueuedGeneration, on inference: InferenceActor) async {
        // The weights are in; what this run wants on top of them may still be more than the
        // Mac has left. Refused here rather than inside Metal, where it is an abort.
        if let shortfall = runShortfall(for: job) {
            // The weights are in resident and this request has not the room on top of them.
            // Under Automatic, reading them from disk instead is a load rather than a refusal:
            // the same step down the guard makes before a load, made after one.
            if stepDownToStreaming(for: job) { return }
            failJob(job, with: .insufficientMemory(shortfall))
            return
        }
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Generating image"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let clock = ContinuousClock()
        let started = clock.now
        timingRunStarted = started
        defer { timingRunStarted = nil }
        let profile = timingKey(for: job)
        let earlierExecution = job.chain.flatMap { chains[$0.chainID]?.executionElapsed } ?? .zero
        if let chain = job.chain { chains[chain.chainID]?.timingKey = profile }
        let earlierPasses = job.chain.flatMap { chains[$0.chainID]?.elapsed } ?? .zero
        let pump = EngineEventPump { [weak self] event in self?.applyGenerationEvent(event) }
        do {
            let segment = try await pump.run { sink in
                try await inference.generate(job.settings, tile: vaeTile(for: job.model), events: sink)
            }
            let execution = clock.now - started
            // Stop pressed during the decode: the backend never looked, and the bytes are not
            // wanted. A stopped run keeps no image, whenever the stop landed.
            guard !Task.isCancelled else {
                finish()
                return
            }
            // A pass of a chained clip is kept and carries on into the next, or, as the last,
            // is joined with the rest (`GenerationStore+Chaining.swift`); a continuation's
            // segment is joined onto its source (`+Stitching.swift`). Both happen here, still
            // inside the run, so what is published is always the whole clip.
            var settings = job.settings
            let media: GeneratedMedia
            if let chain = job.chain {
                guard let joined = try await advanceChain(segment, job: job, segment: chain) else {
                    if chains[chain.chainID] != nil {
                        chains[chain.chainID]?.elapsed += clock.now - started
                        chains[chain.chainID]?.executionElapsed += execution
                    }
                    finish()
                    return
                }
                media = joined.media
                if case .video(let clip) = joined.media {
                    settings = chainedSettings(settings, segment: chain, frames: clip.frameCount, source: joined.source)
                }
            } else {
                media = try await stitched(segment, job: job)
            }
            guard !Task.isCancelled else {
                finish()
                return
            }
            complete(media, job: job, settings: settings, duration: earlierPasses + (clock.now - started),
                profile: profile, execution: (earlierExecution + execution).seconds)
        } catch is CancellationError {
            finish()
        } catch BackendError.cancelled {
            finish()
        } catch let error as BackendError {
            // `.deviceFailed` arrives here, and the boundary that raised it cancelled this very
            // task to unwind the run. Nothing from here down may sleep or check cancellation,
            // or a picture the GPU lost would be reported as a stop nobody pressed.
            fail(with: .backend(error))
        } catch {
            fail(with: .backend(.generationFailed(error.localizedDescription)))
        }
    }

    /// Everything a failed generation puts down: the queue, the run, and the frame it was last
    /// showing. One place rather than two, because the two `catch` clauses differ only in how
    /// they name the error.
    private func fail(with error: EngineError) {
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
    private func failJob(_ job: QueuedGeneration, with error: EngineError) {
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
    private func complete(
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

    func applyLoadEvent(_ event: EngineEvent) {
        switch event {
        case .download(let progress): state = .downloading(progress)
        case .build(let progress): state = .building(progress)
        case .progress(let progress): state = .loading(progress.phase)
        // A load never upscales anything; the case is here because the switch is exhaustive.
        case .upscale: break
        }
    }

    /// Progress that arrives after a cancel was asked for is dropped, so the interface does not
    /// flick back from `.cancelling` to `.generating` for the last step of a doomed run.
    private func applyGenerationEvent(_ event: EngineEvent) {
        guard case .generating = state, case .progress(let progress) = event else { return }
        state = .generating(progress)
        // Kept out of the state, which is compared and hashed on every transition, and which a
        // late event would otherwise be able to put a stale frame back into.
        if let preview = progress.preview { livePreview = preview }
    }

    /// The one place `state` changes for a reason worth a log line. Progress updates go through
    /// the two apply methods above instead, because one line per denoising step is noise.
    func transition(to newState: EngineState) {
        guard newState != state else { return }
        logger.info(
            "state \(self.state.logName, privacy: .public) -> \(newState.logName, privacy: .public)"
        )
        state = newState
        // Every load, generation, upscale, swap and failure passes through here, so the idle
        // clock is reset by the fact of having transitioned and nothing has to remember to.
        armIdleUnload()
    }
}
