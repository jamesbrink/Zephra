import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The index: what it reads, what it does not read twice, and what it does when a write fails.
@MainActor
@Suite("The library index over a folder of images")
struct LibraryIndexTests {
    @Test("a saved image joins the index without a scan, in date order")
    func insertWithoutRescanning() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 1, prompt: "older"))
        let index = bed.index()
        index.start()
        await index.settle()
        let scans = index.scanCount

        var newer = LibraryAnnotationTests.image(seed: 2, prompt: "newer")
        newer = GeneratedImage(
            pngData: newer.pngData, settings: newer.settings, modelID: newer.modelID,
            createdAt: newer.createdAt.addingTimeInterval(60), duration: newer.duration)
        let url = try bed.library.write(newer)
        index.insert(fileAt: url)

        #expect(index.items.map(\.prompt) == ["newer", "older"])
        #expect(index.sections.first?.items.count == 2, "the same day")
        #expect(index.counts.total == 2)
        #expect(index.scanCount == scans, "no folder was listed")
    }

    @Test("an image can be found by the file name a record names it with, trash aside")
    func lookupByFileName() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 7, prompt: "harbour"))
        let index = bed.index()
        index.start()
        await index.settle()

        let found = try #require(index.item(named: url.lastPathComponent))
        #expect(found.prompt == "harbour")
        #expect(index.item(named: "never-written.png") == nil)

        index.moveToRecentlyDeleted([found.id])
        await index.settle()
        #expect(
            index.item(named: url.lastPathComponent) == nil,
            "a picture in the trash is not the source of a live one")
    }

    @Test("a name shared by a generated picture and an imported source finds the generated one")
    func nameCollisionPrefersTheGeneratedPicture() async throws {
        let bed = EngineTestBed()
        let generated = try bed.library.write(LibraryAnnotationTests.image(seed: 12, prompt: "made here"))
        try LibraryScanTests.putSource(named: generated.lastPathComponent, in: bed.library)
        let index = bed.index()
        index.start()
        await index.settle()

        let found = try #require(index.item(named: generated.lastPathComponent))
        #expect(found.collection == .generated)
        #expect(found.url.standardizedFileURL == generated.standardizedFileURL)
    }

    @Test("a file deleted behind the app's back leaves the index on the next scan")
    func removedFilesLeave() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 3))
        let index = bed.index()
        index.start()
        await index.settle()
        #expect(index.items.count == 1)

        try FileManager.default.removeItem(at: url)
        await index.rescanNow()

        #expect(index.items.isEmpty)
        #expect(index.sections.isEmpty)
        #expect(index.counts.total == 0)
    }

    @Test("a fingerprint that has not moved costs nothing")
    func unchangedFingerprintShortCircuits() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 4))
        // The watch is held off for the whole test: it would notice the second write on its
        // own and scan beside the one asked for here, which is a scan more than the count expects.
        let index = bed.index(settleFor: .seconds(30))
        index.start()
        await index.settle()
        let scans = index.scanCount

        await index.rescanIfChanged()
        #expect(index.scanCount == scans, "nothing moved, nothing read")

        try bed.library.write(LibraryAnnotationTests.image(seed: 5))
        await index.rescanIfChanged()
        #expect(index.scanCount == scans + 1)
        #expect(index.items.count == 2)
    }

    @Test("a favourite reaches the file, and one that cannot be written is put back")
    func annotationsAreOptimisticAndReversible() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 6))
        let index = bed.index()
        index.start()
        await index.settle()
        let id = try #require(index.items.first?.id)

        index.toggleFavourite([id])
        #expect(index.items.first?.isFavourite == true, "the grid does not wait for the disk")
        await index.settle()
        #expect(bed.library.annotation(at: url).isFavourite == true)
        #expect(index.lastFailure == nil)
        #expect(index.counts.favourites == 1)

        // A folder nothing can be written into: the temporary file the write goes through
        // cannot be made, so the write fails and the change comes back off.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: bed.directory.path(percentEncoded: false))
        index.addTag("rain", to: [id])
        #expect(index.items.first?.tags == ["rain"])
        await index.settle()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: bed.directory.path(percentEncoded: false))

        #expect(index.items.first?.tags == [], "put back from what the file says")
        #expect(index.items.first?.isFavourite == true, "and the favourite that did land stays")
        #expect(index.lastFailure?.action == .annotate)
        #expect(index.lastFailure?.itemID == id)
        #expect(index.allTags.isEmpty)
    }

    @Test("deleting moves the image to the other folder, and restoring brings it back")
    func deleteAndRestore() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 7))
        let index = bed.index()
        index.start()
        await index.settle()
        let id = try #require(index.items.first?.id)

        index.moveToRecentlyDeleted([id])
        #expect(index.items.isEmpty, "gone from the grid at once")
        await index.settle()
        #expect(index.items.map(\.collection) == [.recentlyDeleted])
        #expect(index.counts.recentlyDeleted == 1)
        #expect(index.counts.total == 0)

        index.query.scope = .recentlyDeleted
        #expect(index.sections.first?.items.count == 1)

        index.restore([try #require(index.items.first?.id)])
        await index.settle()
        #expect(index.items.map(\.collection) == [.generated])
        #expect(index.counts.recentlyDeleted == 0)
    }

    @Test("an album is made, filled, and emptied when it goes")
    func albums() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 8))
        let index = bed.index()
        index.start()
        await index.settle()
        let id = try #require(index.items.first?.id)

        let album = index.createAlbum(named: "Harbours ")
        index.add([id], to: album)
        await index.settle()
        #expect(album.name == "Harbours", "trimmed")
        #expect(index.counts.perAlbum[album.id] == 1)
        #expect(bed.library.albumManifest().albums.map(\.id) == [album.id])

        index.renameAlbum(album, to: "Ports")
        await index.settle()
        #expect(index.name(of: album.id) == "Ports")
        #expect(index.items.first?.annotation.albums.first?.name == "Harbours", "no image rewritten")

        index.deleteAlbum(album)
        await index.settle()
        #expect(index.albums.isEmpty)
        #expect(index.items.first?.annotation.albums.isEmpty == true)
        #expect(bed.library.albums(reconciledWith: index.items).isEmpty, "and it stays gone")
    }

    @Test("a rescan queued behind an album rename does not put the old name back")
    func aRescanDoesNotUndoARename() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 8))
        let index = bed.index()
        index.start()
        await index.settle()
        let album = index.createAlbum(named: "Harbours")
        await index.settle()

        // The scan is queued first, so it runs ahead of the rename's own write and reads a
        // manifest that still says Harbours, which is what the folder watch does after the
        // write that created the album.
        index.enqueue { await index.rescanNow() }
        index.renameAlbum(album, to: "Ports")
        await index.settle()

        #expect(index.name(of: album.id) == "Ports")
        #expect(bed.library.albumManifest().albums.first?.name == "Ports", "and the disk agrees")
    }

    @Test("a file written by something else shows up on its own, without a rescan being asked for")
    func theFolderWatchNoticesAWrite() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 9))
        let index = bed.index(settleFor: .milliseconds(20))
        index.start()
        await index.settle()
        #expect(index.items.count == 1)

        try bed.library.write(LibraryAnnotationTests.image(seed: 10, prompt: "from the Finder"))

        for _ in 0..<250 where index.items.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(index.items.count == 2)
        #expect(index.items.map(\.prompt).contains("from the Finder"))
    }

    @Test("starting the index purges what is past its thirty days, and leaves the rest")
    func purgingWhatIsExpired() async throws {
        let bed = EngineTestBed()
        let now = Date()
        try bed.library.moveToRecentlyDeleted(
            try bed.library.write(LibraryAnnotationTests.image(seed: 20)),
            at: now.addingTimeInterval(-RecentlyDeletedManifest.grace - 60))
        try bed.library.moveToRecentlyDeleted(
            try bed.library.write(LibraryAnnotationTests.image(seed: 21)), at: now)

        let index = bed.index()
        index.start()
        await index.settle()

        #expect(index.items.map(\.seed) == [21], "the older one's thirty days were up")
        #expect(index.counts.recentlyDeleted == 1)

        index.purgeExpired(now: now.addingTimeInterval(RecentlyDeletedManifest.grace + 60))
        await index.settle()
        #expect(index.items.isEmpty)
        #expect(index.counts.recentlyDeleted == 0)
    }

    @Test("the folder can be renamed away and back, and writes are still noticed")
    func theWatchSurvivesARename() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 30))
        let index = bed.index(settleFor: .milliseconds(20))
        index.start()
        await index.settle()
        #expect(index.items.count == 1)

        let away = bed.directory.deletingLastPathComponent()
            .appending(path: bed.directory.lastPathComponent + "-away", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: bed.directory, to: away)
        try await Task.sleep(for: .milliseconds(30))
        try FileManager.default.moveItem(at: away, to: bed.directory)

        try bed.library.write(LibraryAnnotationTests.image(seed: 31, prompt: "after the rename"))

        for _ in 0..<500 where index.items.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(index.items.map(\.prompt).contains("after the rename"))
    }

    @Test("an annotation this app wrote is not read back on the next scan")
    func annotatedFilesAreNotReread() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 32))
        let index = bed.index()
        index.start()
        await index.settle()
        let id = try #require(index.items.first?.id)

        index.toggleFavourite([id])
        await index.settle()

        let item = try #require(index.items.first)
        let onDisk = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        #expect(item.contentModifiedAt == onDisk.contentModificationDate)
        #expect(item.fileSize == onDisk.fileSize.map(Int64.init))
        // A marker that is only in memory: if the scan reuses what it knows, it survives.
        let marked = item.withAnnotation(
            LibraryAnnotation(isFavourite: true, tags: ["not on disk"]))
        let rescanned = LibraryScan(library: bed.library).rescan(known: [marked.id: marked])
        #expect(rescanned.first?.tags == ["not on disk"], "no header was read")
    }

    @Test("the preview index invents a library and never looks for one")
    func previewTouchesNoDisk() async {
        let index = LibraryIndex.preview(count: 12)
        #expect(index.counts.total == 12, "the count asked for is the generated count")
        #expect(index.counts.recentlyDeleted == 3, "and a handful are in the trash")
        #expect(index.items.count == 15, "which is every item it holds")
        #expect(index.sections.count > 1, "spread over several days")
        #expect(!index.albums.isEmpty)
        #expect(index.allTags.count > 1, "several tags, so a sidebar has chips to show")

        index.start()
        await index.rescanNow()
        #expect(index.items.count == 15, "nothing was read, so nothing was lost")
        #expect(index.scanCount == 0)
    }

    @Test("the preview index points at the pictures it is given")
    func previewTakesPictures() {
        let pictures = (0..<4).map { URL(filePath: "/tmp/zephra-preview-\($0).png") }
        let index = LibraryIndex.preview(count: 4, pictures: pictures)
        #expect(index.items.prefix(4).map(\.url) == pictures)
        #expect(
            index.items.dropFirst(4).allSatisfy {
                $0.url.path(percentEncoded: false).contains("Zephra Previews")
            },
            "and invents the rest rather than running out"
        )
    }
}
