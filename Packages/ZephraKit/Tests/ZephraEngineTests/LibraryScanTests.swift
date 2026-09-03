import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Walking the library's folders: what is found, what is skipped, and what is not read twice.
@MainActor
@Suite("Scanning the library's folders")
struct LibraryScanTests {
    @Test("the folders decide the collection, and a foreign PNG is not part of the library")
    func rootsAndForeignFiles() throws {
        let bed = EngineTestBed()
        let library = bed.library
        try library.write(LibraryAnnotationTests.image(seed: 1, prompt: "a harbour"))
        try Self.put(LibraryAnnotationTests.image(seed: 2), in: library, .recentlyDeleted)
        try Self.putSource(named: "reference.png", in: library)
        try MockBackend.pngData.write(to: bed.directory.appending(path: "someone-elses.png"))

        let items = LibraryScan(library: library).rescan()

        #expect(items.count == 3)
        #expect(items.filter { $0.collection == .generated }.map(\.prompt) == ["a harbour"])
        #expect(items.filter { $0.collection == .recentlyDeleted }.count == 1)
        let source = try #require(items.first { $0.collection == .sources })
        #expect(source.provenance.source?.originalFileName == "reference.png")
        #expect(source.prompt == "")
    }

    @Test("a file whose date and size have not moved is taken from what is already known")
    func unchangedFilesAreNotReread() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let url = try library.write(LibraryAnnotationTests.image(seed: 3))
        let scan = LibraryScan(library: library)

        let first = scan.rescan()
        let item = try #require(first.first)
        // A marker no re-read could reproduce: it is not on disk.
        let marked = item.withAnnotation(LibraryAnnotation(tags: ["remembered"]))
        let second = scan.rescan(known: [marked.id: marked])
        #expect(second.first?.tags == ["remembered"])

        try library.annotate(url, with: LibraryAnnotation(isFavourite: true))
        let third = scan.rescan(known: [marked.id: marked])
        #expect(third.first?.tags == [], "a changed file is read again")
        #expect(third.first?.isFavourite == true)
    }

    @Test("the fingerprint moves when a file does, and holds still when nothing does")
    func fingerprintTracksTheFolders() throws {
        let bed = EngineTestBed()
        let library = bed.library
        let url = try library.write(LibraryAnnotationTests.image(seed: 4))
        let scan = LibraryScan(library: library)
        let first = scan.fingerprint()

        #expect(scan.fingerprint() == first, "nothing changed")

        try library.annotate(url, with: LibraryAnnotation(isFavourite: true))
        let annotated = scan.fingerprint()
        #expect(annotated != first)

        try Self.put(LibraryAnnotationTests.image(seed: 5), in: library, .recentlyDeleted)
        #expect(scan.fingerprint() != annotated, "another folder counts too")
    }

    @Test("an item knows its day, its size on disk, and everything worth searching")
    func itemFacts() throws {
        let bed = EngineTestBed()
        let library = bed.library
        try library.write(LibraryAnnotationTests.image(seed: 0xABCD_1234_5678_9ABC, prompt: "a café"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))

        let item = try #require(LibraryScan(library: library, calendar: calendar).rescan().first)

        #expect(item.id == item.url.path(percentEncoded: false))
        #expect(item.fileSize > 0)
        #expect(item.day == calendar.startOfDay(for: item.createdAt))
        #expect(item.searchKey.contains("cafe"), "diacritics folded")
        #expect(item.searchKey.contains(String(0xABCD_1234_5678_9ABC as UInt64)))
        #expect(item.searchKey.contains("abcd·1234"), "the label the inspector shows, folded")
        #expect(item.size == ModelCatalog.default.capabilities.defaultSize)
    }

    /// Writes an image into one of the library's other folders, as the trash and the importer
    /// will once they exist.
    @discardableResult
    static func put(
        _ image: GeneratedImage, in library: ImageLibrary, _ collection: LibraryCollection
    ) throws -> URL {
        let directory = library.directory(for: collection)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "zephra-\(image.settings.seed).png")
        try GenerationRecord.embedded(in: image).write(to: url)
        return url
    }

    /// Writes an imported picture into the sources folder.
    @discardableResult
    static func putSource(named name: String, in library: ImageLibrary) throws -> URL {
        let record = SourceRecord(
            importedAt: Date(timeIntervalSince1970: 1_772_100_000),
            originalFileName: name,
            width: 1024,
            height: 1024,
            digest: "abc123"
        )
        let directory = library.directory(for: .sources)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try PNGTextChunks.inserting([try record.entry()], into: MockBackend.pngData).write(to: url)
        return url
    }
}
