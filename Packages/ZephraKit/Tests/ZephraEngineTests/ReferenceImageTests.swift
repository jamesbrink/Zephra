import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("Generating from a reference image")
struct ReferenceImageTests {
    private static let picture = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
    private static let editing = ModelCatalog.flux2Klein4bit

    /// A stand-in for a model with no way to read a picture at all.
    ///
    /// Not a catalog entry any more: every model Zephra ships can now take a reference — klein
    /// by conditioning on it, the other two by starting from a noised copy. So the drop this
    /// suite is about has to be built rather than borrowed, which is the more honest test
    /// anyway: it exercises the capability rather than today's catalog policy.
    private static let plain: ModelDescriptor = {
        let base = ModelCatalog.zImageTurbo4bit
        let capabilities = ModelCapabilities(
            sizeAlignment: base.capabilities.sizeAlignment,
            sizePresets: base.capabilities.sizePresets,
            sizeBounds: base.capabilities.sizeBounds,
            defaultSize: base.capabilities.defaultSize,
            stepBounds: base.capabilities.stepBounds,
            defaultSteps: base.capabilities.defaultSteps,
            guidanceBounds: base.capabilities.guidanceBounds,
            defaultGuidance: base.capabilities.defaultGuidance,
            supportsNegativePrompt: base.capabilities.supportsNegativePrompt,
            supportsSeed: base.capabilities.supportsSeed,
            supportsReferenceImage: false
        )
        return ModelDescriptor(
            id: "text-to-image-only",
            displayName: "Text to image only",
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

    @Test("the reference image reaches the backend with the rest of the settings")
    func referenceReachesTheBackend() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "make it night"
        store.useAsReference(Self.picture)
        store.generate()
        while store.isRunning { await store.settle() }
        #expect(bed.control.settings.lastSettings?.referenceImage == Self.picture)
    }

    @Test("a picture model keeps its size when a picture is handed in")
    func pictureModelKeepsItsSize() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let before = store.settings.size
        store.useAsReference(PNGImageSizeTests.png(width: 1600, height: 1000))
        #expect(store.settings.referenceImage != nil)
        #expect(store.settings.size == before, "a reference is for the picture asked for, not its shape")
    }

    @Test("a model that cannot read a reference never sees one, even when the well was filled first")
    func plainModelNeverSeesOne() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.plain)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.useAsReference(Self.picture)
        #expect(store.settings.referenceImage == nil)
        store.settings.referenceImage = Self.picture
        store.settings.prompt = "a lighthouse"
        store.generate()
        while store.isRunning { await store.settle() }
        #expect(bed.control.settings.lastSettings?.referenceImage == nil)
    }

    @Test("switching to a model that cannot take a reference clears the well, and switching back does not bring it back")
    func switchingClearsTheWell() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.useAsReference(Self.picture)
        #expect(store.settings.referenceImage == Self.picture)
        await store.switchModel(to: Self.plain)
        #expect(store.settings.referenceImage == nil)
        await store.switchModel(to: Self.editing)
        #expect(store.settings.referenceImage == nil)
    }

    @Test("a queued edit keeps the picture it was queued with after the well is cleared")
    func queuedEditKeepsItsPicture() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        bed.control.update { $0.stepDelay = .milliseconds(15) }
        store.settings.prompt = "first"
        store.settings.steps = 4
        store.generate()
        try await bed.waitForStep()
        store.useAsReference(Self.picture)
        store.settings.prompt = "second, edited"
        store.generate()
        store.useAsReference(nil)
        #expect(store.queue.first?.settings.referenceImage == Self.picture)
        while store.isRunning || !store.queue.isEmpty { await store.settle() }
        await store.settle()
        #expect(store.history.first?.settings.referenceImage == Self.picture)
    }

    @Test("selecting an edited image from the filmstrip puts its reference back in the well")
    func selectingRestoresTheReference() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "edit"
        store.useAsReference(Self.picture)
        store.generate()
        while store.isRunning { await store.settle() }
        store.useAsReference(nil)
        let edited = try #require(store.history.first)
        store.select(edited)
        #expect(store.settings.referenceImage == Self.picture)
    }

    @Test("selecting an edited image on a plain model chooses the model that made it, picture and all")
    func selectingOnAPlainModelChoosesTheEditingModel() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.plain)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        var settings = GenerationSettings.defaults(for: Self.editing)
        settings.prompt = "an edit made elsewhere"
        settings.referenceImage = Self.picture
        let edited = GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: Self.editing.id,
            createdAt: Date(), duration: .seconds(1))
        store.select(edited)
        #expect(store.descriptor.id == Self.editing.id, "the edit runs again where it was made")
        #expect(store.modelAwaitsGenerate, "but nothing is loaded until Generate")
        #expect(store.settings.prompt == "an edit made elsewhere")
        #expect(store.settings.referenceImage == Self.picture)
    }

    @Test("selecting an edit from a model this build has dropped keeps the plain model and drops the picture")
    func selectingAnUnknownEditOnAPlainModelDropsThePicture() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.plain)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        var settings = GenerationSettings.defaults(for: Self.editing)
        settings.prompt = "an edit made elsewhere"
        settings.referenceImage = Self.picture
        let edited = GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: "gone/for-good",
            createdAt: Date(), duration: .seconds(1))
        store.select(edited)
        #expect(store.descriptor.id == Self.plain.id)
        #expect(store.settings.prompt == "an edit made elsewhere")
        #expect(store.settings.referenceImage == nil)
    }

    @Test("a picture arriving settles the strength, and taking it out puts the 1 back")
    func referenceSettlesTheStrength() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: ModelCatalog.default)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let bounds = ModelCatalog.default.capabilities.referenceStrengthBounds
        #expect(bounds.lowerBound < bounds.upperBound, "Z-Image starts from a noised copy")
        #expect(store.settings.referenceStrength == 1, "a request with no picture")

        store.useAsReference(Self.picture)
        #expect(
            store.settings.referenceStrength
                == ModelCatalog.default.capabilities.defaultReferenceStrength,
            "a 1 would open a slider past its own maximum")

        store.settings.referenceStrength = 0.45
        store.useAsReference(Self.picture)
        #expect(store.settings.referenceStrength == 0.45, "a strength already in range is kept")

        store.useAsReference(nil)
        #expect(store.settings.referenceStrength == 1)
    }

    @Test("a model that conditions on the picture leaves the strength at its single value")
    func kleinKeepsItsOnlyStrength() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.useAsReference(Self.picture)
        #expect(store.settings.referenceStrength == 1, "klein declares 1...1")
    }
}
