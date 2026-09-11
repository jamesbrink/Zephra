import Foundation
import Testing
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// What a phone does to the library folder, and what it gets back out of it.
@MainActor
@Suite("A phone edits and reads the library through the link")
struct CompanionLibraryTests {
    /// A bed with one picture in the library and an index that has read it.
    static func bedWithOnePicture() async throws -> (CompanionTestBed, URL) {
        let bed = CompanionTestBed()
        let url = try bed.engine.library.write(LibraryAnnotationTests.image(seed: 5))
        await bed.index.rescanNow()
        return (bed, url)
    }

    @Test("a favourite set from the phone reaches the file and registers no undo")
    func favouriteWritesTheFileAndLeavesUndoAlone() async throws {
        let (bed, url) = try await Self.bedWithOnePicture()
        let manager = UndoManager()
        bed.index.undoManager = manager
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(try await phone.request(.setFavourite(names: [url.lastPathComponent], on: true)) == .ok)

        await bed.index.settle()
        #expect(bed.engine.library.annotation(at: url).isFavourite)
        #expect(
            !manager.canUndo,
            "Undo is the Edit menu of the person at the Mac; a phone's edit is not on it")
        #expect(bed.index.undoManager === manager, "and the manager is put back")
        await bed.shutdown()
    }

    @Test("tags set from the phone replace what was there")
    func tagsAreReplaced() async throws {
        let (bed, url) = try await Self.bedWithOnePicture()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(
            try await phone.request(
                .setTags(names: [url.lastPathComponent], tags: ["rain", "night"])) == .ok)

        await bed.index.settle()
        #expect(bed.engine.library.annotation(at: url).tags == ["rain", "night"])
        await bed.shutdown()
    }

    @Test("a delete from the phone moves the picture to Recently Deleted")
    func deleteMovesToRecentlyDeleted() async throws {
        let (bed, url) = try await Self.bedWithOnePicture()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(try await phone.request(.delete([url.lastPathComponent])) == .ok)

        await bed.index.settle()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(bed.index.items.map(\.collection) == [.recentlyDeleted])
        await bed.shutdown()
    }

    @Test("a name this Mac has never written is not found")
    func unknownNameIsNotFound() async throws {
        let (bed, _) = try await Self.bedWithOnePicture()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(.setFavourite(names: ["never-written.png"], on: true))

        guard case .error(let error) = reply else {
            Issue.record("expected a refusal, got \(reply)")
            return
        }
        #expect(error.code == .notFound)
        await bed.shutdown()
    }

    @Test("a thumbnail comes back as a blob and the chunks behind it")
    func thumbnailArrivesAsABlob() async throws {
        let (bed, url) = try await Self.bedWithOnePicture()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(
            .fetchThumbnail(name: url.lastPathComponent, pixels: 256))

        guard case .blob(let start) = reply else {
            Issue.record("expected a blob, got \(reply)")
            return
        }
        #expect(start.mime == "image/jpeg")
        #expect(start.byteCount == StubThumbnails.bytes.count)
        #expect(try await phone.blob(start) == StubThumbnails.bytes)
        #expect(bed.thumbnails.requests.map(\.lastPathComponent) == [url.lastPathComponent])
        await bed.shutdown()
    }

    @Test("the file itself comes back whole, in chunks")
    func fileArrivesWhole() async throws {
        let (bed, url) = try await Self.bedWithOnePicture()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        let reply = try await phone.request(.fetchFile(name: url.lastPathComponent))

        guard case .blob(let start) = reply else {
            Issue.record("expected a blob, got \(reply)")
            return
        }
        #expect(start.mime == "image/png")
        #expect(try await phone.blob(start) == (try Data(contentsOf: url)))
        await bed.shutdown()
    }

    @Test("a page of the library is the folder newest first, with its total beside it")
    func libraryPageIsTheFolder() async throws {
        let (bed, url) = try await Self.bedWithOnePicture()
        let phone = try await bed.pairedPhone()
        let snapshot = try await phone.snapshot()

        let reply = try await phone.request(.libraryPage(offset: 0, limit: 20))

        guard case .entries(let page) = reply else {
            Issue.record("expected a page, got \(reply)")
            return
        }
        #expect(page.total == 1)
        #expect(page.entries.map(\.fileName) == [url.lastPathComponent])
        #expect(snapshot.libraryCount == 1, "and the snapshot counted the same folder")
        await bed.shutdown()
    }
}
