import Foundation
import Testing

@testable import ZephraEngine

@Suite("PNGTextChunks")
struct PNGTextChunksTests {
    @Test("inserted text reads back, in Latin-1 and in UTF-8")
    func roundTrip() throws {
        let annotated = try PNGTextChunks.inserting(
            [
                (keyword: "Software", text: "Zephra 0.1.0"),
                (keyword: "Description", text: "a lighthouse at dusk — fog rolling in 🌊"),
            ],
            into: MockBackend.pngData
        )

        let text = try PNGTextChunks.read(from: annotated)
        #expect(text["Software"] == "Zephra 0.1.0")
        #expect(text["Description"] == "a lighthouse at dusk — fog rolling in 🌊")
        // Plain text goes in a tEXt; anything past Latin-1 needs an iTXt.
        let types = try PNGTextChunks.spans(in: Array(annotated)).map(\.type)
        #expect(types.contains("tEXt"))
        #expect(types.contains("iTXt"))
    }

    @Test("every chunk written carries a correct CRC-32")
    func checksums() throws {
        // The reference check value for CRC-32, from the specification.
        #expect(PNGTextChunks.crc32(Data("123456789".utf8)) == 0xCBF4_3926)

        let annotated = try PNGTextChunks.inserting(
            [(keyword: "zephra:generation", text: #"{"seed":42}"#)],
            into: MockBackend.pngData
        )
        let bytes = Array(annotated)
        for span in try PNGTextChunks.spans(in: bytes) {
            let covered = Data(bytes[(span.start + 4)..<span.body.upperBound])
            let stored = PNGTextChunks.be32(bytes, at: span.body.upperBound)
            #expect(PNGTextChunks.crc32(covered) == stored, "bad CRC on \(span.type)")
        }
    }

    @Test("inserting into a file that already has text keeps what was there")
    func keepsExistingText() throws {
        let once = try PNGTextChunks.inserting(
            [(keyword: "Author", text: "someone else")],
            into: MockBackend.pngData
        )
        let twice = try PNGTextChunks.inserting(
            [(keyword: "Software", text: "Zephra")],
            into: once
        )

        let text = try PNGTextChunks.read(from: twice)
        #expect(text["Author"] == "someone else")
        #expect(text["Software"] == "Zephra")
    }

    @Test("the pixel data is not touched")
    func pixelsUnchanged() throws {
        let original = Array(MockBackend.pngData)
        let annotated = try PNGTextChunks.inserting(
            [(keyword: "Software", text: "Zephra")],
            into: MockBackend.pngData
        )
        let bytes = Array(annotated)

        let firstIDAT = try #require(PNGTextChunks.spans(in: bytes).first { $0.type == "IDAT" })
        let wasFirstIDAT = try #require(PNGTextChunks.spans(in: original).first { $0.type == "IDAT" })
        #expect(Array(bytes[firstIDAT.start...]) == Array(original[wasFirstIDAT.start...]))
        #expect(bytes.count > original.count)
        // And everything before the insertion point, the header included, is untouched too.
        #expect(Array(bytes[..<wasFirstIDAT.start]) == Array(original[..<wasFirstIDAT.start]))
    }

    @Test("anything that is not a PNG is refused")
    func rejectsNonPNG() throws {
        let notAPNG = Data("this is not a picture".utf8)
        #expect(throws: PNGTextChunks.Failure.notAPNG) { try PNGTextChunks.read(from: notAPNG) }
        #expect(throws: PNGTextChunks.Failure.notAPNG) {
            try PNGTextChunks.inserting([(keyword: "Software", text: "Zephra")], into: notAPNG)
        }

        // A real signature with a chunk that runs off the end is a truncated file, not a
        // different format, and says so.
        var truncated = Data(PNGTextChunks.signature)
        truncated.append(contentsOf: [0, 0, 0, 32, 0x49, 0x48, 0x44, 0x52])
        #expect(throws: PNGTextChunks.Failure.truncated) { try PNGTextChunks.read(from: truncated) }
    }

    @Test("an iTXt flagged as compressed reads as nothing, rather than as garbage")
    func compressedITXtIsSkipped() throws {
        // Keyword, terminator, compression flag 1, method 0, empty language tag and translated
        // keyword, then bytes that are deflate output rather than text.
        var body = Data("Description".utf8)
        body.append(contentsOf: [0, 1, 0, 0, 0])
        body.append(contentsOf: [0x78, 0x9C, 0x4B, 0x4C, 0x4A, 0x06, 0x00, 0x02, 0x4D, 0x01, 0x27])
        let annotated = try Self.splicing(chunk(type: "iTXt", body: body), into: MockBackend.pngData)

        let text = try PNGTextChunks.read(from: annotated)
        #expect(
            text["Description"] == nil,
            "Zephra never writes compressed text, so it is skipped rather than mis-decoded"
        )
        // The chunk really is there and really is an iTXt; it is the flag that stops the read.
        #expect(try PNGTextChunks.spans(in: Array(annotated)).map(\.type).contains("iTXt"))
    }

    @Test("a PNG with no image data is refused rather than written to")
    func rejectsPNGWithoutIDAT() throws {
        var headerOnly = Data(PNGTextChunks.signature)
        headerOnly.append(chunk(type: "IHDR", body: Data(repeating: 0, count: 13)))
        headerOnly.append(chunk(type: "IEND", body: Data()))

        // It parses: the chunks are well formed, there is simply nothing to splice ahead of.
        #expect(try PNGTextChunks.read(from: headerOnly).isEmpty)
        #expect(throws: PNGTextChunks.Failure.noImageData) {
            try PNGTextChunks.inserting([(keyword: "Software", text: "Zephra")], into: headerOnly)
        }
    }

    @Test("a keyword PNG would not accept is refused")
    func rejectsBadKeyword() {
        for keyword in ["", " leading", "trailing ", String(repeating: "x", count: 80)] {
            #expect(throws: PNGTextChunks.Failure.invalidKeyword(keyword)) {
                try PNGTextChunks.inserting([(keyword: keyword, text: "x")], into: MockBackend.pngData)
            }
        }
    }
}
