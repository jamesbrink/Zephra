import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Making a picture the first frame of a clip: the model is chosen, the size follows the
/// picture, and nothing is loaded until Generate.
@MainActor
@Suite("Animating a picture")
struct AnimateTests {
    @Test("animating chooses the clip model without loading it")
    func choosesWithoutLoading() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let loads = bed.control.settings.loads

        store.animate(with: Self.video, origin: "harbour.png") { Self.landscape }
        while store.isAdoptingReference { await Task.yield() }

        #expect(store.descriptor.id == Self.video.id, "the menu says what Generate will run")
        #expect(store.modelAwaitsGenerate)
        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id, "nothing was swapped")
        #expect(bed.control.settings.loads == loads)
        #expect(store.state == .ready)
    }

    @Test("a landscape picture opens the clip landscape, and a portrait one portrait")
    func theSizeFollowsThePicture() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.animate(with: Self.video, origin: nil) { Self.landscape }
        while store.isAdoptingReference { await Task.yield() }
        #expect(store.settings.size == ImageSize(width: 768, height: 512))

        store.animate(with: Self.video, origin: nil) { Self.portrait }
        while store.isAdoptingReference { await Task.yield() }
        #expect(store.settings.size == ImageSize(width: 512, height: 768))
    }

    @Test("the picture lands in the well at the model's own strength, with where it came from")
    func thePictureLandsInTheWell() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.animate(with: Self.video, origin: "harbour-1234.png") { Self.landscape }
        while store.isAdoptingReference { await Task.yield() }

        #expect(store.settings.referenceImage == Self.landscape)
        #expect(store.settings.referenceOrigin == "harbour-1234.png")
        #expect(store.settings.referenceStrength == 0, "hold the picture exactly")
        #expect(store.settings.frames == Self.video.capabilities.defaultFrames)
    }

    @Test("the prompt being written is kept, because it is what the clip is of")
    func thePromptIsKept() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "the water starts moving"

        store.animate(with: Self.video, origin: nil) { Self.landscape }
        while store.isAdoptingReference { await Task.yield() }

        #expect(store.settings.prompt == "the water starts moving")
        #expect(!store.capsuleHoldsPicture, "the capsule is the user's, not a picture's")
    }

    @Test("Generate is what loads the clip model, and the backend is handed the picture")
    func generateLoadsIt() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "the water starts moving"
        store.animate(with: Self.video, origin: "harbour-1234.png") { Self.landscape }
        while store.isAdoptingReference { await Task.yield() }

        store.generate()
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(!store.modelAwaitsGenerate)
        #expect(store.loadedDescriptor?.id == Self.video.id, "Generate is what loaded it")
        #expect(bed.control.settings.lastSettings?.referenceImage == Self.landscape)
        #expect(bed.control.settings.lastSettings?.referenceOrigin == "harbour-1234.png")
    }

    @Test("animating a picture stops following the run in flight")
    func stopsFollowingTheRun() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .milliseconds(15) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "a lighthouse"
        store.settings.steps = 4
        store.generate()
        try await bed.waitForStep()
        #expect(store.followsRun)

        store.animate(with: Self.video, origin: nil) { Self.landscape }
        #expect(!store.followsRun)
        while store.isRunning { await store.settle() }
    }

    @Test("an animation asked for while the images folder is changing does nothing")
    func aFolderChangeRefusesIt() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let chosen = store.descriptor.id
        store.imageDirectoryProgress = "Moving images"

        #expect(!store.canAnimate)
        store.animate(origin: nil) { Self.landscape }
        while store.isAdoptingReference { await Task.yield() }

        #expect(store.descriptor.id == chosen)
        #expect(store.settings.referenceImage == nil)
    }

    @Test("this build ships a model that animates a picture, and the catalog names which")
    func theCatalogHasOne() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        let animator = try #require(ModelCatalog.animator())
        #expect(animator.capabilities.producesVideo)
        #expect(animator.capabilities.supportsReferenceImage)
        #expect(store.canAnimate)

        store.animate(origin: "harbour.png") { Self.landscape }
        while store.isAdoptingReference { await Task.yield() }
        #expect(store.descriptor.id == animator.id)
        #expect(store.settings.referenceImage == Self.landscape)
    }

    @Test("a build shipping no model that makes clips from a picture animates nothing")
    func aBuildWithoutOne() {
        let pictures = ModelCatalog.all.filter { !$0.capabilities.producesVideo }
        #expect(!pictures.isEmpty, "this build does ship picture models")
        #expect(ModelCatalog.animator(among: pictures) == nil)
        #expect(ModelCatalog.animator(among: []) == nil)
    }

    nonisolated static let landscape: Data = PNGImageSizeTests.png(width: 1600, height: 1000)
    nonisolated static let portrait: Data = PNGImageSizeTests.png(width: 1000, height: 1600)

    /// A clip model built here rather than borrowed from the catalog, so these tests say what
    /// the rule is rather than what today's LTX-2.5 entry happens to declare.
    static let video: ModelDescriptor = {
        let base = ModelCatalog.ltx2Distilled4bit
        let capabilities = ModelCapabilities(
            sizeAlignment: 32,
            sizePresets: [
                ImageSize(width: 768, height: 512),
                ImageSize(width: 512, height: 768),
                ImageSize(width: 512, height: 288),
            ],
            sizeBounds: 256...1024,
            defaultSize: ImageSize(width: 768, height: 512),
            stepBounds: 8...8,
            defaultSteps: 8,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: true,
            referenceStrengthBounds: 0.0...0.9,
            defaultReferenceStrength: 0,
            frameBounds: 9...121,
            defaultFrames: 49,
            frameAlignment: 8,
            frameRate: 24
        )
        return ModelDescriptor(
            id: "clips-from-a-picture",
            displayName: "Clips from a picture",
            variantName: nil,
            backend: base.backend,
            source: base.source,
            quantization: base.quantization,
            downloadBytes: base.downloadBytes,
            residentBytes: base.residentBytes,
            peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: capabilities
        )
    }()
}
