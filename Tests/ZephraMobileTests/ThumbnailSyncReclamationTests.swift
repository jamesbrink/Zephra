import Foundation
import Testing
@testable import ZephraLinkClient
import ZephraTestSupport
@testable import ZephraMobile

@MainActor @Suite("Sync retains offline and rollback thumbnails")
struct ThumbnailSyncReclamationTests {
    @Test("Unchanged complete lists prune orphans while pending deletion remains readable")
    func unchangedAndRollback() async throws {
        let scratch = Scratch("ThumbnailSync")
        defer { withExtendedLifetime(scratch) {} }
        let catalog = LibraryCatalog(libraryRoot: scratch.root, filesRoot: nil)
        defer { catalog.stop() }
        let rows = MobilePreview.library().prefix(3).map { CachedEntry($0) }
        let snapshot = try #require(MobilePreview.snapshot())
        let client = LinkClient.frozen(snapshot: snapshot, library: [rows[0].entry])
        catalog.publish([rows[0]])
        catalog.pendingDeletions[rows[1].fileName] = rows[1]
        for row in rows { await catalog.thumbnailStore.store(Data([1]), for: row, pixels: 256) }
        await catalog.sync(with: client)
        #expect(await catalog.thumbnailStore.data(for: rows[0], pixels: 256) != nil)
        #expect(await catalog.thumbnailStore.data(for: rows[1], pixels: 256) != nil)
        #expect(await catalog.thumbnailStore.data(for: rows[2], pixels: 256) == nil)
        catalog.publish([rows[0], rows[1]])
        catalog.pendingDeletions.removeAll()
        #expect(await catalog.thumbnailStore.data(for: rows[1], pixels: 256) != nil)
    }

    @Test("Partial lists never remove offline entries or their thumbnails")
    func partial() async throws {
        let scratch = Scratch("PartialThumbnailSync")
        defer { withExtendedLifetime(scratch) {} }
        let catalog = LibraryCatalog(libraryRoot: scratch.root, filesRoot: nil)
        defer { catalog.stop() }
        let rows = MobilePreview.library().prefix(2).map { CachedEntry($0) }
        let client = LinkClient.frozen(snapshot: try #require(MobilePreview.snapshot()), library: [rows[0].entry])
        client.libraryIsComplete = false
        catalog.publish(rows)
        await catalog.thumbnailStore.store(Data([1]), for: rows[1], pixels: 256)
        await catalog.sync(with: client)
        #expect(catalog.entries.contains(rows[1]))
        #expect(await catalog.thumbnailStore.data(for: rows[1], pixels: 256) == Data([1]))
    }
}
