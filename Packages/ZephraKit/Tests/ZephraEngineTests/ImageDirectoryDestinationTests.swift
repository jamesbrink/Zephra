import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("All image outputs follow the selected directory")
@MainActor
struct ImageDirectoryDestinationTests {
    @Test("upscaling writes and indexes the result in the newly chosen folder")
    func upscaleDestination() async throws {
        let bed = EngineTestBed()
        let chosen = EngineTestBed()
        let store = bed.store()
        let index = bed.index()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let parent = try UpscaleTests.parent(in: bed, prompt: "a lighthouse")
        _ = try await store.changeImageDirectory(to: chosen.directory, moving: false, index: index)
        store.onImageSaved = { index.insert(fileAt: $0) }
        store.upscale(.file(parent), factor: 2)
        await store.settle()
        let result = try #require(store.current?.fileURL)
        #expect(result.deletingLastPathComponent().path == chosen.directory.path)
        #expect(index.items.map(\.url) == [result])
        let record = try #require(GenerationRecord.read(from: try Data(contentsOf: result)))
        #expect(record.upscaleFactor == 2)
        #expect(record.upscaledFrom == parent.lastPathComponent)
        #expect(try bed.writtenFiles() == [parent.lastPathComponent])
    }

    @Test("the current folder is a no-op and switching back restores its library")
    func originalFolderAndNoOp() async throws {
        let original = EngineTestBed()
        let chosen = EngineTestBed()
        let store = original.store()
        let index = original.index()
        try original.library.write(LibraryAnnotationTests.image(seed: 82))
        await index.rescanNow()
        await store.open(try #require(index.items.first))
        let imageID = store.current?.id
        let scans = index.scanCount
        let warnings = try await store.changeImageDirectory(
            to: original.directory, moving: true, index: index)
        #expect(warnings.isEmpty)
        #expect(store.current?.id == imageID)
        #expect(index.scanCount == scans)
        _ = try await store.changeImageDirectory(to: chosen.directory, moving: false, index: index)
        #expect(index.items.isEmpty)
        _ = try await store.changeImageDirectory(to: original.directory, moving: false, index: index)
        #expect(index.items.map(\.seed) == [82])
        #expect(store.outputDirectory.path == original.directory.path)
    }

    @Test("default stays in Pictures and a generating preview refuses folder changes")
    func defaultAndPreviewGate() {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Pictures")
        #expect(ImageLibrary.pictures().root == pictures.appending(path: "Zephra", directoryHint: .isDirectory))
        let store = GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .preparing, fraction: 0)))
        #expect(store.running == nil)
        #expect(!store.canChangeImageDirectory)
    }
}
