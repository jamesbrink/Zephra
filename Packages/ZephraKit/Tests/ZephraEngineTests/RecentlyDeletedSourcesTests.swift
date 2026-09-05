import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("A deleted source picture")
struct RecentlyDeletedSourcesTests {
    static let deletedAt = Date(timeIntervalSince1970: 1_772_000_000)

    @Test("a deleted source picture is listed in Recently Deleted")
    func deletedSourceIsListed() async throws {
        let bed = EngineTestBed()
        let source = try LibraryScanTests.putSource(named: "reference.png", in: bed.library)
        // Today, or the scan's own purge would take it before the index lists it.
        let deleted = try bed.library.moveToRecentlyDeleted(source, at: Date())
        let index = bed.index()
        index.start()
        await index.settle()

        let item = try #require(index.items.first)
        #expect(item.collection == .recentlyDeleted)
        #expect(item.url == deleted)
        if case .imported = item.provenance {} else {
            Issue.record("a source keeps its import provenance in Recently Deleted")
        }
        #expect(bed.library.recentlyDeletedManifest().origin(deleted.lastPathComponent) == .sources)
    }

    @Test("put back returns a source picture to Sources, and a generated one to the root")
    func restoreReturnsToOrigin() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let source = try LibraryScanTests.putSource(named: "reference.png", in: library)
        let generated = try library.write(LibraryAnnotationTests.image(seed: 1))
        let deletedSource = try library.moveToRecentlyDeleted(source, at: Self.deletedAt)
        let deletedGenerated = try library.moveToRecentlyDeleted(generated, at: Self.deletedAt)
        // Sources is gone entirely in between; Put Back recreates it.
        try FileManager.default.removeItem(at: library.directory(for: .sources))

        #expect(try library.restoreFromRecentlyDeleted(deletedSource) == source)
        #expect(try library.restoreFromRecentlyDeleted(deletedGenerated) == generated)
        let scanned = LibraryScan(library: library).rescan()
        #expect(Set(scanned.map(\.collection)) == [.generated, .sources])
        #expect(library.recentlyDeletedManifest().entries.isEmpty)
    }

    @Test("a manifest written before origins existed still restores by the file's own header")
    func manifestWithoutOriginsRestoresByHeader() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let source = try LibraryScanTests.putSource(named: "reference.png", in: library)
        let generated = try library.write(LibraryAnnotationTests.image(seed: 2))
        let deletedSource = try library.moveToRecentlyDeleted(source, at: Self.deletedAt)
        let deletedGenerated = try library.moveToRecentlyDeleted(generated, at: Self.deletedAt)
        // Rewrite the manifest the way a v1 build did: dates only.
        var manifest = library.recentlyDeletedManifest()
        manifest.entries = manifest.entries.map { Entry(fileName: $0.fileName, deletedAt: $0.deletedAt) }
        try library.write(manifest)
        #expect(library.recentlyDeletedManifest().origin(deletedSource.lastPathComponent) == nil)

        #expect(try library.restoreFromRecentlyDeleted(deletedGenerated) == generated)
        #expect(try library.restoreFromRecentlyDeleted(deletedSource) == source)
    }

    private typealias Entry = RecentlyDeletedManifest.Entry
}
