import Testing
import ZephraLinkProtocol

@testable import ZephraMobile

/// The step bar is a reading of what the Mac sent and nothing else. These are the four things
/// it can say.
@Suite("The step bar reads the Mac's engine state")
struct StepProgressTests {
    @Test("Nothing running is no bar at all")
    func idleIsInvisible() {
        let progress = StepProgress(EngineStateDTO(kind: .ready))
        #expect(!progress.isRunning)
        #expect(progress.completed == 0)
    }

    @Test("A run four steps into nine fills four of nine segments")
    func midRunCounts() {
        let progress = StepProgress(
            EngineStateDTO(kind: .generating, step: 4, steps: 9, isBusy: true))
        #expect(progress.isRunning)
        #expect(progress.completed == 4)
        #expect(progress.total == 9)
    }

    @Test("A run being finished keeps the bar up and full")
    func finishingStaysFull() {
        let progress = StepProgress(
            EngineStateDTO(kind: .generating, step: 9, steps: 9, isBusy: true, isFinishing: true))
        #expect(progress.isRunning)
        #expect(progress.completed == progress.total)
        #expect(progress.total == 9)
    }

    @Test("A step past the count cannot overfill the bar")
    func stepIsHeldInsideTheCount() {
        let progress = StepProgress(EngineStateDTO(kind: .generating, step: 12, steps: 9))
        #expect(progress.completed == 9)
    }

    @Test("A Mac that has said nothing yet draws no bar")
    func noEngineIsNoBar() {
        let progress = StepProgress(nil)
        #expect(!progress.isRunning)
        #expect(progress.total == 0)
    }
}
