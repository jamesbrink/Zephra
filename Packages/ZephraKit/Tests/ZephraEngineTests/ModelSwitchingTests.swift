import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore model switching")
struct ModelSwitchingTests {
    /// A second model for the same backend, narrower than the catalog's in every direction, so
    /// a switch to it has something to clamp.
    static let smaller = ModelDescriptor(
        id: "test-smaller",
        displayName: "Test Model",
        variantName: "small",
        backend: .zImage,
        source: .huggingFace(repoID: "example/test-small", revision: "main", filePatterns: ["*"]),
        quantization: .int4,
        downloadBytes: 4_000_000_000,
        residentBytes: 4_000_000_000,
        maxPromptTokens: 128,
        capabilities: ModelCapabilities(
            sizeAlignment: 64,
            sizePresets: [ImageSize(width: 512, height: 512)],
            sizeBounds: 256...512,
            defaultSize: ImageSize(width: 512, height: 512),
            stepBounds: 1...4,
            defaultSteps: 2,
            guidanceBounds: 1...8,
            defaultGuidance: 4,
            supportsNegativePrompt: true,
            supportsSeed: true
        )
    )

    @Test("switching clamps the settings to the new model, keeping the prompt and the seed")
    func switchClampsSettings() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.size = ImageSize(width: 1344, height: 768)
        store.settings.steps = 9
        let seed = store.settings.seed

        store.switchModel(to: Self.smaller)
        await store.settle()

        #expect(store.descriptor.id == Self.smaller.id)
        #expect(store.settings.prompt == "a lighthouse")
        #expect(store.settings.seed == seed)
        #expect(store.settings.size == ImageSize(width: 512, height: 512))
        #expect(store.settings.steps == 4)
        #expect(store.settings.guidance == 1)
        #expect(store.state == .ready)
    }

    @Test("switching unloads the old model before loading the new one")
    func switchUnloadsThenLoads() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(bed.control.settings.loads == 1)
        #expect(bed.control.settings.unloads == 0)

        store.switchModel(to: Self.smaller)
        await store.settle()

        #expect(bed.control.settings.unloads == 1, "the old weights must go back first")
        #expect(bed.control.settings.loads == 2)
    }

    @Test("switching to the model already loaded does nothing at all")
    func switchToSameModelIsANoOp() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.switchModel(to: ModelCatalog.default)
        await store.settle()

        #expect(bed.control.settings.loads == 1)
        #expect(bed.control.settings.unloads == 0)
    }

    @Test("switching is refused while a generation is running, and nothing queued is lost")
    func switchIsRefusedWhileBusy() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(20) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.generate()
        store.generate()
        try await bed.waitForFirstStep()

        #expect(store.canSwitchModel == false)
        store.switchModel(to: Self.smaller)
        #expect(store.descriptor.id == ModelCatalog.default.id, "the model must not have changed")
        #expect(store.queue.count == 1, "the queued prompt must survive a refused switch")

        store.cancel()
        await store.settle()
    }

    @Test("switching is refused while a prompt is waiting, even between generations")
    func switchIsRefusedWithAQueue() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.queue.append(QueuedGeneration(settings: store.settings))

        #expect(store.canSwitchModel == false)
        store.switchModel(to: Self.smaller)
        #expect(store.descriptor.id == ModelCatalog.default.id)
    }
}
