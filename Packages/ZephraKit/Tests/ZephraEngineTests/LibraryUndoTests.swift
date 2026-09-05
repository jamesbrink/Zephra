import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Undo for the library's edits: what the Edit menu can put back, and what it must not know
/// about.
@MainActor
@Suite("Undo puts a library edit back, and redo re-applies it")
struct LibraryUndoTests {
    @Test("undoing a favourite restores it in memory and then on disk; redo re-applies it")
    func favouriteRoundTrip() async throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(LibraryAnnotationTests.image(seed: 1))
        let index = bed.index()
        let manager = UndoManager()
        index.undoManager = manager
        await index.rescanNow()
        let id = try #require(index.items.first?.id)

        index.setFavourite([id], on: true)
        await index.settle()
        #expect(manager.canUndo)
        #expect(manager.undoActionName == "Favorite")

        manager.undo()
        #expect(index.items.first?.isFavourite == false, "put back at once")
        await index.work?.value
        #expect(bed.library.annotation(at: url).isFavourite == false, "and then on disk")
        #expect(manager.canRedo)
        #expect(manager.redoActionName == "Favorite")

        manager.redo()
        #expect(index.items.first?.isFavourite == true)
        await index.work?.value
        #expect(bed.library.annotation(at: url).isFavourite == true)
        #expect(manager.canUndo)
    }

    @Test("undoing a tag restores the tags the images had, and only on the images it touched")
    func tagUndoTouchesOnlyWhatChanged() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 2, prompt: "first"))
        try bed.library.write(LibraryAnnotationTests.image(seed: 3, prompt: "second"))
        let index = bed.index()
        let manager = UndoManager()
        index.undoManager = manager
        await index.rescanNow()
        let ids = Set(index.items.map(\.id))
        index.addTag("rain", to: ids)
        await index.settle()
        manager.removeAllActions()

        index.setTags(["rain", "harbour"], on: ids)
        index.addTag("rain", to: ids)
        #expect(manager.undoActionName == "Tag")

        manager.undo()
        #expect(index.items.allSatisfy { $0.tags == ["rain"] })
        #expect(!manager.canUndo, "the second add changed nothing and registered nothing")
    }

    @Test("undoing a rename gives the album its old name back")
    func renameUndo() async throws {
        let bed = EngineTestBed()
        let index = bed.index()
        let manager = UndoManager()
        index.undoManager = manager
        await index.rescanNow()
        let album = index.createAlbum(named: "Harbours")
        manager.removeAllActions()

        index.renameAlbum(album, to: "Ports")
        #expect(index.name(of: album.id) == "Ports")
        #expect(manager.undoActionName == "Rename Album")

        manager.undo()
        #expect(index.name(of: album.id) == "Harbours")
        #expect(manager.redoActionName == "Rename Album")
        manager.redo()
        #expect(index.name(of: album.id) == "Ports")
        await index.settle()
        #expect(bed.library.albumManifest().albums.map(\.name) == ["Ports"])
    }

    @Test("undoing a deletion brings the album and its members back in one step")
    func deleteUndoRestoresMembers() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 4))
        let index = bed.index()
        let manager = UndoManager()
        index.undoManager = manager
        await index.rescanNow()
        let id = try #require(index.items.first?.id)
        let album = index.createAlbum(named: "Harbours")
        index.add([id], to: album)
        manager.removeAllActions()

        index.deleteAlbum(album)
        #expect(index.albums.isEmpty)
        #expect(index.items.first?.annotation.albums.isEmpty == true)
        #expect(manager.undoActionName == "Delete Album")

        manager.undo()
        #expect(index.albums.map(\.id) == [album.id])
        #expect(index.items.first?.annotation.albums.map(\.id) == [album.id])
        #expect(!manager.canUndo, "the album and its members were one entry")
        #expect(manager.redoActionName == "Delete Album")

        manager.redo()
        #expect(index.albums.isEmpty)
        #expect(index.items.first?.annotation.albums.isEmpty == true)
    }

    @Test("undoing New Album removes it, and the redo is still called New Album")
    func newAlbumUndo() async throws {
        let bed = EngineTestBed()
        let index = bed.index()
        let manager = UndoManager()
        index.undoManager = manager
        await index.rescanNow()

        let album = index.createAlbum(named: "Harbours")
        #expect(manager.undoActionName == "New Album")
        manager.undo()
        #expect(index.albums.isEmpty)
        #expect(manager.redoActionName == "New Album")
        manager.redo()
        #expect(index.albums.map(\.id) == [album.id])
    }

    @Test("without a manager nothing is recorded")
    func nilManagerRecordsNothing() async throws {
        let bed = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 5))
        let index = bed.index()
        await index.rescanNow()
        let id = try #require(index.items.first?.id)

        index.setFavourite([id], on: true)
        index.createAlbum(named: "Harbours")
        let manager = UndoManager()
        index.undoManager = manager
        #expect(!manager.canUndo)
        #expect(index.items.first?.isFavourite == true, "the edit itself still happened")
    }

    @Test("changing the images folder empties the stack")
    func directoryChangeEmptiesTheStack() async throws {
        let bed = EngineTestBed()
        let other = EngineTestBed()
        try bed.library.write(LibraryAnnotationTests.image(seed: 6))
        let store = bed.store()
        let index = bed.index()
        let manager = UndoManager()
        index.undoManager = manager
        await index.rescanNow()
        let id = try #require(index.items.first?.id)
        index.setFavourite([id], on: true)
        #expect(manager.canUndo)

        _ = try await store.changeImageDirectory(to: other.directory, moving: false, index: index)
        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
    }
}
