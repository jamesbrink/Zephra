import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore")
struct GenerationStoreTests {
    @Test("bootstrap loads and warms up, then a generation lands on the canvas and on disk")
    func happyPath() async throws {
        let scratch = Scratch()
        let store = scratch.store()
        await store.bootstrap()
        #expect(store.state == .ready)
        #expect(scratch.control.settings.loads == 1)
        #expect(scratch.control.settings.generations == 1, "warm-up should have run once")
        store.settings.prompt = "a lighthouse at dusk"
        store.settings.steps = 5
        #expect(store.canGenerate)
        store.generate()
        await store.settle()

        #expect(store.state == .ready)
        #expect(store.history.count == 1)
        #expect(store.current?.settings.prompt == "a lighthouse at dusk")
        #expect(store.current?.modelID == ModelCatalog.default.id)
        #expect(store.lastDuration != nil)
        #expect(store.current?.fileURL != nil)
        #expect(store.history.first?.fileURL != nil)

        let written = try scratch.writtenFiles()
        #expect(written.count == 1)
        #expect(written.first?.hasPrefix("zephra-") == true)
    }

    @Test("bootstrapping again once ready does nothing")
    func bootstrapIsIdempotent() async throws {
        let scratch = Scratch()
        let store = scratch.store()
        await store.bootstrap()
        await store.bootstrap()
        #expect(store.state == .ready)
        #expect(scratch.control.settings.loads == 1)
    }

    @Test("cancelling mid-generation returns to ready and keeps no image")
    func cancelMidGeneration() async throws {
        let scratch = Scratch()
        let store = scratch.store()
        await store.bootstrap()
        scratch.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(20) }

        store.settings.prompt = "a lighthouse"
        store.settings.steps = 8
        store.generate()
        try await scratch.waitForFirstStep()
        store.cancel()
        #expect(store.state == .cancelling)
        await store.settle()

        #expect(store.state == .ready)
        #expect(store.history.isEmpty)
        #expect(store.current == nil)
        #expect(store.lastDuration == nil)
        #expect(try scratch.writtenFiles().isEmpty)
    }

    @Test("a failed load surfaces as failed, and retry recovers once the fault is cleared")
    func failedLoadThenRetry() async throws {
        let scratch = Scratch()
        scratch.control.update { $0.loadError = .loadFailed("not enough memory") }
        let store = scratch.store()
        await store.bootstrap()
        #expect(store.state == .failed(.backend(.loadFailed("not enough memory"))))

        scratch.control.update { $0.loadError = nil }
        store.retry()
        await store.settle()
        #expect(store.state == .ready)
    }

    @Test("a generation failure surfaces without disturbing the canvas")
    func failedGeneration() async throws {
        let scratch = Scratch()
        let store = scratch.store()
        await store.bootstrap()
        scratch.control.update { $0.generateError = .generationFailed("kernel panic") }

        store.settings.prompt = "a lighthouse"
        store.generate()
        await store.settle()

        #expect(store.state == .failed(.backend(.generationFailed("kernel panic"))))
        #expect(store.history.isEmpty)
    }

    @Test("history keeps the newest 24 images")
    func historyIsCapped() async throws {
        let scratch = Scratch()
        scratch.control.update { $0.stepDelay = .zero }
        let store = scratch.store()
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 1

        for _ in 0..<26 {
            store.randomizeSeed()
            store.generate()
            await store.settle()
        }

        #expect(store.history.count == 24)
        #expect(store.history.first?.settings.seed == store.current?.settings.seed)
    }

    @Test("selecting an earlier image adopts its settings wholesale")
    func selectAdoptsSettings() {
        let scratch = Scratch()
        let store = scratch.store()
        var earlier = GenerationSettings.defaults(for: ModelCatalog.default)
        earlier.prompt = "a harbour in the rain"
        earlier.steps = 4
        earlier.seed = 99
        let image = GeneratedImage(
            pngData: MockBackend.pngData,
            settings: earlier,
            modelID: ModelCatalog.default.id,
            duration: .seconds(3)
        )

        store.settings.prompt = "something else entirely"
        store.select(image)

        #expect(store.current == image)
        #expect(store.settings == earlier)
    }

    @Test("generate does nothing without a prompt")
    func generateNeedsAPrompt() async throws {
        let scratch = Scratch()
        let store = scratch.store()
        await store.bootstrap()
        #expect(!store.canGenerate)
        store.generate()
        await store.settle()
        #expect(store.state == .ready)
        #expect(store.history.isEmpty)
    }
}
