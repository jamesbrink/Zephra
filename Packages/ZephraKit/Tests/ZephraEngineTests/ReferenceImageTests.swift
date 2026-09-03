import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("Generating from a reference image")
struct ReferenceImageTests {
    private static let picture = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
    private static let editing = ModelCatalog.flux2Klein4bit
    private static let plain = ModelCatalog.zImageTurbo4bit

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

    @Test("selecting an edited image on a model that cannot read a picture adopts everything but the picture")
    func selectingOnAPlainModelDropsThePicture() async throws {
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
        #expect(store.settings.prompt == "an edit made elsewhere")
        #expect(store.settings.referenceImage == nil)
    }
}
