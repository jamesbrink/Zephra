import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("Deleting an image whose save has not landed")
struct DeleteBeforeSaveTests {
    @Test("an image deleted before its save lands goes to Recently Deleted, not the library")
    func deletedImageIsMovedOnWhenItLands() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        // Hold the save chain shut, so the image is in history with no file yet.
        let gate = BackendGate()
        store.saveTask = Task.detached { await gate.wait() }
        var saved: URL?
        var deleted: URL?
        store.onImageSaved = { saved = $0 }
        store.onImageDeleted = { deleted = $0 }
        store.settings.prompt = "x"
        store.generate()
        await store.generationTask?.value
        let image = try #require(store.history.first)
        #expect(image.fileURL == nil)

        store.delete(image.id)
        #expect(store.history.isEmpty)
        #expect(store.deletedBeforeSave.contains(image.id))

        await gate.open()
        await store.settle()

        #expect(saved == nil, "the index must never learn of the file as a save")
        #expect(deleted != nil, "it learns of it as a delete")
        #expect(store.deletedBeforeSave.isEmpty)
        #expect(try bed.writtenFiles() == [ImageLibrary.recentlyDeletedFolderName])
        let bin = bed.library.directory(for: .recentlyDeleted)
        let pngs = try FileManager.default.contentsOfDirectory(atPath: bin.path(percentEncoded: false))
            .filter { $0.hasSuffix(".png") }
        #expect(pngs.count == 1)
        await store.shutdown()
    }

    @Test("a save that fails for a deleted image forgets the deletion")
    func failedSaveForgetsTheDeletion() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = try bed.storeThatCannotSave()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let gate = BackendGate()
        store.saveTask = Task.detached { await gate.wait() }
        store.settings.prompt = "x"
        store.generate()
        await store.generationTask?.value
        let image = try #require(store.history.first)

        store.delete(image.id)
        #expect(store.deletedBeforeSave.contains(image.id))
        await gate.open()
        await store.settle()

        #expect(store.deletedBeforeSave.isEmpty)
        #expect(store.lastSaveFailure?.imageID == image.id)
        await store.shutdown()
    }
}
