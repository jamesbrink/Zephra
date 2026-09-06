import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("frames become bytes the way the reference rounds them")
struct FramesTests {
    @Test("every channel lands on the nearest byte, clipped, with an opaque alpha")
    func roundingMatchesTheReference() throws {
        let fixture = try Fixture.load("frames")
        let pixels = try #require(fixture["in.pixels"])  // [2, 4, 5, 3]
        let expected = try #require(fixture["out.bytes"]).asType(.uint8).asData().data  // [2, 4, 5, 3]

        let video = LTX2Frames.video(pixels.expandedDimensions(axis: 0), frameRate: 24)
        #expect(video.frameCount == 2)
        #expect(video.height == 4)
        #expect(video.width == 5)
        #expect(video.pixels.count == 2 * 4 * 5 * 4)

        var rgb = Data()
        var alphas = Set<UInt8>()
        for (index, byte) in video.pixels.enumerated() {
            if index % 4 == 3 { alphas.insert(byte) } else { rgb.append(byte) }
        }
        #expect(rgb == expected)
        #expect(alphas == [255])
    }

    @Test("the poster is a PNG of the first frame at the clip's size")
    func poster() throws {
        let video = MLXArray.zeros([1, 3, 6, 8, 3])
        let png = try LTX2Frames.posterPNG(video)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        // IHDR: width and height as big-endian 32-bit at offsets 16 and 20.
        let width = png[16..<20].reduce(0) { $0 << 8 | Int($1) }
        let height = png[20..<24].reduce(0) { $0 << 8 | Int($1) }
        #expect(width == 8)
        #expect(height == 6)
    }

    @Test("a frame is addressed by its offset in the one buffer")
    func frameSlices() {
        let video = LTX2Frames.video(MLXArray.zeros([1, 3, 2, 2, 3]), frameRate: 24)
        #expect(video.frameBytes == 16)
        #expect(video.frame(2).count == 16)
        #expect(video.frame(2) == video.pixels.suffix(16))
    }
}
