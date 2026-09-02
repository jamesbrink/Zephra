import Testing
import ZephraCore

@Suite("GenerationProgressEvent")
struct GenerationProgressEventTests {
    @Test("the countdown is the remaining steps at the measured pace")
    func countdown() {
        let event = GenerationProgressEvent(
            phase: .denoising(step: 3, of: 9),
            fraction: 3.0 / 9.0,
            secondsPerStep: 0.5
        )
        #expect(event.estimatedSecondsRemaining == 3.0)
    }

    @Test("the last step has nothing left to count down")
    func lastStep() {
        let event = GenerationProgressEvent(
            phase: .denoising(step: 9, of: 9),
            fraction: 1,
            secondsPerStep: 0.5
        )
        #expect(event.estimatedSecondsRemaining == 0)
    }

    @Test("a countdown needs a measured pace first")
    func needsAPace() {
        let event = GenerationProgressEvent(phase: .denoising(step: 1, of: 9), fraction: 0.1)
        #expect(event.estimatedSecondsRemaining == nil)
    }

    @Test("phases other than denoising have no predictable pace")
    func otherPhases() {
        let event = GenerationProgressEvent(phase: .decoding, fraction: 1, secondsPerStep: 0.5)
        #expect(event.estimatedSecondsRemaining == nil)
    }
}
