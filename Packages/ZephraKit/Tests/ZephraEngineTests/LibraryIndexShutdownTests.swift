import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("Quitting waits for the library")
struct LibraryIndexShutdownTests {
    @Test("shutdown returns only once a queued annotation write has reached the disk")
    func shutdownDrainsTheWriteChain() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 1))
        let index = bed.index()
        index.start()
        await index.settle()
        let item = try #require(index.items.first)
        // Hold the chain shut, so the favourite queues behind something that has not landed.
        let gate = BackendGate()
        index.enqueue { await gate.wait() }
        index.setFavourite([item.id], on: true)
        #expect(index.items.first?.isFavourite == true, "optimistic on screen")

        var done = false
        let quitting = Task { await index.shutdown(); done = true }
        try await Task.sleep(for: .milliseconds(20))
        #expect(!done, "shutdown waits for the chain")
        #expect(!bed.library.annotation(at: url).isFavourite, "nothing has reached the disk yet")

        await gate.open()
        await quitting.value
        #expect(bed.library.annotation(at: url).isFavourite, "the write landed before Quit went on")
    }

    @Test("nothing rescans or inserts after shutdown")
    func nothingMovesAfterShutdown() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 2))
        let index = bed.index()
        index.start()
        await index.settle()
        #expect(index.items.count == 1)
        await index.shutdown()
        let scans = index.scanCount

        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 3))
        index.insert(fileAt: url)
        await index.rescanNow()
        try await Task.sleep(for: .milliseconds(60))

        #expect(index.items.count == 1)
        #expect(index.scanCount == scans)
        #expect(index.watches.isEmpty)
    }
}
