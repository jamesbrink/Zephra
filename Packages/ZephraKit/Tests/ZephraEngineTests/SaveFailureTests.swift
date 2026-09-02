import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore saving")
struct SaveFailureTests {
    @Test("a save that fails is a notice, and the queue behind it still runs down")
    func saveFailureIsANotice() async throws {
        let bed = EngineTestBed()
        let store = try bed.storeThatCannotSave()
        await store.bootstrap()
        bed.control.update { $0.stepDelay = .milliseconds(15) }
        store.settings.prompt = "first"
        store.settings.steps = 2
        store.generate()
        store.settings.prompt = "second"
        store.generate()

        while store.isRunning || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.state == .ready, "a full disk must not stop the engine")
        #expect(store.history.map(\.settings.prompt) == ["second", "first"])
        #expect(store.current?.fileURL == nil)
        let failure = try #require(store.lastSaveFailure)
        #expect(failure.imageID == store.current?.id)
        #expect(!failure.message.isEmpty)
    }

    @Test("the next image that saves clears the notice")
    func saveFailureClearsOnTheNextSave() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        store.lastSaveFailure = SaveFailure(imageID: UUID(), reason: "The disk was full.")

        store.settings.prompt = "a lighthouse"
        store.settings.steps = 1
        store.generate()
        await store.settle()

        #expect(store.lastSaveFailure == nil)
        #expect(store.current?.fileURL != nil)
    }
}
