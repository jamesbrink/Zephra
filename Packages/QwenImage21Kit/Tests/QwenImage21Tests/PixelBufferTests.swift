import CoreGraphics
import Foundation
import ImageIO
import MLX
import Testing

@testable import QwenImage21

@Suite("four channels reach a byte, alpha included")
struct PixelBufferTests {
    /// Two pixels: one fully transparent black, one fully opaque white, then two mid values.
    static func pixels() -> MLXArray {
        MLXArray(
            [
                -1.0, -1.0, -1.0, -1.0,
                1.0, 1.0, 1.0, 1.0,
                0.0, -1.0, 1.0, 0.0,
                -1.0, 1.0, 0.0, -0.5,
            ] as [Float], [1, 2, 2, 4])
    }

    @Test("the pixel range maps onto the byte range, rounded rather than truncated")
    func scaling() {
        let bytes = [UInt8](QwenImage21PixelBuffer.rgba8(Self.pixels()))
        #expect(bytes.count == 2 * 2 * 4)
        #expect(Array(bytes[0..<4]) == [0, 0, 0, 0], "transparent black")
        #expect(Array(bytes[4..<8]) == [255, 255, 255, 255], "opaque white")
        // 0 is the middle of -1 to 1, and (0 + 1) * 127.5 = 127.5, which rounds up.
        #expect(Array(bytes[8..<12]) == [128, 0, 255, 128])
        // -0.5 is (0.5) * 127.5 = 63.75, which rounds to 64.
        #expect(Array(bytes[12..<16]) == [0, 255, 128, 64])
    }

    @Test("alpha is the fourth channel's own value and never an invented 255")
    func alphaIsTheDecodes() {
        let bytes = [UInt8](QwenImage21PixelBuffer.rgba8(Self.pixels()))
        #expect([bytes[3], bytes[7], bytes[11], bytes[15]] == [0, 255, 128, 64])
    }

    @Test("the PNG is RGBA with straight alpha, and reads back byte for byte")
    func pngRoundTrips() throws {
        let data = try QwenImage21PixelBuffer.png(from: Self.pixels())
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 2)
        #expect(image.height == 2)
        #expect(image.alphaInfo == .last, "straight alpha, never premultiplied")
        #expect(image.bitsPerPixel == 32)

        // The provider's own bytes, not a redraw: a `CGContext` cannot be made in a straight
        // alpha format at all -- CoreGraphics offers premultiplied or skipped and nothing
        // between -- so drawing the image into one to read it back would either fail or
        // premultiply the very thing under test.
        let read = [UInt8](try #require(image.dataProvider?.data) as Data)
        #expect(read == [UInt8](QwenImage21PixelBuffer.rgba8(Self.pixels())))
    }

    @Test("a decoded picture's bytes are its own, alpha edge and all")
    func decodedPicture() throws {
        let fixture = try Fixture.load("vae")
        let autoencoder = try VAEFixture.dollsHouseAutoencoder(fixture)
        let latent = VAEFixture.channelsLast(try #require(fixture["out.latents"]))
        let picture = autoencoder.decode(latent)
        let bytes = [UInt8](QwenImage21PixelBuffer.rgba8(picture))
        #expect(bytes.count == 16 * 16 * 4)
        let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        #expect(Set(alpha).count > 1, "the reference picture's alpha edge survived the round trip")
    }
}
