import Foundation
import Testing
import ZephraTestSupport
@testable import ZephraMobile

@Suite("Media availability follows whole-file mutations")
struct FileStoreRevisionTests {
    @Test("Store, eviction, host removal and clearing advance cache revisions")
    func mutations() async throws {
        let scratch = Scratch("FileRevisions")
        defer { withExtendedLifetime(scratch) {} }
        let store = FileStore(root: scratch.root, limit: 1)
        let changes = await store.changes()
        var iterator = changes.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        await store.store(Data([1]), as: "a.png")
        let stored = try #require(await iterator.next())
        #expect(stored > initial)
        await store.store(Data([2]), as: "b.png")
        let evicted = try #require(await iterator.next())
        #expect(evicted > stored)
        #expect(await store.url(for: "a.png") == nil)
        await store.remove(prefix: "b")
        let removed = try #require(await iterator.next())
        #expect(removed > evicted)
        await store.clear()
        #expect(try #require(await iterator.next()) > removed)
    }
}
