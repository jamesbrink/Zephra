import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Reading the two numbers a PNG declares about itself, which is how an upscale learns what
/// actually came back rather than assuming the parent's size times the factor.
@Suite("The size a PNG declares in its own header")
struct PNGImageSizeTests {
    @Test("the one-pixel fixture every other suite writes reads as one by one")
    func theFixtureReadsAsItself() {
        #expect(PNGImageSize.read(from: MockBackend.pngData) == ImageSize(width: 1, height: 1))
    }

    @Test("an edge past a thousand pixels survives the big-endian read")
    func largeEdges() {
        #expect(
            PNGImageSize.read(from: Self.png(width: 4096, height: 2048))
                == ImageSize(width: 4096, height: 2048))
        #expect(
            PNGImageSize.read(from: Self.png(width: 1328, height: 768))
                == ImageSize(width: 1328, height: 768))
    }

    @Test("text chunks spliced in ahead of the image data do not move the header")
    func annotatingDoesNotChangeTheAnswer() throws {
        let annotated = try PNGTextChunks.inserting(
            [(keyword: "Description", text: "a lighthouse at dusk")], into: MockBackend.pngData)
        #expect(PNGImageSize.read(from: annotated) == ImageSize(width: 1, height: 1))
    }

    @Test("bytes that are not a PNG, stop before the header, or claim no size read as nothing")
    func nothingToRead() {
        #expect(PNGImageSize.read(from: Data("not a picture".utf8)) == nil)
        #expect(PNGImageSize.read(from: Data()) == nil)
        #expect(PNGImageSize.read(from: MockBackend.pngData.prefix(20)) == nil)
        #expect(PNGImageSize.read(from: Self.png(width: 0, height: 0)) == nil)
    }

    /// A PNG carrying nothing but a header and an empty run of image data, so a size can be
    /// asserted at edges no fixture picture would be worth storing at.
    static func png(width: Int, height: Int) -> Data {
        var header = Data()
        for value in [UInt32(width), UInt32(height)] {
            header.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) })
        }
        header.append(contentsOf: [8, 2, 0, 0, 0] as [UInt8])
        var png = Data(PNGTextChunks.signature)
        png.append(chunk(type: "IHDR", body: header))
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
}
