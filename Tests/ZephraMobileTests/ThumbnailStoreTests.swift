import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraMobile

/// The thumbnails the Mac sent, and the rule that keeps a changed picture from showing
/// yesterday's pixels under today's name.
@Suite("The phone's thumbnail cache")
struct ThumbnailStoreTests {
    @Test("A thumbnail kept is the same bytes back")
    func roundTrip() async {
        let scratch = Scratch("ThumbnailStore")
        let store = ThumbnailStore(root: scratch.root)
        let entry = LibraryFixtures.cached("a.png")

        await store.store(Data("jpeg".utf8), for: entry, pixels: ThumbnailStore.cellPixels)

        #expect(await store.data(for: entry, pixels: ThumbnailStore.cellPixels) == Data("jpeg".utf8))
    }

    @Test("The two sizes are two files")
    func sizesAreSeparate() async {
        let scratch = Scratch("ThumbnailStore")
        let store = ThumbnailStore(root: scratch.root)
        let entry = LibraryFixtures.cached("a.png")

        await store.store(Data("cell".utf8), for: entry, pixels: ThumbnailStore.cellPixels)

        #expect(await store.data(for: entry, pixels: ThumbnailStore.viewerPixels) == nil)
    }

    /// The whole point of the digest: a picture whose file moved misses rather than answering
    /// with what it looked like before.
    @Test("A picture that changed on the Mac misses")
    func changedPictureMisses() async {
        let scratch = Scratch("ThumbnailStore")
        let store = ThumbnailStore(root: scratch.root)
        let before = LibraryFixtures.cached("a.png")
        let after = LibraryFixtures.cached(
            "a.png", modifiedAt: Date(timeIntervalSince1970: 1_772_009_999))

        await store.store(Data("old".utf8), for: before, pixels: 256)

        #expect(await store.data(for: after, pixels: 256) == nil)
        #expect(await store.data(for: before, pixels: 256) == Data("old".utf8))
    }

    @Test("The digest is the name, the time and the pixels, and nothing else")
    func digestRule() {
        let when = Date(timeIntervalSince1970: 1_772_000_000)
        let base = ThumbnailStore.digest(fileName: "a.png", contentModifiedAt: when, pixels: 256)

        #expect(base.count == 32, "sixteen bytes as hex")
        #expect(base == ThumbnailStore.digest(fileName: "a.png", contentModifiedAt: when, pixels: 256))
        #expect(base != ThumbnailStore.digest(fileName: "b.png", contentModifiedAt: when, pixels: 256))
        #expect(base != ThumbnailStore.digest(fileName: "a.png", contentModifiedAt: when, pixels: 512))
        #expect(
            base != ThumbnailStore.digest(
                fileName: "a.png", contentModifiedAt: when.addingTimeInterval(1), pixels: 256))
    }

    @Test("Two characters of shard, so one folder never holds them all")
    func shards() async {
        let scratch = Scratch("ThumbnailStore")
        let store = ThumbnailStore(root: scratch.root)

        for index in 0..<8 {
            await store.store(Data("x".utf8), for: LibraryFixtures.cached("\(index).png"), pixels: 256)
        }

        let shards = try? FileManager.default.contentsOfDirectory(
            atPath: scratch.root.appending(path: "Thumbnails").path(percentEncoded: false))
        #expect(shards?.allSatisfy { $0.count == 2 } == true)
        #expect(await store.size() == 8)
    }

    @Test("A store with nowhere to write keeps nothing")
    func frozen() async {
        let store = ThumbnailStore(root: nil)
        let entry = LibraryFixtures.cached("a.png")

        await store.store(Data("jpeg".utf8), for: entry, pixels: 256)

        #expect(await store.data(for: entry, pixels: 256) == nil)
        #expect(await store.size() == 0)
    }
}
