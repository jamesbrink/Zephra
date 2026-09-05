import CoreGraphics
import Foundation
import ImageIO
import MLX
import Testing
import ZephraMLX

@Suite("Decoded pixels become bytes on the nearest step of 255")
struct PixelBufferTests {
    /// The RGBA8 bytes Image I/O reads back out of a PNG.
    private static func decoded(_ png: Data) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drawn)
        return bytes
    }

    @Test("a channel value lands on the nearest byte, not the one below")
    func roundsToTheNearestByte() {
        // 0 is 127.5, which rounds to 128; -0.996 is 0.51, which rounds to 1 and would have
        // truncated to 0; 0.5 is 191.25, which rounds down to 191.
        let pixels = MLXArray([Float](arrayLiteral: 0, -0.996, 0.5, -1, 1, 0.996), [1, 1, 2, 3])
        #expect(Array(PixelBuffer.rgba8(pixels)) == [128, 1, 191, 255, 0, 255, 254, 255])
    }

    @Test("values past the range are clipped rather than wrapped")
    func clipsOutOfRange() {
        let pixels = MLXArray([Float](arrayLiteral: -3, 3, 1.001), [1, 1, 1, 3])
        #expect(Array(PixelBuffer.rgba8(pixels)) == [0, 255, 255, 255])
    }

    @Test("the PNG holds the same bytes rgba8 packs, in the same order")
    func pngCarriesTheSameBytes() throws {
        let pixels = MLXRandom.uniform(low: -1, high: 1, [1, 3, 5, 3], key: MLXRandom.key(9))
        let png = try PixelBuffer.png(from: pixels)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "a PNG signature")
        #expect(try Self.decoded(png) == Array(PixelBuffer.rgba8(pixels)))
    }

    @Test("only the first image of a batch is encoded")
    func firstImageOfABatch() throws {
        let pixels = MLX.concatenated(
            [MLXArray.full([1, 2, 2, 3], values: MLXArray(Float(1))),
             MLXArray.full([1, 2, 2, 3], values: MLXArray(Float(-1)))], axis: 0)
        #expect(Array(PixelBuffer.rgba8(pixels)).allSatisfy { $0 == 255 })
        #expect(try Self.decoded(try PixelBuffer.png(from: pixels)).allSatisfy { $0 == 255 })
    }
}
