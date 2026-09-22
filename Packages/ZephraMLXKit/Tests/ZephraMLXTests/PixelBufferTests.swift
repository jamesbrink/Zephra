import CoreGraphics
import Foundation
import ImageIO
import MLX
import Testing
import ZephraMLX

@Suite("Decoded pixels become bytes on the nearest step of 255")
struct PixelBufferTests {
    /// The RGBA8 bytes Image I/O reads back out of a PNG, alpha included.
    ///
    /// `premultipliedLast` rather than the `noneSkipLast` this read through before there was
    /// any alpha to see: a context that skips the fourth byte cannot tell a transparent
    /// picture from an opaque one. Every fixture below that carries alpha is fully opaque or
    /// fully clear, so premultiplied and straight are the same bytes for all of them.
    private static func decoded(_ png: Data) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drawn)
        return bytes
    }

    /// Whether a PNG declares itself as carrying alpha: `IHDR`'s colour type, at body offset 9
    /// of the first chunk, which for a PNG is always at byte 25.
    private static func colourType(_ png: Data) -> UInt8 {
        Array(png)[25]
    }

    // MARK: Three channels, which is every model that came before transparency

    @Test("a channel value lands on the nearest byte, not the one below")
    func roundsToTheNearestByte() throws {
        // 0 is 127.5, which rounds to 128; -0.996 is 0.51, which rounds to 1 and would have
        // truncated to 0; 0.5 is 191.25, which rounds down to 191.
        let pixels = MLXArray([Float](arrayLiteral: 0, -0.996, 0.5, -1, 1, 0.996), [1, 1, 2, 3])
        #expect(try Array(PixelBuffer.rgba8(pixels)) == [128, 1, 191, 255, 0, 255, 254, 255])
    }

    @Test("values past the range are clipped rather than wrapped")
    func clipsOutOfRange() throws {
        let pixels = MLXArray([Float](arrayLiteral: -3, 3, 1.001), [1, 1, 1, 3])
        #expect(try Array(PixelBuffer.rgba8(pixels)) == [0, 255, 255, 255])
    }

    @Test("the PNG holds the same bytes rgba8 packs, in the same order, and declares no alpha")
    func pngCarriesTheSameBytes() throws {
        let pixels = MLXRandom.uniform(low: -1, high: 1, [1, 3, 5, 3], key: MLXRandom.key(9))
        let png = try PixelBuffer.png(from: pixels)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "a PNG signature")
        #expect(Self.colourType(png) == 2, "truecolour, exactly as it has always been written")
        #expect(try Self.decoded(png) == Array(PixelBuffer.rgba8(pixels)))
    }

    @Test("only the first image of a batch is encoded")
    func firstImageOfABatch() throws {
        let pixels = MLX.concatenated(
            [MLXArray.full([1, 2, 2, 3], values: MLXArray(Float(1))),
             MLXArray.full([1, 2, 2, 3], values: MLXArray(Float(-1)))], axis: 0)
        #expect(try Array(PixelBuffer.rgba8(pixels)).allSatisfy { $0 == 255 })
        #expect(try Self.decoded(try PixelBuffer.png(from: pixels)).allSatisfy { $0 == 255 })
    }

    // MARK: Four channels, which is a model that makes transparency

    @Test("a fourth channel is packed as it stands rather than replaced with 255")
    func fourthChannelSurvives() throws {
        // Two pixels: an opaque white and a fully clear mid grey.
        let pixels = MLXArray([Float](arrayLiteral: 1, 1, 1, 1, 0, 0, 0, -1), [1, 1, 2, 4])
        #expect(try Array(PixelBuffer.rgba8(pixels)) == [255, 255, 255, 255, 128, 128, 128, 0])
    }

    @Test("a PNG from four channels declares colour type 6 and reads its alpha back")
    func fourChannelPNGCarriesAlpha() throws {
        let pixels = MLXArray([Float](arrayLiteral: 1, -1, -1, 1, -1, -1, 1, -1), [1, 1, 2, 4])
        let png = try PixelBuffer.png(from: pixels)

        #expect(Self.colourType(png) == 6, "truecolour with alpha")
        // The clear pixel's colour is premultiplied away by the read, which is what a straight
        // alpha of 0 means; the byte that matters here is the fourth.
        let bytes = try Self.decoded(png)
        #expect(Array(bytes[0..<4]) == [255, 0, 0, 255])
        #expect(bytes[7] == 0, "the second pixel is clear")
    }

    @Test("a decode of any other width is refused rather than written four bytes to a pixel")
    func refusesAnyOtherWidth() {
        #expect(throws: PixelBufferError.unsupportedChannelCount(5)) {
            _ = try PixelBuffer.rgba8(MLXArray.full([1, 1, 1, 5], values: MLXArray(Float(0))))
        }
        #expect(throws: PixelBufferError.unsupportedChannelCount(1)) {
            _ = try PixelBuffer.png(from: MLXArray.full([1, 2, 2, 1], values: MLXArray(Float(0))))
        }
    }
}
