import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("Changing image folders coordinates readers and writers")
@MainActor
struct ImageDirectoryChangeTests {
    @Test("keeping images switches both roots and subsequent generation writes there")
    func keepAndGenerate() async throws {
        let bed = EngineTestBed()
        let target = bed.directory.appending(path: "new")
        let store = bed.store()
        let index = bed.index()
        let old = try bed.library.write(LibraryAnnotationTests.image(seed: 1))
        await index.rescanNow()
        await store.open(try #require(index.items.first))
        _ = try await store.changeImageDirectory(to: target, moving: false, index: index)
        #expect(store.outputDirectory == target)
        #expect(index.library.root == target)
        #expect(index.items.isEmpty)
        #expect(store.current == nil)
        #expect(FileManager.default.fileExists(atPath: old.path))
        store.onImageSaved = { index.insert(fileAt: $0) }
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "A lighthouse"
        store.generate(count: 3)
        while store.isDraining { await store.settle() }
        await store.settle()
        #expect(store.history.count == 3)
        #expect(store.history.allSatisfy { $0.fileURL?.deletingLastPathComponent().path == target.path })
        #expect(index.items.count == 3)
    }

    @Test("pending annotations and albums settle before migration")
    func drainWritesBeforeMoving() async throws {
        let bed = EngineTestBed()
        let other = EngineTestBed()
        let store = bed.store()
        let index = bed.index()
        try bed.library.write(LibraryAnnotationTests.image(seed: 2))
        await index.rescanNow()
        let id = try #require(index.items.first?.id)
        let album = index.createAlbum(named: "Harbours")
        index.add([id], to: album)
        index.setFavourite([id], on: true)
        _ = try await store.changeImageDirectory(to: other.directory, moving: true, index: index)
        #expect(index.items.first?.isFavourite == true)
        #expect(index.items.first?.annotation.albums.first?.id == album.id)
        #expect(index.albums.first?.name == "Harbours")
        #expect(!FileManager.default.fileExists(atPath: id))
    }

    @Test("failure retains old roots and unsaved pixels survive a successful change")
    func failureAndUnsavedPixels() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        let index = bed.index()
        let image = LibraryAnnotationTests.image(seed: 3)
        store.current = image
        store.history = [image]
        let target = bed.directory.appending(path: "file")
        try FileManager.default.createDirectory(at: bed.directory, withIntermediateDirectories: true)
        try Data().write(to: target)
        await #expect(throws: ImageDirectoryError.self) {
            try await store.changeImageDirectory(to: target, moving: false, index: index)
        }
        #expect(store.outputDirectory == bed.directory)
        #expect(index.library.root == bed.directory)
        #expect(!store.isChangingImageDirectory && !index.isChangingDirectory)
        _ = try await store.changeImageDirectory(
            to: bed.directory.appending(path: "new"), moving: false, index: index)
        #expect(store.current?.id == image.id)
        #expect(store.history.map(\.id) == [image.id])
    }

    @Test("paused indexes reject fresh mutations while existing writes drain")
    func mutationGate() async throws {
        let bed = EngineTestBed()
        let index = bed.index()
        try bed.library.write(LibraryAnnotationTests.image(seed: 4))
        await index.rescanNow()
        let id = try #require(index.items.first?.id)
        await index.pauseForDirectoryChange()
        index.setFavourite([id], on: true)
        index.createAlbum(named: "Ignored")
        index.moveToRecentlyDeleted([id])
        await index.rescanNow()
        #expect(index.items.count == 1)
        #expect(index.items.first?.isFavourite == false)
        #expect(index.albums.isEmpty)
        await index.resumeAfterDirectoryChange()
        #expect(index.items.count == 1)
    }

    @Test("folder operations mutually gate generation and model changes")
    func operationGate() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        store.imageDirectoryProgress = "Moving images"
        store.settings.prompt = "A lighthouse"
        store.generate()
        store.queueVariation(of: LibraryFilteringTests.item(prompt: "A lighthouse", seed: 42))
        #expect(!store.canGenerate && !store.canQueue && !store.canUpscale)
        #expect(!store.canChangeModelDirectory && !store.canChangeImageDirectory)
        #expect(store.queue.isEmpty)
        store.imageDirectoryProgress = nil
        store.modelDirectoryProgress = "Moving models"
        #expect(!store.canChangeImageDirectory)
    }
}
