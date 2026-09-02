import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("History that survives a relaunch")
struct HistoryPersistenceTests {
    @Test("a new store fills its filmstrip from the library, newest first")
    func restoresFromDisk() async throws {
        let bed = EngineTestBed()
        try bed.library.write(Self.image(prompt: "a harbour in the rain", seed: 1, at: 1_772_000_000))
        try bed.library.write(Self.image(prompt: "a lighthouse at dusk", seed: 2, at: 1_772_000_060))
        // A PNG somebody else put in the folder carries no record, and is not history.
        try MockBackend.pngData.write(to: bed.directory.appending(path: "someone-elses.png"))

        let store = bed.store()
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["a lighthouse at dusk", "a harbour in the rain"])
        #expect(store.current?.settings.prompt == "a lighthouse at dusk")
        #expect(store.current?.settings.seed == 2)
        #expect(store.current?.fileURL != nil)
        #expect(store.state == .idle, "restoring does not load a model")
    }

    @Test("a restored image is selectable, and keeps the model that is loaded now")
    func restoredImagesAreSelectable() async throws {
        let bed = EngineTestBed()
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = "a harbour in the rain"
        settings.seed = 77
        try bed.library.write(
            GeneratedImage(
                pngData: MockBackend.pngData,
                settings: settings,
                modelID: "some/model-that-is-not-loaded",
                createdAt: Date(timeIntervalSince1970: 1_772_000_000),
                duration: .seconds(4)
            )
        )

        let store = bed.store()
        await store.settle()
        store.settings.prompt = "something else entirely"
        let restored = try #require(store.history.first)
        store.select(restored)

        #expect(store.settings == settings)
        #expect(store.descriptor.id == ModelCatalog.default.id, "select leaves the model alone")
        #expect(store.current?.modelID == "some/model-that-is-not-loaded")
    }

    @Test("what this session generates stays ahead of what was restored")
    func freshImagesComeFirst() async throws {
        let bed = EngineTestBed()
        try bed.library.write(Self.image(prompt: "from last time", seed: 1, at: 1_772_000_000))

        let store = bed.store()
        await store.bootstrap()
        store.settings.prompt = "from this time"
        store.settings.steps = 1
        store.generate()
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["from this time", "from last time"])
        #expect(store.current?.settings.prompt == "from this time")
    }

    @Test("deleting the image on the canvas moves to the next newest and trashes the file")
    func deleteCurrent() async throws {
        let bed = EngineTestBed()
        try bed.library.write(Self.image(prompt: "older", seed: 1, at: 1_772_000_000))
        try bed.library.write(Self.image(prompt: "newer", seed: 2, at: 1_772_000_060))
        let store = bed.store()
        await store.settle()
        let newest = try #require(store.current)
        let file = try #require(newest.fileURL)

        store.delete(newest.id)
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["older"])
        #expect(store.current?.settings.prompt == "older")
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(try bed.writtenFiles().count == 1)
    }

    @Test("deleting something else leaves the canvas alone, and the last delete empties it")
    func deleteOthers() async throws {
        let bed = EngineTestBed()
        try bed.library.write(Self.image(prompt: "older", seed: 1, at: 1_772_000_000))
        try bed.library.write(Self.image(prompt: "newer", seed: 2, at: 1_772_000_060))
        let store = bed.store()
        await store.settle()
        let oldest = try #require(store.history.last)

        store.delete(oldest.id)
        await store.settle()
        #expect(store.history.map(\.settings.prompt) == ["newer"])
        #expect(store.current?.settings.prompt == "newer", "the canvas did not move")

        store.delete(try #require(store.current).id)
        await store.settle()
        #expect(store.history.isEmpty)
        #expect(store.current == nil)
        #expect(try bed.writtenFiles().isEmpty)
    }

    private static func image(prompt: String, seed: UInt64, at time: Int) -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = prompt
        settings.seed = seed
        return GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings,
            modelID: ModelCatalog.default.id,
            createdAt: Date(timeIntervalSince1970: TimeInterval(time)),
            duration: .seconds(3)
        )
    }
}
