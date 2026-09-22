import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The one seeking walk over a PNG's header: its text, its size, and whether it carries alpha.
@Suite("A PNG's header read in one seeking walk")
struct PNGHeaderTests {
    @Test("a text chunk larger than the body limit is stepped over, and the text after it found")
    func stepsOverAHugeChunk() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // What an edit's reference picture weighs: past every size the old prefix read grew to,
        // which sent the whole file through `Data(contentsOf:)`.
        let huge = String(repeating: "R", count: 2 << 20)
        let data = try PNGTextChunks.inserting(
            [
                (keyword: "zephra:reference", text: huge),
                (keyword: "zephra:generation", text: #"{"seed":42}"#),
            ],
            into: MockBackend.pngData
        )
        let url = folder.appending(path: "edit.png")
        try data.write(to: url)

        let header = try PNGHeader.read(fromHeaderOf: url)
        #expect(header.text["zephra:generation"] == #"{"seed":42}"#)
        #expect(header.text["zephra:reference"] == nil, "too large to read is too large to keep")
        #expect(header.size == ImageSize(width: 1, height: 1))
    }

    @Test("a file whose image data is cut off still reads its header")
    func aTruncatedTailStillReads() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try PNGTextChunks.inserting(
            [(keyword: "Software", text: "Zephra 0.1.0")], into: MockBackend.pngData)
        let bytes = Array(data)
        let image = try #require(try PNGTextChunks.spans(in: bytes).first { $0.type == "IDAT" })
        let url = folder.appending(path: "cut.png")
        // Everything up to the image data's own bytes: a walk that stops at `IDAT` answers,
        // and a walk that had to reach `IEND` could not.
        try Data(bytes[..<(image.start + 10)]).write(to: url)

        #expect(try PNGHeader.read(fromHeaderOf: url).text["Software"] == "Zephra 0.1.0")
    }

    @Test("colour type 6 and colour type 4 carry alpha, and colour type 2 does not")
    func colourTypeSaysWhetherThereIsAlpha() throws {
        #expect(try Self.header(colourType: 6).hasAlpha)
        #expect(try Self.header(colourType: 4).hasAlpha)
        #expect(try !Self.header(colourType: 2).hasAlpha)
        #expect(try !Self.header(colourType: 0).hasAlpha)
        #expect(try !Self.header(colourType: 3).hasAlpha, "a palette with no tRNS is opaque")
    }

    @Test("a palette picture carries alpha through its tRNS chunk")
    func paletteTransparency() throws {
        let header = try PNGHeader.read(from: Self.png(colourType: 3, transparency: true))
        #expect(header.hasAlpha)
    }

    @Test("the header read and the in-memory read agree, from the file and from the bytes")
    func bothReadersAgree() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = Self.png(colourType: 6, transparency: false)
        let url = folder.appending(path: "rgba.png")
        try data.write(to: url)

        #expect(try PNGHeader.read(fromHeaderOf: url) == (try PNGHeader.read(from: data)))
        #expect(try PNGHeader.read(fromHeaderOf: url).hasAlpha)
    }

    @Test("bytes that are not a PNG are refused rather than guessed at")
    func refusesRubbish() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "not-a-png.png")
        try Data("this is not a picture at all".utf8).write(to: url)

        #expect(throws: PNGTextChunks.Failure.notAPNG) { try PNGHeader.read(fromHeaderOf: url) }
        #expect(throws: PNGTextChunks.Failure.notAPNG) {
            try PNGHeader.read(from: Data("no".utf8))
        }
    }

    private static func header(colourType: UInt8) throws -> PNGHeader {
        try PNGHeader.read(from: png(colourType: colourType, transparency: false))
    }

    /// A PNG carrying a header, optionally a `tRNS`, and an empty run of image data.
    static func png(colourType: UInt8, transparency: Bool) -> Data {
        var body = Data()
        for value in [UInt32(4), UInt32(3)] {
            body.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) })
        }
        body.append(contentsOf: [8, colourType, 0, 0, 0] as [UInt8])
        var png = Data(PNGTextChunks.signature)
        png.append(chunk(type: "IHDR", body: body))
        if transparency { png.append(chunk(type: "tRNS", body: Data([0, 128, 255]))) }
        png.append(chunk(type: "IDAT", body: Data()))
        png.append(chunk(type: "IEND", body: Data()))
        return png
    }

    private static func chunk(type: String, body: Data) -> Data {
        var typed = Data(type.utf8)
        typed.append(body)
        var result = Data((0..<4).map { UInt8(truncatingIfNeeded: UInt32(body.count) >> (24 - 8 * $0)) })
        result.append(typed)
        let crc = PNGTextChunks.crc32(typed)
        result.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: crc >> (24 - 8 * $0)) })
        return result
    }

    private static func folder() throws -> URL {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "PNGHeaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
