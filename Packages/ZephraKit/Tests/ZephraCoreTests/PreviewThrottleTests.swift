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

    @Test("a frame holds the next until ten times its own cost has passed")
    func costShare() {
        let start = ContinuousClock.Instant.now
        var throttle = PreviewThrottle(interval: .milliseconds(750))
        let first = throttle.shouldMakeFrame(at: start)
        #expect(first)
        // A frame that took a second and a half, finished at 1.5 s: the next may not be made
        // before 16.5 s, so a run stepping every six seconds gets one every third step.
        throttle.madeFrame(costing: .milliseconds(1_500), at: start + .milliseconds(1_500))
        let asks = [6, 12, 18].map { throttle.shouldMakeFrame(at: start + .seconds($0)) }
        #expect(asks == [false, false, true])
    }

    @Test("a cheap frame is held by the interval alone")
    func cheapFramesKeepTheInterval() {
        let start = ContinuousClock.Instant.now
        var throttle = PreviewThrottle(interval: .milliseconds(750))
        let first = throttle.shouldMakeFrame(at: start)
        #expect(first)
        // Forty milliseconds, klein's frame: ten of them is under the interval.
        throttle.madeFrame(costing: .milliseconds(40), at: start + .milliseconds(40))
        let asks = [500, 750].map { throttle.shouldMakeFrame(at: start + .milliseconds($0)) }
        #expect(asks == [false, true])
    }

    @Test("every step says yes to every ask, and a dear frame holds nothing back")
    func everyStepAlwaysSaysYes() {
        let start = ContinuousClock.Instant.now
        var throttle = PreviewThrottle.everyStep
        var asks: [Bool] = []
        for tick in 0..<4 {
            let now = start + .milliseconds(tick)
            asks.append(throttle.shouldMakeFrame(at: now))
            throttle.madeFrame(costing: .seconds(2), at: now)
        }
        #expect(asks == [true, true, true, true])
    }
}
