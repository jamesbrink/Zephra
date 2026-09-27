import Foundation
import Testing
import ZephraLinkProtocol
import ZephraTestSupport
@testable import ZephraMobile

@MainActor @Suite("Only thumbnails reachable from the retained library survive")
struct ThumbnailReclamationTests {
    @Test("A new version removes old thumbnails and rejects late obsolete writes")
    func replacedVersion() async {
        let scratch = Scratch("ThumbnailReclamation")
        let store = ThumbnailStore(root: scratch.root)
        let host = HostID(keys: DeviceIdentity().publicKeys)
        let old = CachedEntry(MobilePreview.library()[0], hostID: host)
        var record = old.entry; record.version += "-new"
        let current = CachedEntry(record, hostID: host)
        await store.store(Data([1]), for: old, pixels: 256)
        await store.store(Data([2]), for: current, pixels: 256)
        await store.retain([current])
        #expect(await store.data(for: old, pixels: 256) == nil)
        #expect(await store.data(for: current, pixels: 256) == Data([2]))
        await store.store(Data([3]), for: old, pixels: 256)
        #expect(await store.data(for: old, pixels: 256) == nil)
    }

    @Test("Startup removes historical orphan thumbnails with no remote changes")
    func startup() async {
        let scratch = Scratch("StartupThumbnails")
        let entries = EntryStore(root: scratch.root), thumbnails = ThumbnailStore(root: scratch.root)
        let rows = MobilePreview.library().map { CachedEntry($0) }
        await entries.save([rows[0]])
        await thumbnails.store(Data([1]), for: rows[0], pixels: 256)
        await thumbnails.store(Data([2]), for: rows[1], pixels: 256)
        let catalog = LibraryCatalog(libraryRoot: scratch.root, filesRoot: nil)
        await catalog.loadFromDisk(seeding: MobilePreview.unpairedClient())
        #expect(await thumbnails.data(for: rows[0], pixels: 256) != nil)
        #expect(await thumbnails.data(for: rows[1], pixels: 256) == nil)
        catalog.stop()
    }
}
