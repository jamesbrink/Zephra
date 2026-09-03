import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Favourites, tags and albums written into the picture itself.
@MainActor
@Suite("What the user said about an image, in the image")
struct LibraryAnnotationTests {
    @Test("an unannotated file says nothing was said")
    func unannotatedReadsAsEmpty() throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(Self.image(seed: 1))
        let annotation = bed.library.annotation(at: url)
        #expect(annotation == .none)
        #expect(annotation.isEmpty)
        #expect(bed.library.annotation(at: bed.directory.appending(path: "missing.png")) == .none)
    }

    @Test("favourite, tags and albums survive the round trip")
    func roundTrip() throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(Self.image(seed: 2))
        let album = LibraryAnnotation.Membership(id: UUID(), name: "Harbours")
        let written = LibraryAnnotation(
            isFavourite: true, tags: ["rain", "night"], albums: [album])

        try bed.library.annotate(url, with: written)

        #expect(bed.library.annotation(at: url) == written)
        // And the provenance beside it is untouched.
        let record = try #require(GenerationRecord.read(from: try Data(contentsOf: url)))
        #expect(record.seed == 2)
    }

    @Test("annotating keeps the creation date, so favouriting does not reorder the library")
    func creationDateSurvives() throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(Self.image(seed: 3))
        let before = try #require(
            try url.resourceValues(forKeys: [.creationDateKey]).creationDate)

        let modified = try bed.library.annotate(url, with: LibraryAnnotation(isFavourite: true))

        let after = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        #expect(after.creationDate == before)
        #expect(after.contentModificationDate == modified, "the date reported is the file's own")
        #expect(try bed.writtenFiles() == [url.lastPathComponent], "no temporary left behind")
    }

    @Test("annotating twice leaves the file the size it was, pixels included")
    func repeatedWritesDoNotGrow() throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(Self.image(seed: 4))
        let original = try Data(contentsOf: url)

        try bed.library.annotate(url, with: LibraryAnnotation(isFavourite: true))
        let once = try Data(contentsOf: url)
        try bed.library.annotate(url, with: LibraryAnnotation(isFavourite: true))
        let twice = try Data(contentsOf: url)
        #expect(twice == once)

        try bed.library.annotate(url, with: LibraryAnnotation(isFavourite: false))
        let cleared = try Data(contentsOf: url)
        #expect(bed.library.annotation(at: url) == .none)
        try bed.library.annotate(url, with: LibraryAnnotation(isFavourite: true))
        #expect(try Data(contentsOf: url) == once, "back to where it was, byte for byte")

        let image = try #require(try PNGTextChunks.spans(in: Array(original)).first { $0.type == "IDAT" })
        let now = try #require(try PNGTextChunks.spans(in: Array(cleared)).first { $0.type == "IDAT" })
        #expect(Array(Array(cleared)[now.start...]) == Array(Array(original)[image.start...]))
    }

    @Test("an annotation from a later build reads as nothing rather than as half of one")
    func futureVersionsAreIgnored() throws {
        let bed = EngineTestBed()
        let url = try bed.library.write(Self.image(seed: 5))
        let ahead = #"{"albums":[],"isFavourite":true,"tags":[],"version":99}"#
        let rewritten = try PNGTextChunks.replacing(
            [(keyword: LibraryAnnotation.keyword, text: ahead)], in: try Data(contentsOf: url))
        try rewritten.write(to: url)

        #expect(bed.library.annotation(at: url) == .none)
    }

    static func image(seed: UInt64, prompt: String = "a harbour in the rain") -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = prompt
        settings.seed = seed
        return GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings,
            modelID: ModelCatalog.default.id,
            createdAt: Date(timeIntervalSince1970: 1_772_000_000),
            duration: .seconds(3)
        )
    }
}
