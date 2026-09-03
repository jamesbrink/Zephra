import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Albums: a manifest for the names, the pictures for the membership, and what happens when the
/// two disagree.
@MainActor
@Suite("Albums, held by identity rather than by name")
struct AlbumTests {
    @Test("renaming an album rewrites the manifest and not one image")
    func renameTouchesNoImage() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let album = Album(name: "Harbours")
        let url = try library.write(LibraryAnnotationTests.image(seed: 1))
        try library.annotate(
            url,
            with: LibraryAnnotation(
                albums: [LibraryAnnotation.Membership(id: album.id, name: album.name)]))
        try library.writeAlbums([album])
        let before = try Self.modifiedAt(url)

        var renamed = album
        renamed.name = "Ports"
        try library.writeAlbums([renamed])

        #expect(try Self.modifiedAt(url) == before, "the picture was not touched")
        let items = LibraryScan(library: library).rescan()
        #expect(library.albums(reconciledWith: items).map(\.name) == ["Ports"])
        #expect(items.first?.annotation.albums.first?.name == "Harbours", "the copy is behind")
    }

    @Test("the manifest wins when it and a picture disagree about a name")
    func manifestWinsOnName() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let album = Album(name: "Ports")
        let url = try library.write(LibraryAnnotationTests.image(seed: 2))
        try library.annotate(
            url,
            with: LibraryAnnotation(
                albums: [LibraryAnnotation.Membership(id: album.id, name: "Harbours")]))
        try library.writeAlbums([album])

        let items = LibraryScan(library: library).rescan()
        let found = try #require(library.albums(reconciledWith: items).first)
        #expect(found.id == album.id)
        #expect(found.name == "Ports", "the manifest, not the picture")
    }

    @Test("a lost manifest is rebuilt from the pictures that name the album")
    func lostManifestIsRebuilt() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let album = Album(name: "Harbours")
        let url = try library.write(LibraryAnnotationTests.image(seed: 3))
        try library.annotate(
            url,
            with: LibraryAnnotation(
                albums: [LibraryAnnotation.Membership(id: album.id, name: album.name)]))
        try library.writeAlbums([album])

        try FileManager.default.removeItem(at: library.albumManifestURL)
        #expect(library.albumManifest().albums.isEmpty)

        let items = LibraryScan(library: library).rescan()
        let rebuilt = library.albums(reconciledWith: items)
        #expect(rebuilt.map(\.id) == [album.id])
        #expect(rebuilt.map(\.name) == ["Harbours"])
    }

    @Test("an album with nothing in it survives a rescan, because the manifest remembers it")
    func emptyAlbumsSurvive() throws {
        let bed = EngineTestBed()
        let library = bed.library
        try library.write(LibraryAnnotationTests.image(seed: 4))
        let empty = Album(name: "Nothing yet")
        try library.writeAlbums([empty])

        let items = LibraryScan(library: library).rescan()
        #expect(library.albums(reconciledWith: items).map(\.id) == [empty.id])
        #expect(LibraryCounts(items: items, albumIDs: [empty.id]).perAlbum == [empty.id: 0])
    }

    @Test("albums are listed by name, and a manifest from a later build reads as none")
    func orderAndVersions() throws {
        let bed = EngineTestBed()
        let library = bed.library
        try library.writeAlbums([
            Album(name: "Zephyrs"), Album(name: "Anchors"), Album(name: "Moorings"),
        ])
        #expect(library.albumManifest().albums.map(\.name) == ["Zephyrs", "Anchors", "Moorings"])
        #expect(library.albums(reconciledWith: []).map(\.name) == ["Anchors", "Moorings", "Zephyrs"])

        let ahead = #"{"albums":[{"createdAt":"2026-01-01T00:00:00Z","id":"\#(UUID().uuidString)","name":"Later"}],"version":99}"#
        try Data(ahead.utf8).write(to: library.albumManifestURL)
        #expect(library.albumManifest().albums.isEmpty)
    }

    private static func modifiedAt(_ url: URL) throws -> Date {
        try #require(
            try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }
}
