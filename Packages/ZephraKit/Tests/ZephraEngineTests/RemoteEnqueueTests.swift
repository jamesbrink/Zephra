import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("A paired device submits work without touching the capsule")
struct RemoteEnqueueTests {
    /// What a phone would send: a prompt of its own, a couple of steps so the mock is quick,
    /// and a seed nothing else in the test uses.
    static func request(
        prompt: String = "a lantern on a jetty at dusk",
        size: ImageSize = ImageSize(width: 512, height: 512),
        seed: UInt64 = 4_242
    ) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = prompt
        settings.size = size
        settings.steps = 2
        settings.seed = seed
        return settings
    }

    /// A model id no catalog entry uses, so admission has something genuinely unknown to
    /// refuse without the test having to drop a real entry.
    static let unknown = ModelDescriptor(
        id: "test-not-in-the-catalog",
        displayName: "Test Model",
        variantName: nil,
        backend: .zImage,
        source: .huggingFace(repoID: "example/unknown", revision: "main", filePatterns: ["*"]),
        quantization: .int4,
        downloadBytes: 1_000_000_000,
        residentBytes: 1_000_000_000,
        peakBytes: 2_000_000_000,
        tiledPeakBytes: 2_000_000_000,
        maxPromptTokens: 128,
        capabilities: ModelCatalog.default.capabilities
    )

    @Test("a remote submit leaves the capsule and the canvas exactly as they were")
    func capsuleIsUntouched() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "what the person at the Mac is typing"
        let typed = store.settings
        let chosen = store.descriptor

        let batch = store.enqueue(Self.request(), on: ModelCatalog.default)

        #expect(batch != nil)
        #expect(store.settings == typed, "the prompt being written is not the remote's")
        #expect(store.descriptor.id == chosen.id)
        #expect(!store.followsRun, "a remote run never takes the canvas")
        #expect(!store.capsuleHoldsPicture)
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()
        #expect(store.current == nil, "the result enters history, not the canvas")
        await store.shutdown()
    }

    @Test("a count of three queues three seeds of one batch")
    func threeSeedsShareABatch() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }

        let batch = try #require(store.enqueue(Self.request(), on: ModelCatalog.default, count: 3))
        // The first is taken by the drain at once, so the run in flight is one of the three.
        try await bed.waitForStep()
        let running = try #require(store.running)
        let all = [running] + store.queue

        #expect(all.count == 3)
        #expect(all.allSatisfy { $0.batchID == batch })
        #expect(Set(all.map(\.settings.seed)).count == 3, "every seed is its own")
        #expect(all.contains { $0.settings.seed == 4_242 }, "the seed asked for is one of them")
        #expect(all.map(\.batchIndex) == [0, 1, 2])

        store.cancel()
        await store.settle()
        await store.shutdown()
    }

    @Test("a submit while nothing runs drains, and the remote's prompt lands in history")
    func idleSubmitDrains() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "what the person at the Mac is typing"

        store.enqueue(Self.request(prompt: "a lantern on a jetty at dusk"), on: ModelCatalog.default)
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["a lantern on a jetty at dusk"])
        #expect(try bed.writtenFiles().count == 1)
        #expect(store.state == .ready)
        await store.shutdown()
    }

    @Test("a submit while a run is in flight waits its turn in the queue")
    func submitDuringARunQueues() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }

        store.settings.prompt = "the Mac's own picture"
        store.settings.steps = 8
        store.generate()
        try await bed.waitForStep()
        #expect(store.followsRun)

        let batch = store.enqueue(Self.request(prompt: "the phone's picture"), on: ModelCatalog.default)

        #expect(batch != nil)
        #expect(store.queue.map(\.settings.prompt) == ["the phone's picture"])
        #expect(store.running?.settings.prompt == "the Mac's own picture")
        #expect(store.followsRun, "the Mac's run keeps the canvas")
        #expect(store.settings.prompt == "the Mac's own picture")

        store.cancel()
        await store.settle()
        await store.shutdown()
    }

    @Test("an oversize request comes back on the model's own grid")
    func theClampApplies() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.stepsEmitted = 0; $0.stepDelay = .milliseconds(30) }
        let model = ModelCatalog.default
        let asked = ImageSize(width: 8_000, height: 1_020)

        store.enqueue(Self.request(size: asked), on: model, count: 2)
        try await bed.waitForStep()
        let queued = try #require(store.running)

        #expect(queued.settings.size == model.capabilities.fit(asked))
        #expect(queued.settings.size != asked)
        #expect(queued.settings.size.width % model.capabilities.sizeAlignment == 0)
        #expect(model.capabilities.sizeBounds.contains(queued.settings.size.width))
        #expect(store.queue.allSatisfy { $0.settings.size == queued.settings.size })

        store.cancel()
        await store.settle()
        await store.shutdown()
    }
}
