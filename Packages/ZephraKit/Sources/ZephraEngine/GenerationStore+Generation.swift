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
            //
            // `.deviceLost` is the other one: the run is lost the same way, but so is the GPU,
            // so the failure is the store's own rather than the backend's and nothing else is
            // offered to submit.
            if noteIfDeviceLost(error) {
                fail(with: .deviceLost)
                return
            }
            // Somebody else's fault cost this run and nothing else: it goes again, once.
            if rerunAfterVictimFault(job, error: error) { return }
            fail(with: .backend(error))
        } catch {
            fail(with: .backend(.generationFailed(error.localizedDescription)))
        }
    }

    /// A load event landing after the GPU is lost is dropped: the load it belongs to has been
    /// cancelled and `.failed(.deviceLost)` is the one state the interface may show over it.
    /// `transition(to:)` rewrites its own answer for the same reason; this is the one other
    /// writer of `state` a load reaches.
    func applyLoadEvent(_ event: EngineEvent) {
        guard !deviceLost else { return }
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
        // Asked here because every state change funnels through, which is the only way to
        // notice a loss the runtime latched outside a run — the allocator's cache handed back
        // by an unload is where bender's first ignored submission landed. Once it is noticed
        // the engine has one state: a Mac whose GPU refuses it is not idle and is not ready.
        noteDeviceLossIfLatched()
        let newState = deviceLost ? EngineState.failed(.deviceLost) : newState
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
