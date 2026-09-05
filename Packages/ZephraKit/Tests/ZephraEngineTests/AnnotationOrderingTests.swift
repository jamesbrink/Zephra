import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("Annotation writes land in order on screen")
struct AnnotationOrderingTests {
    static let older = LibraryAnnotation(isFavourite: false, tags: ["old"], albums: [])
    static let newer = LibraryAnnotation(isFavourite: true, tags: ["new"], albums: [])

    /// An index over one real file that already shows `newer`, with `newer` still to be written.
    private func indexWithNewerPending(_ bed: EngineTestBed) async throws -> (LibraryIndex, LibraryItem) {
        try bed.library.write(LibraryAnnotationTests.image(seed: 7))
        let index = bed.index()
        index.start()
        await index.settle()
        let item = try #require(index.items.first).withAnnotation(Self.newer)
        index.items = [item]
        index.pending[item.id] = Self.newer
        return (index, item)
    }

    @Test("a write that lands after a newer change keeps the newer change on screen")
    func olderWriteDoesNotOverwriteNewer() async throws {
        let bed = EngineTestBed()
        let (index, item) = try await indexWithNewerPending(bed)
        let landed = Date(timeIntervalSince1970: 1_800_000_000)

        index.apply(
            LibraryIndex.AnnotationWrite(id: item.id, modifiedAt: landed, size: 4321, reason: nil),
            wrote: Self.older)

        #expect(index.items[0].annotation == Self.newer)
        #expect(index.items[0].contentModifiedAt == landed, "the file's new shape is recorded")
        #expect(index.items[0].fileSize == 4321)
    }

    @Test("a failed write with a newer change waiting neither reverts nor reports")
    func failedOlderWriteIsSilentWhenNewerWaits() async throws {
        let bed = EngineTestBed()
        let (index, item) = try await indexWithNewerPending(bed)

        index.apply(
            LibraryIndex.AnnotationWrite(id: item.id, modifiedAt: nil, size: nil, reason: "boom"),
            wrote: Self.older)

        #expect(index.items[0].annotation == Self.newer)
        #expect(index.lastFailure == nil)
    }

    @Test("toggling a favourite twice before the first write lands ends where the second toggle said, on disk and on screen")
    func twoTogglesEndWhereTheSecondSaid() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 1))
        let index = bed.index()
        index.start()
        await index.settle()
        let item = try #require(index.items.first)
        let gate = BackendGate()
        index.enqueue { await gate.wait() }

        index.setFavourite([item.id], on: true)
        index.setFavourite([item.id], on: false)
        await gate.open()
        await index.settle()

        #expect(index.items.first?.isFavourite == false)
        #expect(!bed.library.annotation(at: url).isFavourite)
        #expect(index.lastFailure == nil)
    }
}
