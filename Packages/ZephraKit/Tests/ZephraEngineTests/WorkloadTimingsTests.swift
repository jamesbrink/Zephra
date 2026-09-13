import Foundation
import Testing
import ZephraCore
@testable import ZephraEngine

@MainActor @Suite("Passive timing comparability and bounded history")
struct WorkloadTimingsTests {
    func key(revision: String = "commit-a", residency: WeightResidency = .resident,
             reference: Bool = false, frames: Int = 1) -> WorkloadTimingKey {
        var settings = GenerationSettings.defaults(for: ModelCatalog.zImageTurbo4bit)
        settings.referenceImage = reference ? Data([1]) : nil
        settings.frames = frames
        return WorkloadTimingKey(modelID: "model", revision: revision, residency: residency,
            settings: settings, tiled: false)
    }
    @Test("Other weights, residency, references and clip lengths never borrow an ETA")
    func comparability() {
        let timings = WorkloadTimings()
        timings.record(key(), execution: 10, finalization: 2)
        #expect(timings.estimate(key())?.execution == 12)
        #expect(timings.estimate(key())?.finalization == 2.4)
        #expect(timings.estimate(key(revision: "commit-b")) == nil)
        #expect(timings.estimate(key(residency: .streamed)) == nil)
        #expect(timings.estimate(key(reference: true)) == nil)
        #expect(timings.estimate(key(frames: 241)) == nil)
    }
    @Test("Recent slow runs bound estimates; stale profiles and invalid observations expire")
    func bounded() {
        let timings = WorkloadTimings()
        timings.record(key(), execution: 100, finalization: 1)
        for _ in 0..<8 { timings.record(key(), execution: 10, finalization: 2) }
        #expect(timings.estimate(key())?.execution == 12)
        #expect(timings.estimate(key())?.samples == 8)
        timings.record(key(), execution: .nan, finalization: 0)
        #expect(timings.estimate(key())?.samples == 8)
        for index in 0..<64 { timings.record(key(revision: "other-\(index)"), execution: 1, finalization: 0) }
        #expect(timings.estimate(key()) == nil)
    }
    @Test("A busy run subtracts elapsed work without claiming an overdue run is finished")
    func remaining() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        var settings = store.settings
        settings.prompt = "a kite"
        let job = QueuedGeneration(model: store.descriptor, settings: settings, batchID: UUID(), batchIndex: 0)
        let key = try #require(store.timingKey(model: store.descriptor, settings: settings))
        store.timings.record(key, execution: 100, finalization: 0)
        store.running = job
        store.timingRunStarted = ContinuousClock.now - .seconds(30)
        let remaining = try #require(store.remainingTiming(for: job))
        #expect(remaining > 89 && remaining <= 90)
        store.timingRunStarted = ContinuousClock.now - .seconds(200)
        #expect(store.remainingTiming(for: job) == 12)
        store.running = nil
        await store.shutdown()
    }
}
