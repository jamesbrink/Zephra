import Foundation
import Testing

@testable import ZephraEngine

/// Reading a PNG's text from its first few kilobytes, and rewriting that text in place.
@MainActor
@Suite("PNG text read from the header, and replaced without growing")
struct PNGHeaderReadingTests {
    /// The files a library scan has to cope with: bare pixels, one keyword, several, and text
    /// that needs an iTXt.
    static let fixtures: [(name: String, entries: [PNGTextChunks.Entry])] = [
        ("bare", []),
        ("one", [(keyword: "Software", text: "Zephra 0.1.0")]),
        (
            "several",
            [
                (keyword: "Software", text: "Zephra 0.1.0"),
                (keyword: "Description", text: "a lighthouse at dusk"),
                (keyword: "zephra:generation", text: #"{"seed":42,"version":1}"#),
            ]
        ),
        ("unicode", [(keyword: "Description", text: "fog rolling in — 🌊")]),
    ]

    @Test("the header read says what a whole-file read says, for every fixture")
    func headerMatchesFullRead() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for fixture in Self.fixtures {
            let data = try PNGTextChunks.inserting(fixture.entries, into: MockBackend.pngData)
            let url = folder.appending(path: "\(fixture.name).png")
            try data.write(to: url)
            let header = try PNGTextChunks.read(fromHeaderOf: url)
            #expect(header == (try PNGTextChunks.read(from: data)), "\(fixture.name)")
            #expect(header.count == fixture.entries.count)
        }
    }

    @Test("text written after the image data is not seen by the header read, as intended")
    func textAfterImageDataIsSkipped() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = Array(MockBackend.pngData)
        let end = try #require(try PNGTextChunks.spans(in: bytes).first { $0.type == "IEND" })
        var trailing = Data(bytes[..<end.start])
        trailing.append(try PNGTextChunks.chunk(for: (keyword: "Author", text: "afterwards")))
        trailing.append(contentsOf: bytes[end.start...])
        let url = folder.appending(path: "trailing.png")
        try trailing.write(to: url)

        #expect(try PNGTextChunks.read(from: trailing)["Author"] == "afterwards")
        #expect(try PNGTextChunks.read(fromHeaderOf: url)["Author"] == nil)
    }

    @Test("a file that stops in the middle of a chunk is refused, not guessed at")
    func truncatedFileThrows() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try PNGTextChunks.inserting(
            [(keyword: "Software", text: "Zephra")], into: MockBackend.pngData)
        // Cut inside a text chunk's body: the chunk claims more bytes than the file holds, which
        // is the difference between a file that merely stops early and one that is malformed.
        let text = try #require(try PNGTextChunks.spans(in: Array(data)).first { $0.type == "tEXt" })
        let url = folder.appending(path: "truncated.png")
        try data.prefix(text.start + 10).write(to: url)

        #expect(throws: PNGTextChunks.Failure.truncated) {
            try PNGTextChunks.read(fromHeaderOf: url)
        }
        let notAPNG = folder.appending(path: "not-a-png.png")
        try Data("this is not a picture".utf8).write(to: notAPNG)
        #expect(throws: PNGTextChunks.Failure.notAPNG) {
            try PNGTextChunks.read(fromHeaderOf: notAPNG)
        }
    }

    @Test("replacing the same keyword twice leaves the file the size it was")
    func replacingDoesNotGrow() throws {
        let first = try PNGTextChunks.replacing(
            [(keyword: "zephra:library", text: #"{"isFavourite":true}"#)],
            in: MockBackend.pngData
        )
        let second = try PNGTextChunks.replacing(
            [(keyword: "zephra:library", text: #"{"isFavourite":true}"#)],
            in: first
        )
        #expect(second == first)

        let changed = try PNGTextChunks.replacing(
            [(keyword: "zephra:library", text: #"{"isFavourite":TRUE}"#)],
            in: first
        )
        #expect(changed.count == first.count, "text of the same length, file of the same size")
        #expect(try PNGTextChunks.read(from: changed)["zephra:library"] == #"{"isFavourite":TRUE}"#)
    }

    @Test("replacing keeps the other keywords and copies the image data verbatim")
    func replacingKeepsEverythingElse() throws {
        let original = try PNGTextChunks.inserting(
            [
                (keyword: "Software", text: "Zephra 0.1.0"),
                (keyword: "zephra:generation", text: #"{"seed":42}"#),
            ],
            into: MockBackend.pngData
        )
        let rewritten = try PNGTextChunks.replacing(
            [(keyword: "zephra:library", text: "{}")], in: original)

        let text = try PNGTextChunks.read(from: rewritten)
        #expect(text["Software"] == "Zephra 0.1.0")
        #expect(text["zephra:generation"] == #"{"seed":42}"#)
        #expect(text["zephra:library"] == "{}")

        let was = try #require(try PNGTextChunks.spans(in: Array(original)).first { $0.type == "IDAT" })
        let now = try #require(try PNGTextChunks.spans(in: Array(rewritten)).first { $0.type == "IDAT" })
        #expect(Array(Array(rewritten)[now.start...]) == Array(Array(original)[was.start...]))
    }

    private static func folder() throws -> URL {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "PNGHeaderReadingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
