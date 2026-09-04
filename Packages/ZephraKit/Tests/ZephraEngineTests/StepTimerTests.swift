import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("StepTimer")
struct StepTimerTests {
    private let start = ContinuousClock.now

    @Test("no pace is reported until a whole step has been timed")
    func needsTwoTicks() {
        var timer = StepTimer()
        #expect(timer.secondsPerStep == nil)
        timer.tick(at: start)
        #expect(timer.secondsPerStep == nil)
        timer.tick(at: start.advanced(by: .milliseconds(100)))
        #expect(isClose(timer.secondsPerStep, 0.1))
    }

    @Test("the mean covers only the last three intervals")
    func rollingMean() {
        var timer = StepTimer()
        for offset in [0, 100, 300, 600, 1500] {
            timer.tick(at: start.advanced(by: .milliseconds(offset)))
        }
        // Intervals are 0.1, 0.2, 0.3 and 0.9 seconds; the first has aged out of the window.
        #expect(isClose(timer.secondsPerStep, (0.2 + 0.3 + 0.9) / 3))
    }

    @Test("annotating fills in a pace the backend did not measure")
    func annotationFillsGaps() {
        var timer = StepTimer()
        let first = timer.annotated(event(step: 1), at: start)
        #expect(first.secondsPerStep == nil)
        let second = timer.annotated(event(step: 2), at: start.advanced(by: .milliseconds(250)))
        #expect(isClose(second.secondsPerStep, 0.25))
        #expect(second.phase == .denoising(step: 2, of: 4))
        #expect(isClose(second.estimatedSecondsRemaining, 0.5))
    }

    @Test("annotating leaves a pace the backend measured itself")
    func annotationDefersToTheBackend() {
        var timer = StepTimer()
        _ = timer.annotated(event(step: 1), at: start)
        let measured = GenerationProgressEvent(
            phase: .denoising(step: 2, of: 4),
            fraction: 0.5,
            secondsPerStep: 42
        )
        let annotated = timer.annotated(measured, at: start.advanced(by: .milliseconds(250)))
        #expect(annotated.secondsPerStep == 42)
    }

    @Test("a frame carries the pace along without counting as a step")
    func framesDoNotTick() {
        var timer = StepTimer()
        _ = timer.annotated(event(step: 1), at: start)
        let second = timer.annotated(event(step: 2), at: start.advanced(by: .milliseconds(400)))
        #expect(isClose(second.secondsPerStep, 0.4))
        // The frame lands moments before the next step's own report; a timer that counted it
        // would average in a near-zero interval and halve the pace on screen.
        let frame = GenerationProgressEvent(
            phase: .denoising(step: 2, of: 4), fraction: 0.5,
            preview: MockBackend.preview(step: 2))
        let annotatedFrame = timer.annotated(frame, at: start.advanced(by: .milliseconds(790)))
        #expect(isClose(annotatedFrame.secondsPerStep, 0.4))
        #expect(annotatedFrame.preview != nil)
        let third = timer.annotated(event(step: 3), at: start.advanced(by: .milliseconds(800)))
        #expect(isClose(third.secondsPerStep, 0.4))
    }

    @Test("phases other than denoising are passed through untouched")
    func nonDenoisingPhasesAreUntouched() {
        var timer = StepTimer()
        let decoding = GenerationProgressEvent(phase: .decoding, fraction: 1)
        #expect(timer.annotated(decoding, at: start) == decoding)
        #expect(timer.secondsPerStep == nil)
    }

    private func event(step: Int) -> GenerationProgressEvent {
        GenerationProgressEvent(phase: .denoising(step: step, of: 4), fraction: Double(step) / 4)
    }

    private func isClose(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9
    }
}
