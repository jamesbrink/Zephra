import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Deleting into a folder rather than into the Finder's Trash, and getting it back.
@MainActor
@Suite("Recently deleted, and the thirty days before it is final")
struct RecentlyDeletedTests {
    static let deletedAt = Date(timeIntervalSince1970: 1_772_000_000)

    @Test("a deleted image moves folders, is written down, and comes back where it was")
    func roundTrip() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let url = try library.write(LibraryAnnotationTests.image(seed: 1))

        let deleted = try library.moveToRecentlyDeleted(url, at: Self.deletedAt)

        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(deleted.deletingLastPathComponent().lastPathComponent == "Recently Deleted")
        #expect(library.recentlyDeletedManifest().deletedAt(deleted.lastPathComponent) != nil)
        let scanned = LibraryScan(library: library).rescan()
        #expect(scanned.map(\.collection) == [.recentlyDeleted])

        let restored = try library.restoreFromRecentlyDeleted(deleted)
        #expect(restored == url)
        #expect(library.recentlyDeletedManifest().entries.isEmpty)
        #expect(LibraryScan(library: library).rescan().map(\.collection) == [.generated])
    }

    @Test("a name already taken is stepped around, going in and coming back")
    func collisionsAreSteppedAround() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let first = try library.write(LibraryAnnotationTests.image(seed: 2))
        let deleted = try library.moveToRecentlyDeleted(first, at: Self.deletedAt)

        // The same name written again, then deleted again: two files, two entries.
        let second = try library.write(LibraryAnnotationTests.image(seed: 2))
        #expect(second == first, "the name was free again")
        let alsoDeleted = try library.moveToRecentlyDeleted(second, at: Self.deletedAt)
        #expect(alsoDeleted != deleted)
        #expect(library.recentlyDeletedManifest().entries.count == 2)

        // And restoring both puts the second one beside the first rather than over it.
        let restored = try library.restoreFromRecentlyDeleted(deleted)
        let alsoRestored = try library.restoreFromRecentlyDeleted(alsoDeleted)
        #expect(restored == first)
        #expect(alsoRestored != restored)
        #expect(try bed.writtenFiles().filter { $0.hasSuffix(".png") }.count == 2)
    }

    @Test("only what is past its thirty days is purged")
    func purgeHonoursTheGrace() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let old = try library.moveToRecentlyDeleted(
            try library.write(LibraryAnnotationTests.image(seed: 3)), at: Self.deletedAt)
        let fresh = try library.moveToRecentlyDeleted(
            try library.write(LibraryAnnotationTests.image(seed: 4)),
            at: Self.deletedAt.addingTimeInterval(RecentlyDeletedManifest.grace))

        let cutoff = Self.deletedAt.addingTimeInterval(RecentlyDeletedManifest.grace / 2)
        let purged = try library.purgeRecentlyDeleted(deletedBefore: cutoff)

        #expect(purged.map(\.lastPathComponent) == [old.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: old.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: fresh.path(percentEncoded: false)))
        let manifest = library.recentlyDeletedManifest()
        #expect(manifest.entries.map(\.fileName) == [fresh.lastPathComponent])
    }

    @Test("a picture Zephra did not make is never purged, however long it sits there")
    func foreignFilesAreLeftAlone() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let folder = library.directory(for: .recentlyDeleted)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let foreign = folder.appending(path: "someone-elses.png")
        try MockBackend.pngData.write(to: foreign)

        for _ in 0..<2 {
            #expect(try library.purgeRecentlyDeleted(deletedBefore: .distantFuture).isEmpty)
        }

        #expect(FileManager.default.fileExists(atPath: foreign.path(percentEncoded: false)))
        #expect(library.recentlyDeletedManifest().entries.isEmpty, "and it is not written down")
    }

    @Test("a file nobody wrote down gets its full thirty days from when it was noticed")
    func unrecordedFilesGetTheFullGrace() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let stray = try LibraryScanTests.put(
            LibraryAnnotationTests.image(seed: 5), in: library, .recentlyDeleted)

        let first = try library.purgeRecentlyDeleted(deletedBefore: .distantFuture, now: Self.deletedAt)
        #expect(first.isEmpty, "noticed, not purged")
        #expect(library.recentlyDeletedManifest().deletedAt(stray.lastPathComponent) == Self.deletedAt)

        let later = try library.purgeRecentlyDeleted(
            deletedBefore: Self.deletedAt.addingTimeInterval(RecentlyDeletedManifest.grace + 1))
        #expect(later.map(\.lastPathComponent) == [stray.lastPathComponent])
        #expect(library.recentlyDeletedManifest().entries.isEmpty)
    }
}
