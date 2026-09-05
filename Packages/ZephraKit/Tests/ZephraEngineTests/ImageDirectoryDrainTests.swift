import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("Image directory changes drain asynchronous work")
@MainActor
struct ImageDirectoryDrainTests {
    @Test("a queued store deletion reaches Recently Deleted before migration")
    func pendingDelete() async throws {
        let bed = EngineTestBed()
        let other = EngineTestBed()
        let store = bed.store()
        let index = bed.index()
        let image = LibraryAnnotationTests.image(seed: 12)
        let url = try bed.library.write(image)
        store.history = [image.withFileURL(url)]
        store.delete(image.id)
        _ = try await store.changeImageDirectory(to: other.directory, moving: true, index: index)
        #expect(index.items.count == 1)
        #expect(index.items.first?.collection == .recentlyDeleted)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("in-flight old-folder opens cannot replace the cleared canvas")
    func pendingOpen() async throws {
        let bed = EngineTestBed()
        let other = EngineTestBed()
        let store = bed.store()
        let index = bed.index()
        try bed.library.write(LibraryAnnotationTests.image(seed: 13))
        await index.rescanNow()
        let item = try #require(index.items.first)
        let opening = Task { await store.open(item) }
        await Task.yield()
        _ = try await store.changeImageDirectory(to: other.directory, moving: false, index: index)
        await opening.value
        #expect(store.current == nil)
        #expect(index.items.isEmpty)
    }

    @Test("a public scan already reading the old folder cannot repopulate the new index")
    func pendingScan() async throws {
        let bed = EngineTestBed()
        let other = EngineTestBed()
        let store = bed.store()
        let index = bed.index()
        for seed in 100..<150 {
            try bed.library.write(LibraryAnnotationTests.image(seed: UInt64(seed)))
        }
        let scanning = Task { await index.rescanNow() }
        await Task.yield()
        _ = try await store.changeImageDirectory(to: other.directory, moving: false, index: index)
        await scanning.value
        #expect(index.library.root == other.directory)
        #expect(index.items.isEmpty)
        #expect(!index.isScanning)
    }

    @Test("generation refuses a directory change and keeps its queued requests")
    func generationGate() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .seconds(60) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "A tree"
        store.generate(count: 2)
        let queued = store.queue
        await #expect(throws: ImageDirectoryError.self) {
            try await store.changeImageDirectory(
                to: bed.directory.appending(path: "new"), moving: false, index: bed.index())
        }
        #expect(store.queue == queued)
        store.cancel()
        await store.settle()
    }
}
