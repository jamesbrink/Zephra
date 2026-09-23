import Foundation
import Testing
import ZephraCore

@Suite("PreviewFrameReporter")
struct PreviewFrameReporterTests {
    /// A stand-in for a kit's frame: two by one pixels, opaque.
    private struct Frame: PreviewFrame {
        let width = 2
        let height = 1
        let pixels = Data([1, 2, 3, 255, 4, 5, 6, 255])
    }

    @Test("no interval means no handler at all, so a loop skips the check")
    func noIntervalNoHandler() {
        let handler: PreviewFrameReporter.Handler<Frame>? = PreviewFrameReporter.handler(
            interval: nil, onProgress: { _ in })
        #expect(handler == nil)
    }

    @Test("a frame is decoded once per interval and reported after its step")
    func framesAreThrottledAndReported() throws {
        var events: [GenerationProgressEvent] = []
        var decodes = 0
        let report: PreviewFrameReporter.Handler<Frame> = try #require(
            PreviewFrameReporter.handler(interval: .seconds(60)) { events.append($0) })
        for step in 0..<3 {
            report(step, 4) {
                decodes += 1
                return Frame()
            }
        }
        // The first ask always goes through; the next two are inside a minute of it.
        #expect(decodes == 1)
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.phase == .denoising(step: 1, of: 4))
        let preview = try #require(event.preview)
        #expect(preview.width == 2 && preview.height == 1)
        #expect(preview.pixels == Frame().pixels)
        #expect(preview.isWellFormed)
    }

    @Test("a frame that cannot be packed is dropped rather than failing the run")
    func aFrameThatThrowsIsDropped() throws {
        struct NotAFrame: Error {}
        var events: [GenerationProgressEvent] = []
        let report: PreviewFrameReporter.Handler<Frame> = try #require(
            PreviewFrameReporter.handler(interval: .seconds(60)) { events.append($0) })

        report(0, 4) { throw NotAFrame() }

        #expect(events.isEmpty)
    }

    @Test("every step makes a frame on every call, however soon after the last")
    func everyStepMakesEveryFrame() throws {
        var events: [GenerationProgressEvent] = []
        let report: PreviewFrameReporter.Handler<Frame> = try #require(
            PreviewFrameReporter.handler(interval: .seconds(60), cadence: .everyStep) {
                events.append($0)
            })
        for step in 0..<5 { report(step, 6) { Frame() } }
        #expect(events.count == 5)
    }

    @Test("off makes no handler at all")
    func offMakesNoHandler() {
        let handler: PreviewFrameReporter.Handler<Frame>? = PreviewFrameReporter.handler(
            interval: .seconds(1), cadence: .off, onProgress: { _ in })
        #expect(handler == nil)
    }

    @Test("a launch that switched frames off beats every step")
    func noIntervalBeatsEveryStep() {
        let handler: PreviewFrameReporter.Handler<Frame>? = PreviewFrameReporter.handler(
            interval: nil, cadence: .everyStep, onProgress: { _ in })
        #expect(handler == nil)
    }

    @Test("the cadence is read from the task the backend runs on")
    func theCadenceIsTheTaskLocal() {
        #expect(PreviewCadence.current == .balanced)
        PreviewCadence.$current.withValue(.off) {
            let handler: PreviewFrameReporter.Handler<Frame>? = PreviewFrameReporter.handler(
                interval: .seconds(1), onProgress: { _ in })
            #expect(handler == nil)
        }
    }
}
