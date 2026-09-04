import Testing
import ZephraCore

@Suite("PreviewThrottle")
struct PreviewThrottleTests {
    @Test("the first frame of a run is never held back")
    func theFirstFrameGoesThrough() {
        var throttle = PreviewThrottle(interval: .seconds(1))
        let first = throttle.shouldMakeFrame(at: .now)
        #expect(first)
    }

    @Test("a frame inside the interval is refused and does not move the clock on")
    func withinTheInterval() {
        let start = ContinuousClock.Instant.now
        var throttle = PreviewThrottle(interval: .seconds(1))
        let asks = [0, 500, 900, 1_000].map {
            throttle.shouldMakeFrame(at: start + .milliseconds($0))
        }
        // The last one goes through because the interval is measured from the frame that was
        // made, not from the last one that was refused.
        #expect(asks == [true, false, false, true])
    }

    @Test("a step longer than the interval gets a frame every time")
    func slowSteps() {
        let start = ContinuousClock.Instant.now
        var throttle = PreviewThrottle(interval: .milliseconds(750))
        let asks = (0..<4).map { throttle.shouldMakeFrame(at: start + .seconds($0 * 7)) }
        #expect(asks.allSatisfy { $0 })
    }
}
