import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Combined library survives an offline cold launch")
struct MultiHostDiskTests {
    @Test func ownershipAndForget() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appending(path: "Library"), files = directory.appending(path: "Files")
        let root = LibraryCatalog(libraryRoot: library, filesRoot: files)
        let ids = (0..<2).map { _ in HostID(keys: DeviceIdentity().publicKeys) }
        var entries: [CachedEntry] = []
        for (index, id) in ids.enumerated() {
            let child = root.addHost(id, client: MobilePreview.unpairedClient(), frozen: false)
            await child.stopAndDrain()
            let entry = CachedEntry(LibraryFixtures.cached("same.png").entry, hostID: id)
            child.publish([entry])
            await child.entryStore.save([entry])
            await root.fileStore.store(Data([UInt8(index)]), as: root.mediaKey(entry, fallback: entry.fileName))
            entries.append(entry)
        }
        let reopened = LibraryCatalog(libraryRoot: library, filesRoot: files)
        for id in ids {
            let offline = MobilePreview.unpairedClient()
            let child = reopened.addHost(id, client: offline, frozen: false)
            await child.stopAndDrain()
            await child.loadFromDisk(seeding: offline)
        }
        #expect(Set(reopened.entries.map(\.id)) == Set(entries.map(\.id)))
        #expect(!reopened.isLive)
        #expect(await reopened.picture(named: entries[0].id) == Data([0]))
        #expect(await reopened.picture(named: entries[1].id) == Data([1]))
        #expect(await reopened.picture(named: "same.png") == nil)
        let partitions = reopened.partition([entries[0].id])
        #expect(partitions.count == 1)
        #expect(partitions.first?.0.hostID == ids[0])
        #expect(partitions.first?.1 == ["same.png"])
        #expect(!(await reopened.setTags([entries[0].id], tags: ["offline"])))
        #expect(reopened.entries.allSatisfy { !$0.tags.contains("offline") })
        await reopened.removeHost(ids[0])
        #expect(reopened.entries.map(\.id) == [entries[1].id])
        #expect(await reopened.fileStore.data(for: root.mediaKey(entries[0], fallback: "same.png")) == nil)
        #expect(await reopened.picture(named: entries[1].id) == Data([1]))
        let removed = EntryStore(root: library.appending(path: "Hosts/" + ids[0].rawValue))
        #expect(await removed.load().isEmpty)
        await reopened.removeHost(ids[1])
    }
    @Test func interruptedQuarantine() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyEntries = root.appending(path: "Legacy/Entries")
        let thumbnails = root.appending(path: "Thumbnails")
        try FileManager.default.createDirectory(at: legacyEntries, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try Data([1]).write(to: legacyEntries.appending(path: "kept.json"))
        try Data([2]).write(to: thumbnails.appending(path: "kept.jpg"))
        // This is the durable state after Entries moved and before Thumbnails or the marker.
        try LibraryCacheMigration.quarantine(root)
        try LibraryCacheMigration.quarantine(root)
        #expect(try Data(contentsOf: legacyEntries.appending(path: "kept.json")) == Data([1]))
        #expect(try Data(contentsOf: root.appending(path: "Legacy/Thumbnails/kept.jpg")) == Data([2]))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "host-cache-v2").path))
    }
}
