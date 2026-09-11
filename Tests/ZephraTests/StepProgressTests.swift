import Foundation
import Testing
import ZephraCore
import ZephraEngine

@testable import Zephra

@Suite("What the step bar counts")
struct StepProgressTests {
    private func settings(steps: Int) -> GenerationSettings {
        GenerationSettings(
            prompt: "a red bicycle", size: ImageSize(width: 512, height: 512), steps: steps, guidance: 0, seed: 1)
    }

    @Test("a queued 9-step run behind a 4-step one draws four segments")
    func theRunInFlightSetsTheCount() {
        let reading = StepProgress(
            state: .generating(GenerationProgressEvent(phase: .encodingText, fraction: 0)),
            running: settings(steps: 4), next: settings(steps: 9))
        #expect(reading.total == 4)
        #expect(reading.completed == 0)
        #expect(!reading.isRunning)
    }

    @Test("once the loop reports, its own total is the count, whatever the slider says")
    func theLoopsTotalWins() {
        let reading = StepProgress(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 2, of: 4), fraction: 0.5)),
            running: settings(steps: 4), next: settings(steps: 9))
        #expect(reading == StepProgress(completed: 2, total: 4, isRunning: true))
    }

    @Test("a pass of a chained clip counts as its share of the whole")
    func chainedPassesReadAsOneRun() {
        let chain = ChainSegment(chainID: UUID(), index: 1, count: 3)
        let reading = StepProgress(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 2, of: 8), fraction: 0.25)),
            running: settings(steps: 8), next: settings(steps: 8), chain: chain)
        #expect(reading == StepProgress(completed: 10, total: 24, isRunning: true))
        let finishing = StepProgress(
            state: .generating(GenerationProgressEvent(phase: .decoding, fraction: 1)),
            running: settings(steps: 8), next: settings(steps: 8), chain: chain)
        #expect(finishing == StepProgress(completed: 16, total: 24, isRunning: true))
    }

    @Test("the bar stays up and full from the last step until the result lands")
    func theBarStaysFullWhileFinishing() {
        let developing = StepProgress(
            state: .generating(GenerationProgressEvent(phase: .decoding, fraction: 1)),
            running: settings(steps: 8), next: settings(steps: 9))
        #expect(developing == StepProgress(completed: 8, total: 8, isRunning: true))
        let encoding = StepProgress(
            state: .generating(GenerationProgressEvent(phase: .saving, fraction: 1)),
            running: settings(steps: 8), next: settings(steps: 9))
        #expect(encoding == StepProgress(completed: 8, total: 8, isRunning: true))
    }

    @Test("with nothing running the count is the next run's, and the bar is not showing")
    func idleCountsTheNextRun() {
        let reading = StepProgress(state: .ready, running: nil, next: settings(steps: 9))
        #expect(reading == StepProgress(completed: 0, total: 9, isRunning: false))
    }

    @Test("the store reads the run it holds, not the capsule's slider")
    func theStoreReadsItsRun() {
        let flight = InterfacePreview.queuedRun(of: 1, steps: 4)
        let store = GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .preparing, fraction: 0)),
            running: flight[0])
        store.settings.steps = 9
        #expect(store.stepProgress.total == 4)
    }
}
