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
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Generating image"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let clock = ContinuousClock()
        let started = clock.now
        let pump = EngineEventPump { [weak self] event in self?.applyGenerationEvent(event) }
        do {
            let media = try await pump.run { sink in
                try await inference.generate(job.settings, tile: vaeTile(for: job.model), events: sink)
            }
            // Stop pressed during the decode: the backend never looked, and the bytes are not
            // wanted. A stopped run keeps no image, whenever the stop landed.
            guard !Task.isCancelled else {
                finish()
                return
            }
            switch media {
            case .image(let png):
                complete(png, job: job, duration: clock.now - started)
            case .video:
                // The library's video seam is the next milestone; until then a clip has
                // nowhere to go, and saying so beats writing a poster that pretends to be it.
                fail(with: .backend(.generationFailed("This build cannot save a video yet.")))
            }
        } catch is CancellationError {
            finish()
        } catch BackendError.cancelled {
            finish()
        } catch let error as BackendError {
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
    private func complete(_ data: Data, job: QueuedGeneration, duration: Duration) {
        let image = GeneratedImage(
            pngData: data,
            settings: job.settings,
            modelID: job.model.id,
            duration: duration,
            batchID: job.batchID
        )
        if followsRun { current = image }
        history.insert(image, at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        lastDuration = duration
        save(image)
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
    }
}
