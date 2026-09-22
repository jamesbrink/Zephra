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
        peakBytes: 8_000_000_000,
        tiledPeakBytes: 6_000_000_000,
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

    /// A model of another family whose bounds are wide enough to clamp nothing, so the only
    /// thing that can move the step count on a switch to it is the family change itself.
    static let otherFamily = ModelDescriptor(
        id: "test-other-family",
        displayName: "Test Model",
        variantName: "other family",
        backend: .flux2,
        source: .huggingFace(repoID: "example/other", revision: "main", filePatterns: ["*"]),
        quantization: .int4,
        downloadBytes: 4_000_000_000,
        residentBytes: 4_000_000_000,
        peakBytes: 8_000_000_000,
        tiledPeakBytes: 6_000_000_000,
        maxPromptTokens: 1024,
        capabilities: ModelCapabilities(
            sizeAlignment: 16,
            sizePresets: [ImageSize(width: 1024, height: 1024)],
            sizeBounds: 512...2048,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 1...12,
            defaultSteps: 4,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true
        )
    )

    @Test("moving to another family takes that family's schedule, not the step count in the box")
    func switchToAnotherFamilyResetsTheSchedule() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.size = ImageSize(width: 1344, height: 768)
        store.settings.steps = 9

        store.switchModel(to: Self.otherFamily)
        await store.settle()

        // Nine is inside 1...12, so clamping leaves it alone. It still has to move: nine steps
        // of a nine-step schedule and nine of a four-step distillation are different requests.
        #expect(store.settings.steps == 4)
        #expect(store.settings.prompt == "a lighthouse")
        #expect(
            store.settings.size == ImageSize(width: 1344, height: 768),
            "a size means the same thing to both, so it is the user's and it survives"
        )
    }

    @Test("another variant of the same family keeps the step count the user chose")
    func switchWithinAFamilyKeepsTheSchedule() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.steps = 3

        store.switchModel(to: ModelCatalog.zImageTurbo4bit)
        await store.settle()

        #expect(
            store.settings.steps == 3,
            "the two variants run the same schedule, so three steps is still three steps"
        )
    }

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
}
