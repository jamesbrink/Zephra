import CoreGraphics
import Foundation
import ImageIO
import MLX
import Testing
import ZephraMLX

@testable import Flux2

@Suite("Pixels go out as PNG and come back in fitted to the reference's grid")
struct PixelBufferTests {
    /// A solid-colour PNG of the given size, drawn with Core Graphics.
    private static func solidPNG(width: Int, height: Int, red: CGFloat) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.5, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let bitmap = NSBitmapImageRepStandIn.png(image)
        return try #require(bitmap)
    }

    @Test("an image survives the trip out to PNG and back to within a step of 255")
    func roundTrip() throws {
        let pixels = MLXRandom.uniform(low: -1, high: 1, [1, 48, 64, 3], key: MLXRandom.key(5))
        let png = try PixelBuffer.png(from: pixels)
        let back = try Flux2PixelBuffer.pixels(from: png)
        #expect(back.shape == [1, 3, 48, 64])
        #expect(Fixture.maxAbsoluteDifference(back.transposed(0, 2, 3, 1), pixels) < 2.0 / 255)
    }

    @Test("a picture is scaled to a megapixel keeping its shape and trimmed to multiples of 16")
    func fitting() {
        let cases: [(Int, Int, Int, Int)] = [
            (2048, 1152, 1360, 768), (1024, 1024, 1024, 1024), (100, 100, 96, 96),
            (1536, 512, 1536, 512), (1000, 600, 992, 592),
        ]
        for (width, height, fittedWidth, fittedHeight) in cases {
            let target = Flux2ImageFitting.target(width: width, height: height)
            #expect(target.width == fittedWidth && target.height == fittedHeight,
                    Comment(rawValue: "\(width)x\(height) -> \(target.width)x\(target.height)"))
            #expect(target.width % 16 == 0 && target.height % 16 == 0)
            #expect(target.width * target.height <= Flux2ImageFitting.maximumArea)
        }
    }

    @Test("the trim is a centre crop, never a black bar down one edge")
    func cropNotLetterbox() throws {
        let png = try Self.solidPNG(width: 1000, height: 600, red: 0.8)
        let pixels = try Flux2PixelBuffer.pixels(from: png)
        #expect(pixels.shape == [1, 3, 592, 992])
        // A letterboxed edge would sit at -1; a solid picture has one value everywhere.
        let spread = (MLX.max(pixels[0, 0]) - MLX.min(pixels[0, 0])).item(Float.self)
        #expect(spread < 2.0 / 255)
        #expect(MLX.min(pixels[0, 0]).item(Float.self) > 0.5)
    }

    @Test("bytes that are not a picture are refused, not decoded into something")
    func unreadable() {
        #expect(throws: Flux2PipelineError.unreadableReference) {
            try Flux2PixelBuffer.pixels(from: Data([1, 2, 3, 4]))
        }
    }
}

/// PNG encoding for the test's own bitmaps, through Image I/O like the code under test.
private enum NSBitmapImageRepStandIn {
    static func png(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
