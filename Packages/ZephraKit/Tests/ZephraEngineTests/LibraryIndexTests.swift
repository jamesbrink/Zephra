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
        let index = bed.index()
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

    @Test("a purge takes what is past its thirty days and leaves the rest")
    func purgingWhatIsExpired() async throws {
        let bed = EngineTestBed()
        let deletedAt = Date(timeIntervalSince1970: 1_772_000_000)
        try bed.library.moveToRecentlyDeleted(
            try bed.library.write(LibraryAnnotationTests.image(seed: 20)), at: deletedAt)
        try bed.library.moveToRecentlyDeleted(
            try bed.library.write(LibraryAnnotationTests.image(seed: 21)),
            at: deletedAt.addingTimeInterval(RecentlyDeletedManifest.grace))
        let index = bed.index()
        index.start()
        await index.settle()
        #expect(index.counts.recentlyDeleted == 2)

        index.purgeExpired(now: deletedAt.addingTimeInterval(RecentlyDeletedManifest.grace + 1))
        await index.settle()

        #expect(index.counts.recentlyDeleted == 1)
        #expect(index.items.map(\.seed) == [21])
    }

    @Test("the preview index invents a library and never looks for one")
    func previewTouchesNoDisk() async {
        let index = LibraryIndex.preview(count: 12)
        #expect(index.items.count == 12)
        #expect(index.sections.count > 1, "spread over several days")
        #expect(index.counts.total == 12)
        #expect(!index.albums.isEmpty)
        #expect(index.allTags == ["night"])

        index.start()
        await index.rescanNow()
        #expect(index.items.count == 12, "nothing was read, so nothing was lost")
        #expect(index.scanCount == 0)
    }
}
