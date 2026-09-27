import Foundation
import Testing
import ZephraTestSupport
@testable import ZephraMobile

@Suite("Cache clearing respects consumers and rejects old commits")
struct CacheLifetimeTests {
    @Test("Clear preserves leased bytes until the final release")
    func leasedClear() async throws {
        let scratch = Scratch("LeasedClear")
        let store = FileStore(root: scratch.root)
        let key = "a.png"
        let old = await store.ticket(for: key)
        let lease = await store.lease(key)
        let url = try #require(await store.store(Data([1]), as: key, ticket: old))
        await store.clear()
        #expect(try Data(contentsOf: url) == Data([1]))
        #expect(await store.store(Data([2]), as: key, ticket: old) == nil)
        let current = await store.ticket(for: key)
        #expect(await store.store(Data([2]), as: key, ticket: current) == url)
        #expect(try Data(contentsOf: url) == Data([1]))
        await store.release(key)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        withExtendedLifetime(lease) {}
    }

    @Test("Removing one host invalidates its fetches without touching another host")
    func hostRemoval() async throws {
        let scratch = Scratch("HostRemoval")
        let store = FileStore(root: scratch.root)
        let a = await store.ticket(for: "a-file.png"), b = await store.ticket(for: "b-file.png")
        await store.store(Data([1]), as: "a-file.png", ticket: a)
        await store.store(Data([2]), as: "b-file.png", ticket: b)
        await store.remove(prefix: "a-")
        #expect(await store.store(Data([3]), as: "a-file.png", ticket: a) == nil)
        #expect(await store.data(for: "b-file.png") == Data([2]))
        #expect(await store.store(Data([4]), as: "b-new.png") != nil)
    }

    @Test("Metadata and thumbnails cannot commit after a clear")
    func staleMetadata() async throws {
        let scratch = Scratch("StaleMetadata")
        let entries = EntryStore(root: scratch.root), thumbnails = ThumbnailStore(root: scratch.root)
        let entry = CachedEntry(MobilePreview.library()[0])
        let a = await entries.ticket(), b = await thumbnails.ticket()
        await entries.clear(); await thumbnails.clear()
        await entries.save([entry], ticket: a)
        await thumbnails.store(Data([1]), for: entry, pixels: 256, ticket: b)
        #expect(await entries.load().isEmpty)
        #expect(await thumbnails.size() == 0)
    }
}
