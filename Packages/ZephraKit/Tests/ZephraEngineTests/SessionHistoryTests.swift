import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The filmstrip is this session's work. What was made before this launch belongs to the
/// library, and the store no longer goes looking for it.
@MainActor
@Suite("History is this session's, and the folder is the library's")
struct SessionHistoryTests {
    @Test("a new store does not read the folder it writes to")
    func nothingIsRestored() async throws {
        let bed = EngineTestBed()
        try bed.library.write(Self.image(prompt: "from last time", seed: 1, at: 1_772_000_000))

        let store = bed.store()
        await store.settle()

        #expect(store.history.isEmpty)
        #expect(store.current == nil)
        #expect(store.state == .idle)
    }

    @Test("a saved image tells the index where it landed, and the index reads that one file")
    func savingFeedsTheIndex() async throws {
        let bed = EngineTestBed()
        let index = bed.index()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.onImageSaved = { url in index.insert(fileAt: url) }
        index.start()
        await index.settle()
        let scans = index.scanCount

        await store.bootstrap()
        store.settings.prompt = "a lighthouse at dusk"
        store.settings.steps = 1
        store.generate()
        await store.settle()

        #expect(index.items.map(\.prompt) == ["a lighthouse at dusk"])
        #expect(index.items.first?.seed == store.settings.seed)
        #expect(index.scanCount == scans, "one file read, no folder listed")
        #expect(store.history.count == 1, "and it is still this session's image too")
    }

    @Test("deleting the image on the canvas moves to the next newest and to Recently Deleted")
    func deleteCurrent() async throws {
        let bed = EngineTestBed()
        let store = try await Self.storeWithTwoImages(bed)
        let newest = try #require(store.current)
        let file = try #require(newest.fileURL)
        var deleted: [URL] = []
        store.onImageDeleted = { deleted.append($0) }

        store.delete(newest.id)
        await store.settle()

        #expect(store.history.map(\.settings.prompt) == ["older"])
        #expect(store.current?.settings.prompt == "older")
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        #expect(try bed.writtenFiles().filter { $0.hasSuffix(".png") }.count == 1)
        #expect(deleted == [file], "the app is told which file went")

        // Not the Finder's Trash: the same folder the library pane deletes into, with its
        // thirty days written down beside it.
        let scanned = LibraryScan(library: bed.library).rescan()
        #expect(scanned.filter { $0.collection == .generated }.map(\.prompt) == ["older"])
        let waiting = try #require(scanned.first { $0.collection == .recentlyDeleted })
        let name = waiting.fileName
        #expect(name == file.lastPathComponent)
        #expect(bed.library.recentlyDeletedManifest().deletedAt(name) != nil)
    }

    @Test("deleting something else leaves the canvas alone, and the last delete empties it")
    func deleteOthers() async throws {
        let bed = EngineTestBed()
        let store = try await Self.storeWithTwoImages(bed)
        let oldest = try #require(store.history.last)

        store.delete(oldest.id)
        await store.settle()
        #expect(store.history.map(\.settings.prompt) == ["newer"])
        #expect(store.current?.settings.prompt == "newer", "the canvas did not move")

        store.delete(try #require(store.current).id)
        await store.settle()
        #expect(store.history.isEmpty)
        #expect(store.current == nil)
        #expect(try bed.writtenFiles().filter { $0.hasSuffix(".png") }.isEmpty)
    }

    @Test("forgetting the picture on the canvas, deleted through the library rather than here, moves to the next newest")
    func forgetCurrent() async throws {
        let bed = EngineTestBed()
        let store = try await Self.storeWithTwoImages(bed)
        let newest = try #require(store.current)
        let file = try #require(newest.fileURL)

        store.forget(fileAt: file)

        #expect(store.history.map(\.settings.prompt) == ["older"])
        #expect(store.current?.settings.prompt == "older")
    }

    @Test("forgetting a file that is not on the canvas only drops it from history")
    func forgetOthers() async throws {
        let bed = EngineTestBed()
        let store = try await Self.storeWithTwoImages(bed)
        let oldest = try #require(store.history.last)
        let file = try #require(oldest.fileURL)

        store.forget(fileAt: file)

        #expect(store.history.map(\.settings.prompt) == ["newer"])
        #expect(store.current?.settings.prompt == "newer", "the canvas did not move")
    }

    @Test("forgetting the file behind a picture opened from the library, never in history, clears the canvas")
    func forgetOpenedFromLibrary() async throws {
        let bed = EngineTestBed()
        let file = try bed.library.write(Self.image(prompt: "from the library", seed: 1, at: 1_772_000_000))
        let item = try #require(LibraryScan(library: bed.library).rescan().first { $0.url == file })

        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        await store.open(item)
        #expect(store.current?.settings.prompt == "from the library")
        #expect(store.history.isEmpty, "opening does not add to history")

        store.forget(fileAt: file)

        #expect(store.current == nil)
    }

    /// A store that has generated two images, oldest first, which is the state the deletion
    /// tests used to get by reading the folder.
    private static func storeWithTwoImages(_ bed: EngineTestBed) async throws -> GenerationStore {
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.steps = 1
        for prompt in ["older", "newer"] {
            store.settings.prompt = prompt
            store.generate()
            await store.settle()
        }
        #expect(store.history.map(\.settings.prompt) == ["newer", "older"])
        return store
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
