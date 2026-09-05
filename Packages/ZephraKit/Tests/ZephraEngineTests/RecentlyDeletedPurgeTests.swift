import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("What the purge may and may not delete")
struct RecentlyDeletedPurgeTests {
    static let longAgo = Date(timeIntervalSince1970: 1_700_000_000)
    static let now = Date(timeIntervalSince1970: 1_772_000_000)

    @Test("a picture Zephra did not make is never purged even under a name the manifest remembers")
    func foreignFileUnderARememberedNameIsKept() throws {
        let bed = EngineTestBed()
        let library = bed.library
        // Something of ours was deleted long ago under this name and later removed by hand...
        let ours = try library.write(LibraryAnnotationTests.image(seed: 1))
        let deleted = try library.moveToRecentlyDeleted(ours, at: Self.longAgo)
        try FileManager.default.removeItem(at: deleted)
        // ...and somebody else's picture now sits under that very name.
        try MockBackend.pngData.write(to: deleted)
        #expect(library.recentlyDeletedManifest().deletedAt(deleted.lastPathComponent) == Self.longAgo)

        let purged = try library.purgeRecentlyDeleted(
            deletedBefore: Self.now.addingTimeInterval(-RecentlyDeletedManifest.grace), now: Self.now)

        #expect(purged.isEmpty)
        #expect(FileManager.default.fileExists(atPath: deleted.path(percentEncoded: false)))
        #expect(library.recentlyDeletedManifest().deletedAt(deleted.lastPathComponent) == nil,
                "the stale entry is dropped rather than left to fire later")
    }

    @Test("deleting immediately forgets the entry, so a later file under that name gets its own thirty days")
    func purgeForgetsTheName() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let first = try library.write(LibraryAnnotationTests.image(seed: 2))
        let deleted = try library.moveToRecentlyDeleted(first, at: Self.longAgo)

        try library.purgeFromRecentlyDeleted(deleted)
        #expect(!FileManager.default.fileExists(atPath: deleted.path(percentEncoded: false)))
        #expect(library.recentlyDeletedManifest().entries.isEmpty)

        // The same name deleted again today keeps its whole grace period.
        let second = try library.write(LibraryAnnotationTests.image(seed: 2))
        let deletedAgain = try library.moveToRecentlyDeleted(second, at: Self.now)
        #expect(deletedAgain == deleted, "the name was free again")
        let purged = try library.purgeRecentlyDeleted(
            deletedBefore: Self.now.addingTimeInterval(-RecentlyDeletedManifest.grace), now: Self.now)
        #expect(purged.isEmpty)
        #expect(FileManager.default.fileExists(atPath: deletedAgain.path(percentEncoded: false)))
    }

    @Test("a purge through the index forgets the name too")
    func indexPurgeForgets() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 3))
        // Today, or the scan's own purge would take it before the test's does.
        try bed.library.moveToRecentlyDeleted(url, at: Date())
        let index = bed.index()
        index.start()
        await index.settle()
        let item = try #require(index.items.first)
        #expect(item.collection == .recentlyDeleted)

        index.purge([item.id])
        await index.settle()

        #expect(index.items.isEmpty)
        #expect(bed.library.recentlyDeletedManifest().entries.isEmpty)
    }
}
