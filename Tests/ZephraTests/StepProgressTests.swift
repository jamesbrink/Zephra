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
