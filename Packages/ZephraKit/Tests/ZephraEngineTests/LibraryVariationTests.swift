import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Opening a library image on the canvas, and asking for another one like it.
@MainActor
@Suite("Opening a library image, and varying it")
struct LibraryVariationTests {
    @Test("opening shows the image and leaves the prompt being written alone")
    func openDoesNotAdoptSettings() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 11, prompt: "a harbour"))
        let item = try #require(LibraryScan(library: bed.library).rescan().first)
        let store = bed.store()
        store.settings.prompt = "something else entirely"

        await store.open(item)

        #expect(store.current?.settings.prompt == "a harbour")
        #expect(store.current?.fileURL == url)
        #expect(store.settings.prompt == "something else entirely", "select adopts; open does not")
        #expect(store.lastLibraryFailure == nil)
    }

    @Test("opening an image that has gone says so rather than emptying the canvas")
    func openingAMissingFileFails() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 12))
        let item = try #require(LibraryScan(library: bed.library).rescan().first)
        try FileManager.default.removeItem(at: item.url)
        let store = bed.store()

        await store.open(item)

        #expect(store.current == nil)
        #expect(store.lastLibraryFailure?.action == .open)
        #expect(store.lastLibraryFailure?.itemID == item.id)
    }

    @Test("a variation keeps the request and takes a fresh seed")
    func variationAdoptsSettingsWithANewSeed() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let item = LibraryFilteringTests.item(prompt: "a lighthouse at dusk", seed: 4242)

        store.queueVariation(of: item)

        #expect(store.settings.prompt == "a lighthouse at dusk")
        #expect(store.settings.seed != 4242, "a variation is a different image")
        #expect(store.settings.size == item.size)
        #expect(store.state.isBusy, "the model was already loaded, so it started at once")

        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()
        #expect(store.history.map(\.settings.prompt) == ["a lighthouse at dusk"])
        #expect(store.history.first?.settings.seed == store.settings.seed)
    }

    @Test("a variation of another model's image swaps models to make it")
    func variationSwapsModels() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let other = ModelCatalog.zImageTurbo4bit
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.loadedDescriptor?.id == ModelCatalog.default.id)

        store.queueVariation(of: LibraryFilteringTests.item(prompt: "made elsewhere", modelID: other.id))

        #expect(store.descriptor.id == other.id, "the choice lands at once")
        #expect(store.queue.first?.model.id == other.id)
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()

        #expect(store.history.map(\.modelID) == [other.id])
        #expect(store.loadedDescriptor?.id == other.id)
        #expect(bed.control.settings.unloads == 1)
        #expect(store.state == .ready)
    }

    @Test("a variation of an image from a model this build has dropped runs on the current one")
    func unknownModelsFallBack() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        let item = LibraryFilteringTests.item(prompt: "from an old build", modelID: "gone/for-good")
        store.queueVariation(of: item)

        #expect(store.descriptor.id == ModelCatalog.default.id)
        #expect(store.settings.steps == ModelCatalog.default.capabilities.defaultSteps,
                "the current model's own schedule, not the record's")
        while store.isDraining || !store.queue.isEmpty { await store.settle() }
        await store.settle()
        #expect(store.history.map(\.modelID) == [ModelCatalog.default.id])
    }

    @Test("an imported picture has nothing to vary")
    func importedPicturesAreNotVaried() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        let url = try LibraryScanTests.putSource(named: "reference.png", in: bed.library)
        let item = try #require(
            LibraryScan(library: bed.library).rescan().first { $0.url == url.standardizedFileURL })

        store.queueVariation(of: item)

        #expect(store.queue.isEmpty)
    }
}
