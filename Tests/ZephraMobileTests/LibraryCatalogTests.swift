import Foundation
import Testing
import ZephraLinkClient
import ZephraTestSupport

@testable import ZephraMobile

/// The catalog over a frozen client: what it takes in, what it writes, and what a star does
/// before the Mac has answered.
@MainActor
@Suite("The phone's library catalog")
struct LibraryCatalogTests {
    @Test("It takes in what the client is holding, newest first")
    func seedsFromTheClient() async throws {
        let bed = try Bed()

        await bed.catalog.sync(with: bed.client)

        #expect(bed.catalog.entries.count == bed.client.library.count)
        #expect(bed.catalog.entries.first!.createdAt >= bed.catalog.entries.last!.createdAt)
        #expect(bed.catalog.isLive, "a frozen client is live as far as the interface can tell")
        #expect(!bed.catalog.isSyncing, "and the sync has finished")
    }

    @Test("What it took in is on disk, and a second catalog reads it with no Mac at all")
    func survivesTheLaunch() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)
        #expect(bed.catalog.cacheBytes > 0)

        let second = LibraryCatalog(libraryRoot: bed.library, filesRoot: bed.files)
        let unpaired = MobilePreview.unpairedClient()
        await second.loadFromDisk(seeding: unpaired)

        #expect(second.entries.map(\.fileName) == bed.catalog.entries.map(\.fileName))
        #expect(!second.isLive, "and it knows it cannot reach anything")
    }

    @Test("The sections are the query's answer, and the query is the only thing that narrows")
    func sectionsFollowTheQuery() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)

        bed.catalog.query.scope = .clips
        let clips = bed.catalog.sections.flatMap(\.entries)

        #expect(!clips.isEmpty)
        #expect(clips.filter { !$0.isVideo }.isEmpty)
        bed.catalog.query.scope = .all
        #expect(bed.catalog.sections.flatMap(\.entries).count == bed.catalog.entries.count)
    }

    /// A frozen client answers every request `.ok`, so this is the happy path: the star fills
    /// in at once and stays filled.
    @Test("Favoriting shows at once and stays when the Mac agrees")
    func favouriteIsOptimistic() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)
        let name = try #require(bed.catalog.entries.first { !$0.isFavourite }?.fileName)

        let took = await bed.catalog.setFavourite([name], on: true)

        #expect(took)
        #expect(bed.catalog.entry(named: name)?.isFavourite == true)
        #expect(
            bed.catalog.entry(named: name)?.version == bed.client.library
                .first { $0.fileName == name }?.version,
            "the Mac decides what a file's fingerprint is, so the guess does not invent one")
    }

    @Test("Tagging shows at once, and the tags it knows grow with it")
    func tagging() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)
        let name = try #require(bed.catalog.entries.first?.fileName)

        #expect(await bed.catalog.setTags([name], tags: ["harbour", "rain"]))

        #expect(bed.catalog.entry(named: name)?.tags == ["harbour", "rain"])
        #expect(bed.catalog.knownTags.contains("rain"))
    }

    @Test("Deleting closes the gap before the Mac has answered")
    func deleting() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)
        let before = bed.catalog.entries.count
        let name = try #require(bed.catalog.entries.first?.fileName)

        #expect(await bed.catalog.delete([name]))

        #expect(bed.catalog.entries.count == before - 1)
        #expect(bed.catalog.entry(named: name) == nil)
    }

    /// Nothing may be sent while the Mac cannot be reached, and nothing may be changed on
    /// screen either: a star that filled in offline would be a lie about the file.
    @Test("Nothing is edited while the Mac cannot be reached")
    func offlineRefuses() async throws {
        let bed = try Bed(connection: .offline)
        await bed.catalog.sync(with: bed.client)
        let name = try #require(bed.catalog.entries.first { !$0.isFavourite }?.fileName)

        #expect(!bed.catalog.isLive)
        #expect(await bed.catalog.setFavourite([name], on: true) == false)
        #expect(bed.catalog.entry(named: name)?.isFavourite == false)
        #expect(await bed.catalog.delete([name]) == false)
        #expect(bed.catalog.entry(named: name) != nil)
    }

    @Test("Clearing the cache empties it, and the next sync fills it again")
    func clearing() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)

        await bed.catalog.clearCache()

        // `clearCache` syncs again before it returns, since the Mac is the truth and this one
        // is reachable; what it must never do is leave the old bytes behind.
        #expect(bed.catalog.entries.count == bed.client.library.count)
    }

    /// The Mac's index is its *pictures*: it resolves a poster's name and nothing else, so a
    /// request naming the MP4 comes back `notFound` and no clip is ever fetched. What arrives
    /// is the video all the same, and it is filed beside its poster under the same stem.
    @Test("A clip is asked for by its poster's name and kept beside it as an MP4")
    func aClipIsFiledBesideItsPoster() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)
        let clip = try #require(bed.catalog.entries.first { $0.isVideo })
        let sidecar = LibraryCatalog.clipName(of: clip.fileName)
        #expect(sidecar.hasSuffix(".mp4"))

        await bed.catalog.fileStore.store(Data("a clip".utf8), as: sidecar)

        let url = try await bed.catalog.file(for: clip)
        #expect(url.lastPathComponent == sidecar)
        #expect(await bed.catalog.hasFile(for: clip))
    }

    /// The canvas and the library read the same store, so a picture crosses what may be a relay
    /// once rather than once per surface.
    @Test("One cache: a file already here answers both the whole-file door and the picture one")
    func oneCacheServesBothSurfaces() async throws {
        let bed = try Bed()
        await bed.catalog.sync(with: bed.client)
        let entry = try #require(bed.catalog.entries.first { !$0.isVideo })
        let bytes = Data("a picture".utf8)

        await bed.catalog.fileStore.store(bytes, as: entry.fileName)

        #expect(await bed.catalog.picture(named: entry.fileName) == bytes)
        let url = try await bed.catalog.file(for: entry)
        #expect(url.lastPathComponent == entry.fileName)
    }

    /// A catalog over a frozen client and a scratch directory, which is every test above.
    struct Bed {
        let scratch: Scratch
        let client: LinkClient
        let catalog: LibraryCatalog

        var library: URL { scratch.url("Library") }
        var files: URL { scratch.url("Files") }

        init(connection: LinkConnectionState = .live(.lan)) throws {
            let scratch = Scratch("LibraryCatalog")
            let snapshot = try #require(MobilePreview.snapshot())
            let client = LinkClient.frozen(
                snapshot: snapshot, library: MobilePreview.library(), connection: connection)
            let catalog = LibraryCatalog(
                libraryRoot: scratch.url("Library"), filesRoot: scratch.url("Files"))
            catalog.attach(client)
            self.scratch = scratch
            self.client = client
            self.catalog = catalog
        }
    }
}
