import Foundation
import Testing
import ZephraCore
@testable import ZephraEngine

@MainActor @Suite("A published chain records all of its generation time")
struct ChainTimingTests {
    @Test("A three-pass clip cannot be learned as only its final pass")
    func wholeChain() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store(descriptor: ModelCatalog.ltx2Distilled4bit)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a kite"
        store.settings.frames = 241
        store.settings.steps = 2
        store.generate()
        try await bed.waitUntil { store.history.count == 1 && store.state == .ready }
        let image = try #require(store.history.first)
        #expect(bed.control.settings.generations == 3)
        #expect(image.duration.seconds >= 0.11)
        #expect(GenerationRecord(image).durationSeconds >= 0.11)
        #expect(store.chains.isEmpty)
        await store.shutdown()
    }
}
